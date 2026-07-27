;; Structure and Formatting constraint rules for experimental Fennel constraints.

(local Diagnostics (require :constraints.diagnostics))
(local M {})

(local thresholds
  {:max-nesting-depth 7
   :max-function-length 120
   :max-module-length 1200
   :max-table-literal-size 80
   :max-anonymous-callback-depth 3})

(fn make-fingerprint [constraint-id file-path line name]
  (.. constraint-id ":" file-path ":" line ":" (or name "")))

(fn str-contains? [s sub]
  (and s sub (string.find s sub 1 true)))

(fn max-nesting-depth-rule-run [ctx]
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (let [metrics (or ff.metrics {})
          measure (or metrics.max-nesting-depth 0)
          limit thresholds.max-nesting-depth]
      (when (> measure limit)
        (table.insert diagnostics
          (Diagnostics.violation
            {:constraint-id "structure.max-nesting-depth"
             :family "structure-formatting"
             :message (.. "max nesting depth " measure " exceeds limit of " limit " in " (or ff.module ff.path))
             :file ff.path :line 0 :column 0
             :evidence {:measure measure :limit limit
                        :fingerprint (make-fingerprint "structure.max-nesting-depth" ff.path 0 (or ff.module ff.path))}
             :hint (.. "Refactor deeply nested code into smaller functions to reduce nesting depth below " limit)})))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn max-function-length-rule-run [ctx]
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (let [metrics (or ff.metrics {})
          funcs (or metrics.functions [])
          limit thresholds.max-function-length]
      (each [_ fn-info (ipairs funcs)]
        (let [measure (or fn-info.length 0)
              fn-name (or fn-info.name (tostring fn-info.line))]
          (when (> measure limit)
            (table.insert diagnostics
              (Diagnostics.violation
                {:constraint-id "structure.max-function-length"
                 :family "structure-formatting"
                 :message (.. "function " fn-name " length " measure " exceeds limit of " limit " in " (or ff.module ff.path))
                 :file ff.path :line (or fn-info.line 0) :column (or fn-info.column 0)
                 :evidence {:measure measure :limit limit :function-name fn-name
                            :fingerprint (make-fingerprint "structure.max-function-length" ff.path (or fn-info.line 0) fn-name)}
                 :hint (.. "Break function " fn-name " into smaller functions to stay below " limit " lines")})))))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn max-module-length-rule-run [ctx]
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (let [metrics (or ff.metrics {})
          measure (or metrics.module-lines 0)
          limit thresholds.max-module-length]
      (when (> measure limit)
        (table.insert diagnostics
          (Diagnostics.violation
            {:constraint-id "structure.max-module-length"
             :family "structure-formatting"
             :message (.. "module " (or ff.module ff.path) " length " measure " exceeds limit of " limit)
             :file ff.path :line 0 :column 0
             :evidence {:measure measure :limit limit
                        :fingerprint (make-fingerprint "structure.max-module-length" ff.path 0 (or ff.module ff.path))}
             :hint (.. "Split " (or ff.module ff.path) " into smaller modules to stay below " limit " lines")})))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn large-inline-structure-rule-run [ctx]
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (let [metrics (or ff.metrics {})
          table-size (or metrics.max-table-literal-size 0)
          anon-depth (or metrics.max-anonymous-callback-depth 0)
          table-limit thresholds.max-table-literal-size
          anon-limit thresholds.max-anonymous-callback-depth]
      (when (> table-size table-limit)
        (table.insert diagnostics
          (Diagnostics.violation
            {:constraint-id "structure.large-inline-structure"
             :family "structure-formatting"
             :message (.. "max table literal size " table-size " exceeds limit of " table-limit " in " (or ff.module ff.path))
             :file ff.path :line 0 :column 0
             :evidence {:measure table-size :limit table-limit :type :table-literal-size
                        :fingerprint (make-fingerprint "structure.large-inline-structure" ff.path 0 "table-literal-size")}
             :hint "Extract large inline table literals into named constants or load from files"})))
      (when (> anon-depth anon-limit)
        (table.insert diagnostics
          (Diagnostics.violation
            {:constraint-id "structure.large-inline-structure"
             :family "structure-formatting"
             :message (.. "max anonymous callback depth " anon-depth " exceeds limit of " anon-limit " in " (or ff.module ff.path))
             :file ff.path :line 0 :column 0
             :evidence {:measure anon-depth :limit anon-limit :type :anonymous-callback-depth
                        :fingerprint (make-fingerprint "structure.large-inline-structure" ff.path 0 "anonymous-callback-depth")}
             :hint "Name anonymous callbacks or refactor to reduce nesting depth"})))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn definition-form-contains-let? [form]
  (and form (str-contains? form "(let ")))

(fn export-key-contains-forbidden-word? [key]
  (and key
       (or (str-contains? key "legacy")
           (str-contains? key "compat")
           (str-contains? key "alias"))))

(fn fn-has-silent-fallback? [def calls]
  "Check if a function contains (or ...) without assert or error."
  (when (and def.form def.name (= def.kind :fn))
    (when (string.find def.form "(or " 1 true)
      (var has-assertion false)
      (each [_ call (ipairs (or calls []))]
        (when (and (not has-assertion)
                   (= (or call.enclosing-fn "") def.name)
                   (or (= call.callee "assert")
                       (= call.callee "error")))
          (set has-assertion true)))
      (not has-assertion))))

(fn style-doctrine-rule-run [ctx]
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (let [module-name (or ff.module ff.path)
          file-path ff.path
          calls (or ff.calls [])]
      (each [_ def (ipairs (or ff.definitions []))]
        (when (definition-form-contains-let? def.form)
          (table.insert diagnostics
            (Diagnostics.violation
              {:constraint-id "structure.style-doctrine"
               :family "structure-formatting"
               :message (.. "use of (let) form found in " module-name " at line " (or def.line 0))
               :file file-path :line (or def.line 0) :column (or def.column 0)
               :evidence {:construct "let" :line (or def.line 0)
                          :fingerprint (make-fingerprint "structure.style-doctrine" file-path (or def.line 0) "let")}
               :hint "Use (local) instead of (let) in Fennel"}))))
      (each [_ export (ipairs (or ff.exports []))]
        (when (export-key-contains-forbidden-word? export.key)
          (table.insert diagnostics
            (Diagnostics.violation
              {:constraint-id "structure.style-doctrine"
               :family "structure-formatting"
               :message (.. "alias export key '" export.key "' found in " module-name " at line " (or export.line 0))
               :file file-path :line (or export.line 0) :column (or export.column 0)
               :evidence {:construct "alias" :key export.key
                          :fingerprint (make-fingerprint "structure.style-doctrine" file-path (or export.line 0) (.. "alias:" export.key))}
               :hint "Remove legacy/compat/alias export keys and use canonical names"}))))
      (each [_ def (ipairs (or ff.definitions []))]
        (when (fn-has-silent-fallback? def calls)
          (table.insert diagnostics
            (Diagnostics.violation
              {:constraint-id "structure.style-doctrine"
               :family "structure-formatting"
               :message (.. "silent fallback (or) in function " (or def.name "<anonymous>") " without assert or error in " module-name)
               :file file-path :line (or def.line 0) :column (or def.column 0)
               :evidence {:construct "silent-fallback" :function-name (or def.name "<anonymous>")
                          :fingerprint (make-fingerprint "structure.style-doctrine" file-path (or def.line 0) (or def.name "silent-fallback"))}
               :hint "Use assert or error to fail loudly instead of silently falling back"}))))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn M.rules []
  [{:id "structure.max-nesting-depth" :family "structure-formatting" :targets [:repo] :kind :static
    :run max-nesting-depth-rule-run :fn max-nesting-depth-rule-run}
   {:id "structure.max-function-length" :family "structure-formatting" :targets [:repo] :kind :static
    :run max-function-length-rule-run :fn max-function-length-rule-run}
   {:id "structure.max-module-length" :family "structure-formatting" :targets [:repo] :kind :static
    :run max-module-length-rule-run :fn max-module-length-rule-run}
   {:id "structure.large-inline-structure" :family "structure-formatting" :targets [:repo] :kind :static
    :run large-inline-structure-rule-run :fn large-inline-structure-rule-run}
   {:id "structure.style-doctrine" :family "structure-formatting" :targets [:repo] :kind :static
    :run style-doctrine-rule-run :fn style-doctrine-rule-run}])

M
