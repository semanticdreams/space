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

(fn count-set-writes [fn-form path-text table-part key-part]
  "Count set/tset target occurrences for this path in the form text."
  (var count 0)
  (var pos 1)
  (var done false)
  (local set-pat (.. "(set " path-text))
  (while (not done)
    (let [(start) (string.find fn-form set-pat pos true)]
      (if start
          (do (set count (+ count 1))
              (set pos (+ start 1)))
          (set done true))))
  ;; Also count tset writes
  (when (and table-part key-part)
    (var pos2 1)
    (var done2 false)
    (local tset-pat (.. "(tset " table-part " :" key-part))
    (while (not done2)
      (let [(start2) (string.find fn-form tset-pat pos2 true)]
        (if start2
            (do (set count (+ count 1))
                (set pos2 (+ start2 1)))
            (set done2 true)))))
  count)

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
      ;; Pre-count mutations per function per path for restore detection
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
      ;; Now check each mutation
      (each [_ mutation (ipairs (or ff.mutations []))]
        (when (mutation-path-is-sensitive? mutation.path)
          (var fn-form nil)
          (when mutation.enclosing-fn
            (each [_ def (ipairs (or ff.definitions []))]
              (when (and (= def.kind :fn) (= def.name mutation.enclosing-fn))
                (set fn-form def.form))))
          (var has-restoration false)
          (when fn-form
            (let [path-text (table.concat (or mutation.path []) ".")
                  table-part (. (or mutation.path []) 1)
                  key-part (. (or mutation.path []) 2)
                  fn-name (or mutation.enclosing-fn "<top-level>")
                  fn-counts (. fn-mutation-counts fn-name)
                  mutation-count (or (and fn-counts (. fn-counts path-text)) 0)]
              ;; Pattern 1: with-restored-app-fields
              (when (string.find fn-form "with-restored-app-fields" 1 true)
                (set has-restoration true))
              ;; Pattern 2: direct snapshot restore (snapshot + extra writes)
              (when (not has-restoration)
                (var has-snapshot (form-has-snapshot-evidence? fn-form path-text))
                (var write-count (count-set-writes fn-form path-text table-part key-part))
                ;; If more writes than mutations, at least one is a restore
                (when (and has-snapshot (> write-count mutation-count))
                  (set has-restoration true)))
              ;; Pattern 3: pcall cleanup restore (pcall + extra writes)
              (when (not has-restoration)
                (var write-count (count-set-writes fn-form path-text table-part key-part))
                (when (and (string.find fn-form "pcall" 1 true)
                           (> write-count mutation-count))
                  (set has-restoration true)))))
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
