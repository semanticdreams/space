(local fennel (require :fennel))
(local fs (require :fs))
(local ts (require :tree-sitter))
(local Targets (require :constraints.targets))
(local Source (require :constraints.source))
(local Facts (require :constraints.facts))
(local Runner (require :constraints.runner))

(fn fnl-path? [path]
  (and (= (type path) :string)
       (not= (path:match "%.fnl$") nil)))

(fn diagnostic-hint [message]
  (local text (tostring (if message message "")))
  (local delimiter-message?
    (if (text:match "delimiter")
        true
        (text:match "expected.*%)")
        true
        (text:match "expected.*%]")
        true
        (text:match "expected.*%}")
        true
        false))
  (if delimiter-message?
      "Check the enclosing form and delimiter balance near the reported location."
      "Compile the file with the project Fennel runtime and inspect the reported form."))

(fn parse-location [message]
  (local text (tostring (if message message "")))
  (var line nil)
  (var column nil)
  (local (line-text column-text) (text:match ":(%d+):(%d+):"))
  (when line-text
    (set line (tonumber line-text))
    (set column (tonumber column-text)))
  (when (not line)
    (local only-line (text:match ":(%d+):"))
    (when only-line
      (set line (tonumber only-line))))
  (values line column))

(fn input-diagnostic [path message]
  {:kind :input
   :file (if path (fs.absolute path) "")
   :line nil
   :column nil
   :message message
   :hint "Pass one or more existing .fnl source files."})

(fn compile-diagnostic [path err]
  (local message (tostring err))
  (local (line column) (parse-location message))
  {:kind :compile
   :file (fs.absolute path)
   :line line
   :column column
   :message message
   :hint (diagnostic-hint message)})

(fn macro-module? [path module]
  (if (= module "macros")
      true
      (and (= (type path) :string)
           (if (path:match "/macros%.fnl$")
               true
               (path:match "/init%-macros%.fnl$")
               true
               false))))

(fn compile-options [path module]
  (local opts {:filename path
               :module-name module
               :correlate true})
  (when (macro-module? path module)
    (tset opts :env "_COMPILER")
    (tset opts :scope "_COMPILER"))
  opts)

(fn compile-file-source [path source module]
  (local (ok err) (pcall (fn []
                           (fennel.compile-string source (compile-options path module)))))
  (if ok
      nil
      (compile-diagnostic path err)))

(fn compile-file [path]
  (local source (fs.read-file path))
  (compile-file-source path source nil))

