(local fennel (require :fennel))
(local fs (require :fs))
(local Targets (require :constraints.targets))
(local Source (require :constraints.source))

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
