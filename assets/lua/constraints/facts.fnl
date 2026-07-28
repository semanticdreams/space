;; Static fact extraction for experimental Fennel constraints.
;; Walks tree-sitter AST nodes to collect requires, definitions, exports,
;; calls, accesses, mutations, and metrics from Fennel source files.

(local M {})

;; Form node types that introduce a new nesting scope.
(local form-types
  {:local_form true
   :fn_form true
   :set_form true
   :global_form true
   :list true
   :table true
   :table_metadata true
   :sequential_table true})

(fn node-text [source node]
  "Extract the substring of source covered by a node."
  (source:sub (+ (node:start-byte) 1) (node:end-byte)))

(fn node-line-col [node]
  "Return {:line :column} for the start of a node (0-indexed to 1-indexed)."
  (let [pt (node:start-point)]
    {:line (+ pt.row 1)
     :column (+ pt.column 1)}))

(fn non-delimiter-children [node]
  "Return all children that are not delimiter tokens."
  (local result [])
  (for [i 0 (- (node:child-count) 1)]
    (let [c (node:child i)
          ct (c:type)]
      (when (not (or (= ct "(") (= ct ")") (= ct "{") (= ct "}")
                      (= ct "[") (= ct "]") (= ct ".") (= ct ":")
                      (= ct "\"") (= ct "'")))
        (table.insert result c))))
  result)

(fn split-colon-symbol [text]
  "Split a colon-style symbol like 'obj:method' into [receiver method]."
  (let [parts []]
    (each [segment (text:gmatch "[^:]+")]
      (table.insert parts segment))
    parts))

(fn split-dotted-symbol [text]
  "Split a dotted symbol like 'world.state.scene.panels' into path segments."
  (let [parts []]
    (each [segment (text:gmatch "[^%.]+")]
      (table.insert parts segment))
    parts))

(fn extract-module-name-from-string-node [source node]
  "Extract the module name from a string node (handles :keyword and \"string\")."
  (let [text (node-text source node)
        ntype (node:type)]
    (if (not= ntype "string")
        text
        (text:match "^:")
        (text:sub 2)
        (text:match "^\"")
        (text:gsub "^\"(.*)\"$" "%1")
        text)))

(fn is-table-node? [node-type]
  "Check if a node type is a table-like container."
  (or (= node-type :table)
      (= node-type :table_metadata)
      (= node-type :sequential_table)))

(fn table-pair-type [node-type]
  "Return the pair child type for table nodes."
  (if (= node-type :table) :table_pair
      (= node-type :table_metadata) :table_metadata_pair
      nil))

(fn count-table-elements [node]
  "Count key-value pairs or sequential elements in a table node."
  (let [ntype (node:type)]
    (if (= ntype :sequential_table)
        (length (non-delimiter-children node))
        (do
          (local pair-type (table-pair-type ntype))
          (if pair-type
              (do
                (var count 0)
                (for [i 0 (- (node:child-count) 1)]
                  (let [c (node:child i)]
                    (when (= (c:type) pair-type)
                      (set count (+ count 1)))))
                count)
              0)))))

(fn fn-name-from-node [source node]
  "Extract the function name from an fn_form node, or nil if anonymous.
  In the AST: fn_form children are: '(' 'symbol(fn)' [symbol(name)] args... ')'
  A named fn has a symbol as the 3rd child (index 2): '( fn name args... )'
  An anonymous fn has no name symbol: '( fn args... )'"
  (let [ndc (non-delimiter-children node)]
    (if (>= (length ndc) 2)
        (let [c2 (. ndc 2)]
          (if (= (c2:type) "symbol")
              (let [text (node-text source c2)]
                (if (not= text "fn") text nil))
              nil))
        nil)))

(fn enclosing-fn-name [fn-stack]
  "Return the name of the innermost function on fn-stack, or nil."
  (if (> (length fn-stack) 0)
      (. (. fn-stack (length fn-stack)) :name)
      nil))

