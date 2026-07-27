;; Test-Isolation constraint rules for experimental Fennel constraints.
;; One rule: global-mutation-restoration

(local Diagnostics (require :constraints.diagnostics))
(local M {})

(local sensitive ["app.renderers" "app.lights" "app.engine" "app.activity-registry" "app.physics-containment-config" "package.loaded"])

(fn mutation-path-is-sensitive? [mutation-path]
  (let [plen (length (or mutation-path []))]
    (if (< plen 2) false
        (do
          (var found false)
          (each [_ sg (ipairs sensitive)]
            (when (not found)
              (local sg-parts [])
              (each [seg (sg:gmatch "[^%.]+")] (table.insert sg-parts seg))
              (let [slen (length sg-parts)]
                (when (>= plen slen)
                  (var matches true)
                  (for [i 1 slen]
                    (when (not (= (. mutation-path i) (. sg-parts i)))
                      (set matches false)))
                  (when matches (set found true))))))
          found))))

(fn global-mutation-restoration-rule-run [ctx]
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (when (string.find ff.path "/tests/" 1 true)
      (each [_ mutation (ipairs (or ff.mutations []))]
        (when (mutation-path-is-sensitive? mutation.path)
          (var fn-form nil)
          (when mutation.enclosing-fn
            (each [_ def (ipairs (or ff.definitions []))]
              (when (and (= def.kind :fn) (= def.name mutation.enclosing-fn))
                (set fn-form def.form))))
          (var has-restoration false)
          (when fn-form
            ;; Pattern 1: with-restored-app-fields macro/function
            (when (string.find fn-form "with-restored-app-fields" 1 true) (set has-restoration true))
            ;; Pattern 2 & 3: direct snapshot table restore and pcall cleanup
            ;; restore — both require at least 3 path occurrences
            ;; (snapshot + mutation + restore) to distinguish actual restore
            ;; from two mutations without cleanup
            (when (not has-restoration)
              (let [pt (table.concat (or mutation.path []) ".")
                    (start) (string.find fn-form pt 1 true)]
                (when start
                  (let [(start2) (string.find fn-form pt (+ start 1) true)]
                    (when start2
                      (let [(start3) (string.find fn-form pt (+ start2 1) true)]
                        (when start3 (set has-restoration true)))))))))
          (when (not has-restoration)
            (table.insert diagnostics
              (Diagnostics.violation
                {:constraint-id "lifecycle.global-mutation-restoration" :family "test-isolation"
                 :message (.. "test file mutates sensitive global " (table.concat (or mutation.path []) ".") " without snapshot and restore")
                 :file ff.path :line (or mutation.line 0) :column 0
                 :evidence {:global-path (table.concat (or mutation.path []) ".") :enclosing-fn (or mutation.enclosing-fn "<top-level>")}
                 :hint (.. "snapshot and restore " (table.concat (or mutation.path []) ".") " using with-restored-app-fields or pcall cleanup")})))))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn M.rules []
  [{:id "lifecycle.global-mutation-restoration" :family "test-isolation" :targets [:repo] :kind :static :run global-mutation-restoration-rule-run :fn global-mutation-restoration-rule-run}])

M
