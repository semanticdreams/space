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

(fn form-has-snapshot-evidence? [fn-form path-text]
  "Check for snapshot patterns: the path appearing in a local binding or
  let binding position where it is read, not written."
  (or (string.find fn-form (.. "(local " path-text) 1 true)
      (string.find fn-form (.. " " path-text ")") 1 true)
      (string.find fn-form (.. " " path-text "]") 1 true)))

(fn global-mutation-restoration-rule-run [ctx]
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (when (string.find ff.path "/tests/" 1 true)
      ;; Pre-count mutations per function per path for restore detection.
      ;; The fact extractor records ALL set/tset forms as mutations,
      ;; including restoration writes. So a valid snapshot+restore
      ;; function has >= 2 mutation entries for the same path.
      (var fn-mutation-counts {})
      (each [_ mutation (ipairs (or ff.mutations []))]
        (when (mutation-path-is-sensitive? mutation.path)
          (let [pt (table.concat (or mutation.path []) ".")
                fn-name (or mutation.enclosing-fn "<top-level>")]
            (var entry (. fn-mutation-counts fn-name))
            (when (not entry)
              (set entry {})
              (tset fn-mutation-counts fn-name entry))
            (tset entry pt (+ (or (. entry pt) 0) 1)))))
      ;; Track which (fn, path) pairs we've already diagnosed to avoid
      ;; duplicate diagnostics for the same function+path.
      (var diagnosed {})
      ;; Now check each mutation for restoration evidence
      (each [_ mutation (ipairs (or ff.mutations []))]
        (when (mutation-path-is-sensitive? mutation.path)
          (let [fn-name (or mutation.enclosing-fn "<top-level>")
                path-text (table.concat (or mutation.path []) ".")]
            (when (not (. diagnosed (.. fn-name "::" path-text)))
              (var fn-form nil)
              (when mutation.enclosing-fn
                (each [_ def (ipairs (or ff.definitions []))]
                  (when (and (= def.kind :fn) (= def.name mutation.enclosing-fn))
                    (set fn-form def.form))))
              (var has-restoration false)
              (when fn-form
                (let [fn-counts (. fn-mutation-counts fn-name)
                      mutation-count (or (and fn-counts (. fn-counts path-text)) 0)]
                  ;; Pattern 1: with-restored-app-fields
                  (when (string.find fn-form "with-restored-app-fields" 1 true)
                    (set has-restoration true))
                  ;; Pattern 2: direct snapshot table restore
                  ;; Requires snapshot evidence (path read into local/let binding)
                  ;; AND >= 2 mutation records (mutation + restore both recorded by extractor)
                  (when (not has-restoration)
                    (when (and (form-has-snapshot-evidence? fn-form path-text)
                               (>= mutation-count 2))
                      (set has-restoration true)))
                  ;; Pattern 3: pcall cleanup restore
                  ;; Requires pcall in form, snapshot evidence, AND >= 2 mutation records
                  ;; (mutation inside pcall + restore outside, both recorded by extractor)
                  (when (not has-restoration)
                    (when (and (string.find fn-form "pcall" 1 true)
                               (form-has-snapshot-evidence? fn-form path-text)
                               (>= mutation-count 2))
                      (set has-restoration true)))))
              (when (not has-restoration)
                (tset diagnosed (.. fn-name "::" path-text) true)
                (table.insert diagnostics
                  (Diagnostics.violation
                    {:constraint-id "lifecycle.global-mutation-restoration" :family "test-isolation"
                     :message (.. "test file mutates sensitive global " (table.concat (or mutation.path []) ".") " without snapshot and restore")
                     :file ff.path :line (or mutation.line 0) :column 0
                     :evidence {:global-path (table.concat (or mutation.path []) ".") :enclosing-fn (or mutation.enclosing-fn "<top-level>")}
                     :hint (.. "snapshot and restore " (table.concat (or mutation.path []) ".") " using with-restored-app-fields or pcall cleanup")})))))))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn M.rules []
  [{:id "lifecycle.global-mutation-restoration" :family "test-isolation" :targets [:repo] :kind :static :run global-mutation-restoration-rule-run :fn global-mutation-restoration-rule-run}])

M
