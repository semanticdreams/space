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

(fn escape-pattern [s]
  "Escape Lua pattern magic characters in a string."
  (s:gsub "[%]%[%%%.%*%+%-%?%(%)%^%$]" "%%%1"))

(fn has-concrete-restore-evidence? [fn-form path]
  "Check for concrete restore evidence: the function form must show both
   a snapshot of the path into a local variable and a later write that
   sets the path back to that same variable.
   Snapshot: (let [VAR path_text ...] or (local VAR path_text ...)
   Restore:  (set path_text VAR) or (tset table-prefix key VAR)"
  (let [path-text (table.concat path ".")
        escaped-path (path-text:gsub "%." "%%.")]
    (var found false)
    ;; Find snapshot variables from (let [VAR path_text ...]) patterns.
    (each [snap-var (fn-form:gmatch (.. "%(let%s*%[%s*([^%s]+)%s+" escaped-path))]
      (let [escaped-var (escape-pattern snap-var)]
        ;; (set path_text snap-var)
        (when (string.find fn-form (.. "%(set%s+" escaped-path "%s+" escaped-var "%s*%)"))
          (set found true))
        ;; (tset table-prefix key snap-var)
        (when (not found)
          (let [plen (length path)]
            (when (>= plen 2)
              (local table-parts [])
              (for [i 1 (- plen 1)]
                (table.insert table-parts (. path i)))
              (let [tset-table (table.concat table-parts ".")
                    key (. path plen)
                    escaped-tset (tset-table:gsub "%." "%%.")
                    escaped-key (escape-pattern key)]
                (when (or (string.find fn-form (.. "%(tset%s+" escaped-tset "%s+:%s*" escaped-key "%s+" escaped-var))
                          (string.find fn-form (.. "%(tset%s+" escaped-tset "%s+\"%s*" escaped-key "%s*\"%s+" escaped-var)))
                  (set found true))))))))
    ;; Also check (local VAR path_text) patterns.
    (when (not found)
      (each [snap-var (fn-form:gmatch (.. "%(local%s+([^%s]+)%s+" escaped-path))]
        (let [escaped-var (escape-pattern snap-var)]
          (when (string.find fn-form (.. "%(set%s+" escaped-path "%s+" escaped-var "%s*%)"))
            (set found true)))))
    found))

(fn global-mutation-restoration-rule-run [ctx]
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (when (string.find ff.path "/tests/" 1 true)
      ;; Track which (fn, path) pairs we've already diagnosed to avoid
      ;; duplicate diagnostics for the same function+path.
      (var diagnosed {})
      ;; Check each mutation for restoration evidence
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
                ;; Pattern 1: with-restored-app-fields (explicit, unambiguous)
                (when (string.find fn-form "with-restored-app-fields" 1 true)
                  (set has-restoration true))
                ;; Pattern 2: direct snapshot table restore
                ;; Requires concrete restore evidence: (let [VAR path] ...)
                ;; AND a later (set path VAR) or (tset prefix key VAR)
                ;; that restores the sensitive global back to the snapshot value.
                (when (not has-restoration)
                  (when (has-concrete-restore-evidence? fn-form mutation.path)
                    (set has-restoration true)
                    ;; Mark as Pattern 2 for pcall branch to skip.
                    nil))
                ;; Pattern 3: pcall cleanup restore
                ;; Requires pcall in form AND concrete restore evidence
                ;; (snapshot + restore write back to snapshot binding).
                (when (not has-restoration)
                  (when (and (string.find fn-form "pcall" 1 true)
                             (has-concrete-restore-evidence? fn-form mutation.path))
                    (set has-restoration true))))
              (when (not has-restoration)
                (tset diagnosed (.. fn-name "::" path-text) true)
                (table.insert diagnostics
                  (Diagnostics.violation
                    {:constraint-id "lifecycle.global-mutation-restoration" :family "test-isolation"
                     :message (.. "test file mutates sensitive global " path-text " without snapshot and restore")
                     :file ff.path :line (or mutation.line 0) :column 0
                     :evidence {:global-path path-text :enclosing-fn (or mutation.enclosing-fn "<top-level>")}
                     :hint (.. "snapshot and restore " path-text " using with-restored-app-fields or pcall cleanup")})))))))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn M.rules []
  [{:id "lifecycle.global-mutation-restoration" :family "test-isolation" :targets [:repo] :kind :static :run global-mutation-restoration-rule-run :fn global-mutation-restoration-rule-run}])

M