(fn read-fnl-file [path]
  (local absolute (fs.absolute path))
  (if (fnl-path? absolute)
      (do
        (local (ok source-or-err) (pcall #(fs.read-file absolute)))
        (if ok
            (values absolute source-or-err nil)
            (values absolute nil (input-diagnostic absolute (tostring source-or-err)))))
      (values absolute nil (input-diagnostic absolute (.. "expected a .fnl file, got " (tostring path))))))

(fn node-text [source node]
  (source:sub (+ (node:start-byte) 1) (node:end-byte)))

(fn node-start-location [node]
  (local pt (node:start-point))
  {:line (+ pt.row 1)
   :column (+ pt.column 1)})

(fn node-end-location [node]
  (local pt (node:end-point))
  {:line (+ pt.row 1)
   :column (+ pt.column 1)})

(fn node-has-error? [node]
  (var found (= (node:type) "ERROR"))
  (var i 0)
  (while (and (not found) (< i (node:child-count)))
    (when (node-has-error? (node:child i))
      (set found true))
    (set i (+ i 1)))
  found)

(fn files-argv [files]
  (local argv ["--target" "files"])
  (local input-files (if files files []))
  (each [_ file (ipairs input-files)]
    (table.insert argv "--file")
    (table.insert argv file))
  argv)

(fn parse-file [path]
  (local (absolute source diagnostic) (read-fnl-file path))
  (if diagnostic
      (values absolute source nil nil diagnostic)
      (do
        (local tree (ts.parse source {:language :fennel}))
        (local root (tree:root))
        (values absolute source tree root nil))))

(fn bounded-sexpr [root max-chars]
  (local (ok sexpr-or-err) (pcall #(root:sexpr)))
  (local sexpr (if ok sexpr-or-err (tostring sexpr-or-err)))
  (local limit (if max-chars max-chars 8000))
  (if (> (# sexpr) limit)
      (values (sexpr:sub 1 limit) true)
      (values sexpr false)))

(fn parse-tree [args]
  (local (absolute _source _tree root diagnostic) (parse-file args.file))
  (if diagnostic
      {:ok false
       :file absolute
       :root-type ""
       :sexpr ""
       :truncated? false
       :diagnostics [diagnostic]}
      (do
        (local (sexpr truncated?) (bounded-sexpr root args.max-chars))
        (local has-error? (node-has-error? root))
        (local diagnostics [])
        (when has-error?
          (table.insert diagnostics
            {:kind :parse
             :file absolute
             :line nil
             :column nil
             :message "tree-sitter reported ERROR nodes while parsing Fennel source"
             :hint "Inspect the nearest enclosing form and delimiter balance."}))
        {:ok (not has-error?)
         :file absolute
         :root-type (root:type)
         :sexpr sexpr
         :truncated? truncated?
         :diagnostics diagnostics})))

(fn byte-offset-at-line-column [source line column]
  (local target-line (tonumber line))
  (local target-column (tonumber column))
  (if (if target-line
          (if target-column
              (if (< target-line 1) true (< target-column 1))
              true)
          true)
      nil
      (do
        (var current-line 1)
        (var line-start 1)
        (var i 1)
        (while (and (< current-line target-line) (<= i (# source)))
          (when (= (source:sub i i) "\n")
            (set current-line (+ current-line 1))
            (set line-start (+ i 1)))
          (set i (+ i 1)))
        (if (not= current-line target-line)
            nil
            (do
              (var line-end (+ (# source) 1))
              (var j line-start)
              (while (and (< j line-end) (<= j (# source)))
                (if (= (source:sub j j) "\n")
                    (set line-end j)
                    (set j (+ j 1))))
              (local pos (+ line-start target-column -1))
              (if (if (< pos line-start) true (>= pos line-end))
                  nil
                  (- pos 1)))))))

(fn closing-delimiter-for [first]
  (if (= first "(")
      ")"
      (= first "[")
      "]"
      (= first "{")
      "}"
      nil))

(fn delimited-text? [text]
  (local first (text:sub 1 1))
  (local closing (closing-delimiter-for first))
  (if closing
      (= (text:sub (# text)) closing)
      false))

(fn node-contains-offset? [node offset]
  (and (<= (node:start-byte) offset) (<= offset (node:end-byte))))

(fn node-byte-length [node]
  (- (node:end-byte) (node:start-byte)))

(fn better-delimited-node? [node best]
  (if (not best)
      true
      (< (node-byte-length node) (node-byte-length best))))

(fn smallest-delimited-node [source root offset]
  (var best nil)
  (fn visit [node]
    (when (node-contains-offset? node offset)
      (local text (node-text source node))
      (when (and (delimited-text? text) (better-delimited-node? node best))
        (set best node))
      (for [i 0 (- (node:child-count) 1)]
        (visit (node:child i)))))
  (visit root)
  best)

(fn enclosing-form [args]
  (local (absolute source _tree root diagnostic) (parse-file args.file))
  (if diagnostic
      {:ok false :file absolute :form "" :node-type "" :start {} :end {} :diagnostics [diagnostic]}
      (do
        (local offset (byte-offset-at-line-column source args.line args.column))
        (if (not offset)
            {:ok false
             :file absolute
             :form ""
             :node-type ""
             :start {}
             :end {}
             :diagnostics [{:kind :input
                            :file absolute
                            :line args.line
                            :column args.column
                            :message "location is outside the file"
                            :hint "Pass a 1-indexed line and column within the source file."}]}
            (do
              (local node (smallest-delimited-node source root offset))
              (if node
                  {:ok true
                   :file absolute
                   :form (node-text source node)
                   :node-type (node:type)
                   :start (node-start-location node)
                   :end (node-end-location node)
                   :diagnostics []}
                  {:ok false
                   :file absolute
                   :form ""
                   :node-type ""
                   :start {}
                   :end {}
                   :diagnostics [{:kind :parse
                                  :file absolute
                                  :line args.line
                                  :column args.column
                                  :message "no enclosing delimited form found"
                                  :hint "Choose a location inside a list, vector, or table form."}]}))))))

(fn structure-metrics [args]
  (local target (Targets.resolve (files-argv [args.file]) {}))
  (local records (Source.discover target))
  (local facts (Facts.extract records))
  (local file-facts (. facts.files 1))
  (local absolute (fs.absolute args.file))
  (if file-facts
      {:ok true
       :file file-facts.path
       :metrics file-facts.metrics
       :diagnostics []}
      {:ok false
       :file absolute
       :metrics {:module-lines 0 :max-nesting-depth 0 :functions []}
       :diagnostics [(input-diagnostic absolute "no Fennel source record found for file")]}))

(fn check-constraints-files [args]
  (local input-files (if args args.files []))
  (local target (Targets.resolve (files-argv input-files) {}))
  (Runner.run-target target {}))

(fn unique-sorted-absolute-paths [paths]
  (local absolute [])
  (each [_ path (ipairs (if paths paths []))]
    (table.insert absolute (fs.absolute path)))
  (table.sort absolute)
  (local seen {})
  (local result [])
  (each [_ path (ipairs absolute)]
    (when (not (. seen path))
      (tset seen path true)
      (table.insert result path)))
  result)

(fn finish-result [checked diagnostics]
  (local failed (# diagnostics))
  {:ok (= failed 0)
   :status (if (= failed 0) :pass :fail)
   :checked checked
   :diagnostics diagnostics
   :summary {:checked (# checked)
             :failed failed}})

(fn check-paths [paths]
  (local checked [])
  (local diagnostics [])
  (each [_ path (ipairs (unique-sorted-absolute-paths paths))]
    (if (fnl-path? path)
        (do
          (table.insert checked path)
          (local diagnostic (compile-file path))
          (when diagnostic
            (table.insert diagnostics diagnostic)))
        (table.insert diagnostics
          (input-diagnostic path (.. "expected a .fnl file, got " path)))))
  (finish-result checked diagnostics))

(fn target-paths [target]
  (local paths [])
  (local records (Source.discover target))
  (each [_ record (ipairs records)]
    (table.insert paths record.path))
  paths)

(fn check-records [records]
  (local checked [])
  (local diagnostics [])
  (each [_ record (ipairs (if records records []))]
    (table.insert checked record.path)
    (local diagnostic (compile-file-source record.path record.source record.module))
    (when diagnostic
      (table.insert diagnostics diagnostic)))
  (finish-result checked diagnostics))

(fn FennelValidationService [opts]
  (local options (if opts opts {}))
  {:opts options
    :resolve-target (fn [_self argv]
                      (Targets.resolve argv {}))
    :parse-tree (fn [_self args]
                  (parse-tree (if args args {})))
    :enclosing-form (fn [_self args]
                      (enclosing-form (if args args {})))
    :structure-metrics (fn [_self args]
                         (structure-metrics (if args args {})))
    :check-constraints-files (fn [_self args]
                               (check-constraints-files (if args args {})))
    :check-files (fn [_self args]
                   (check-paths (if args.files args.files [])))
   :check-repo (fn [self args]
                 (local target (self:resolve-target (if args args ["--target" "repo"])))
                 (self:check-target target))
    :check-target (fn [_self target]
                    (local (ok records-or-err) (pcall Source.discover target))
                    (if ok
                        (check-records records-or-err)
                        (finish-result [] [(input-diagnostic "" (tostring records-or-err))])))})

{:FennelValidationService FennelValidationService}