(fn extract-file-facts [record]
  "Extract all static facts from a single file record."
  (let [source record.source
        root record.root
        facts {:target record.target
               :path record.path
               :module record.module
               :relative-path (or record.relative-path record.path)
               :requires []
               :definitions []
               :exports []
               :calls []
               :accesses []
               :mutations []
               :metrics {:module-lines 0
                         :max-nesting-depth 0
                         :max-anonymous-callback-depth 0
                         :max-table-literal-size 0
                         :functions []}}]

    ;; State during walk
    (var depth 0)
    (var fn-stack [])
    (var max-depth 0)
    (var max-anon-depth 0)

    ;; Compute module-lines from source line count
    (var line-count 1)
    (each [_ _ (source:gmatch "\n")]
      (set line-count (+ line-count 1)))
    (set facts.metrics.module-lines line-count)

    (fn visit [node]
      (let [node-type (node:type)
            is-form (. form-types node-type)]
        (when is-form
          (set depth (+ depth 1))
          (when (> depth max-depth)
            (set max-depth depth))
          ;; Update per-frame max depth for all active function frames
          (each [_ frame (ipairs fn-stack)]
            (when (> depth frame.frame-max-depth)
              (set frame.frame-max-depth depth))))

        ;; --- local_form ---
        (when (= node-type :local_form)
          (let [loc (node-line-col node)
                form (node-text source node)]
            ;; local_form children: ( symbol(local) binding_pair(symbol_binding value) )
            ;; Extract the binding name from symbol_binding inside binding_pair
            (var local-name nil)
            (var value-node nil)
            (for [i 0 (- (node:child-count) 1)]
              (let [c (node:child i)]
                (if (= (c:type) "binding_pair")
                    (for [j 0 (- (c:child-count) 1)]
                      (let [bp-c (c:child j)]
                        (if (= (bp-c:type) "symbol_binding")
                            (set local-name (node-text source bp-c))
                            (or (= (bp-c:type) "list")
                                (= (bp-c:type) "table")
                                (= (bp-c:type) "table_metadata")
                                (= (bp-c:type) "sequential_table")
                                (= (bp-c:type) "fn_form"))
                            (set value-node bp-c))))
                    (= (c:type) "symbol_binding")
                    (set local-name (node-text source c)))))
            (when local-name
              (table.insert facts.definitions
                {:kind :local
                 :name local-name
                 :top-level? (= depth 1)
                 :line loc.line
                 :column loc.column
                 :length (node:end-byte)
                 :form form
                 :enclosing-fn (enclosing-fn-name fn-stack)})
              ;; If value is a require form, extract module name
              (when (and value-node (= (value-node:type) "list"))
                (let [vndc (non-delimiter-children value-node)]
                  (when (and (>= (length vndc) 2)
                             (= (node-text source (. vndc 1)) "require"))
                    (let [mod-node (. vndc 2)
                          mod-name (extract-module-name-from-string-node source mod-node)
                          mod-loc (node-line-col value-node)]
                      (table.insert facts.requires
                        {:module mod-name
                         :line mod-loc.line
                         :column mod-loc.column
                         :form (node-text source value-node)}))))))))

        ;; --- fn_form ---
        (when (= node-type :fn_form)
          (let [fn-name (fn-name-from-node source node)
                loc (node-line-col node)
                form (node-text source node)
                is-top-level (= (length fn-stack) 0)
                anonymous? (not fn-name)
                enc-fn (enclosing-fn-name fn-stack)]
            (table.insert facts.definitions
              {:kind :fn
               :name (or fn-name "<anonymous>")
               :top-level? is-top-level
               :line loc.line
               :column loc.column
               :length (node:end-byte)
               :form form
               :enclosing-fn enc-fn})
            (table.insert fn-stack
              {:name (or fn-name "<anonymous>")
               :start-depth depth
               :start-line loc.line
               :start-column loc.column
               :anonymous? anonymous?
               :frame-max-depth depth})
            (when anonymous?
              (let [anon-d (- depth 1)]
                (when (> anon-d max-anon-depth)
                  (set max-anon-depth anon-d))))))

        ;; --- global_form ---
        (when (= node-type :global_form)
          (let [loc (node-line-col node)
                form (node-text source node)]
            (for [i 0 (- (node:child-count) 1)]
              (let [c (node:child i)]
                (when (= (c:type) "binding_pair")
                  (for [j 0 (- (c:child-count) 1)]
                    (let [bp-c (c:child j)]
                      (when (= (bp-c:type) "symbol_binding")
                        (let [name-text (node-text source bp-c)]
                          (table.insert facts.definitions
                            {:kind :global
                             :name name-text
                             :top-level? (= depth 1)
                             :line loc.line
                             :column loc.column
                             :length (node:end-byte)
                             :form form}))))))))))

        ;; --- set_form (mutation) ---
        (when (= node-type :set_form)
          (let [loc (node-line-col node)
                form (node-text source node)
                enclosing-fn (if (> (length fn-stack) 0)
                                 (. (. fn-stack (length fn-stack)) :name)
                                 nil)]
            (var path nil)
            (for [i 0 (- (node:child-count) 1)]
              (when (not path)
                (let [c (node:child i)]
                  (if (= (c:type) "binding_pair")
                      (for [j 0 (- (c:child-count) 1)]
                        (let [bp-c (c:child j)]
                          (when (and (not path) (= (bp-c:type) "multi_symbol"))
                            (let [c-text (node-text source bp-c)]
                              (set path (split-dotted-symbol c-text))))))
                      (= (c:type) "multi_symbol")
                      (let [c-text (node-text source c)]
                        (set path (split-dotted-symbol c-text)))))))
            (when path
              (table.insert facts.mutations
                {:op :set
                 :path path
                 :line loc.line
                 :column loc.column
                 :form form
                 :enclosing-fn enclosing-fn}))))

        ;; --- list (calls, require, tset) ---
        (when (= node-type :list)
          (let [ndc (non-delimiter-children node)
                loc (node-line-col node)
                form (node-text source node)
                enclosing-fn (if (> (length fn-stack) 0)
                                 (. (. fn-stack (length fn-stack)) :name)
                                 nil)]
            (when (>= (length ndc) 1)
              (let [head (. ndc 1)
                    head-type (head:type)
                    head-text (node-text source head)]
                (if (= head-text "require")
                    (when (>= (length ndc) 2)
                      (let [mod-node (. ndc 2)
                            mod-name (extract-module-name-from-string-node source mod-node)]
                        (table.insert facts.requires
                          {:module mod-name
                           :line loc.line
                           :column loc.column
                           :form form})))
                    (= head-text "tset")
                    (let [tset-path (if (>= (length ndc) 3)
                                        (let [table-node (. ndc 2)
                                              table-name (node-text source table-node)
                                              key-node (. ndc 3)
                                              key-text (extract-module-name-from-string-node source key-node)]
                                          (if (table-name:match "%.")
                                              (do
                                                (local p (split-dotted-symbol table-name))
                                                (table.insert p key-text)
                                                p)
                                              [table-name key-text]))
                                        [])]
                      (table.insert facts.mutations
                        {:op :tset
                         :path tset-path
                         :line loc.line
                         :column loc.column
                         :form form
                         :enclosing-fn enclosing-fn}))
                    ;; regular call
                    (let [callee head-text
                          receiver (if (= head-type "multi_symbol")
                                       (let [parts (split-dotted-symbol head-text)]
                                         (. parts 1))
                                       (= head-type "multi_symbol_method")
                                       (let [parts (split-colon-symbol head-text)]
                                         (. parts 1))
                                       nil)
                          method (if (= head-type "multi_symbol_method")
                                     (let [parts (split-colon-symbol head-text)]
                                       (if (>= (length parts) 2)
                                           (. parts (length parts))
                                           nil))
                                     (and (= head-type "multi_symbol")
                                          (>= (length (split-dotted-symbol head-text)) 2))
                                     (let [parts (split-dotted-symbol head-text)]
                                       (. parts (length parts)))
                                     nil)]
                      (table.insert facts.calls
                        {:callee callee
                         :receiver receiver
                         :method method
                         :line loc.line
                         :column loc.column
                         :form form
                         :enclosing-fn enclosing-fn})))))))

        ;; --- multi_symbol (access path) ---
        (when (= node-type :multi_symbol)
          (let [c-text (node-text source node)
                loc (node-line-col node)
                path (split-dotted-symbol c-text)]
            (when (>= (length path) 2)
              (table.insert facts.accesses
                {:path path
                 :text c-text
                 :line loc.line
                 :column loc.column
                 :form c-text}))))

        ;; --- table/table_metadata literal (exports and size) ---
        (when (is-table-node? node-type)
          (let [table-size (count-table-elements node)
                loc (node-line-col node)]
            (when (> table-size facts.metrics.max-table-literal-size)
              (set facts.metrics.max-table-literal-size table-size))
            ;; Export keys from top-level table literals only.
            ;; These are module-return tables (the dominant Fennel export pattern).
            ;; Nested tables (e.g., (local config {:key val})) are data, not exports.
            (when (= depth 1)
              (let [pair-type (table-pair-type node-type)]
                (when pair-type
                  (for [i 0 (- (node:child-count) 1)]
                    (let [c (node:child i)]
                      (when (= (c:type) pair-type)
                        (for [j 0 (- (c:child-count) 1)]
                          (let [tp-c (c:child j)]
                            (when (= (tp-c:type) "string")
                              (let [key-text (extract-module-name-from-string-node source tp-c)
                                    key-loc (node-line-col c)]
                                (table.insert facts.exports
                                  {:key key-text
                                   :line key-loc.line
                                   :column key-loc.column
                                   :form (node-text source c)})))))))))))))

        ;; Recurse into children
        (for [i 0 (- (node:child-count) 1)]
          (visit (node:child i)))

        ;; Leave form scope
        (when is-form
          (when (= node-type :fn_form)
            (when (> (length fn-stack) 0)
              (let [fn-info (table.remove fn-stack)
                    ep (node:end-point)
                    end-line (+ ep.row 1)
                    fn-length (- end-line fn-info.start-line)]
                (table.insert facts.metrics.functions
                  {:name fn-info.name
                   :line fn-info.start-line
                   :column fn-info.start-column
                   :length (math.max 1 fn-length)
                   :max-nesting-depth (- fn-info.frame-max-depth fn-info.start-depth)}))))
          (set depth (- depth 1)))))

    ;; ERROR recovery: when tree-sitter produces an ERROR root (grammar
    ;; limitation), scan flat children for op+fn+name at column 1 and push
    ;; synthetic entries onto fn-stack so nested fn_forms get correct
    ;; enclosing-fn attribution.
    (when (= (root:type) "ERROR")
      (var i 0)
      (while (< i (root:child-count))
        (let [c1 (root:child i)]
          (when (and (= (c1:type) "(")
                     (< (+ i 2) (root:child-count))
                     (= (node-text source (root:child (+ i 1))) "fn")
                     (= (. (root:child (+ i 1)) :type) "symbol")
                     (= (. (root:child (+ i 2)) :type) "symbol"))
            (let [fn-name (node-text source (root:child (+ i 2)))
                  loc (node-line-col c1)]
              (table.insert fn-stack
                {:name fn-name
                 :start-depth 0
                 :start-line loc.line
                 :start-column loc.column
                 :anonymous? false
                 :frame-max-depth 0}))))
        (set i (+ i 1))))

    (visit root)

    ;; Finalize metrics
    (set facts.metrics.max-nesting-depth (math.max 0 (- max-depth 1)))
    (set facts.metrics.max-anonymous-callback-depth max-anon-depth)

    facts))

(fn M.extract [file-records]
  "Extract static facts from a list of file records.
  Returns a fact-db:
  {:files [file-facts ...]
   :by-file {path file-facts}}"
  (let [by-file {}
        files []]
    (each [_ record (ipairs file-records)]
      (let [file-facts (extract-file-facts record)]
        (table.insert files file-facts)
        (tset by-file record.path file-facts)))
    {:files files
     :by-file by-file}))

M
