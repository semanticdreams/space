;; Lifecycle constraint rules for experimental Fennel constraints.
;; Two rules: event-registration-cleanup and required-runtime-fails-loudly.

(local Diagnostics (require :constraints.diagnostics))
(local M {})

(fn str-ends-with? [s suffix]
  (and s (>= (length s) (length suffix))
       (= (s:sub (- (length s) (- (length suffix) 1))) suffix)))

(fn escape-pattern [s]
  "Escape all Lua pattern magic characters in s for literal matching."
  (s:gsub "([%^%$%(%)%%%.%[%]%*%+%-%?])" "%%%1"))

(fn register? [c] (and c (or (= c :register) (= c "app.engine.events.updated:connect") (str-ends-with? c ":connect"))))
(fn cleanup-call? [c]
  (and c
       (or (= c :disconnect) (= c :unregister) (= c :clear) (= c :drop)
           (str-ends-with? c ":disconnect") (str-ends-with? c ":drop")
           (str-ends-with? c ":clear") (str-ends-with? c ":unregister")
           (c:match "^disconnect%-") (c:match "^unsubscribe%-"))))
(fn cleanup-fn-name? [n]
  (or (= n :cleanup) (= n :teardown) (= n :shutdown) (= n :unload) (= n :drop)
      (and n (or (n:match "^disconnect%-") (n:match "^unsubscribe%-")))))

(fn has-loop-cleanup? [ff]
  "Check if any function definition contains both a loop construct and a
  cleanup call — evidence of handler-record loop cleanup."
  (var found false)
  (each [_ def (ipairs (or ff.definitions []))]
    (when (and (not found) (= def.kind :fn) def.form)
      (let [form def.form]
         (when (and (or (form:find "each " 1 true) (form:find "for " 1 true)
                        (form:find "icollect " 1 true))
                    (or (form:find ":disconnect" 1 true) (form:find ":drop" 1 true)
                        (form:find ":clear" 1 true) (form:find ":unregister" 1 true)
                        (form:find "disconnect%-") (form:find "unsubscribe%-")))
          (set found true)))))
  found)

(fn event-registration-cleanup-rule-run [ctx]
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (var reg-count 0)
    (var reg-forms [])
    (each [_ call (ipairs (or ff.calls []))]
      (when (register? call.callee)
        (set reg-count (+ reg-count 1))
        (table.insert reg-forms {:callee call.callee :line (or call.line 0) :form (or call.form "")})))
    (var cl-count 0)
    (var cl-forms [])
    (each [_ call (ipairs (or ff.calls []))]
      (when (cleanup-call? call.callee)
        (set cl-count (+ cl-count 1))
        (table.insert cl-forms {:callee call.callee :line (or call.line 0) :form (or call.form "")})))
    (var has-cleanup-fn false)
    (var cleanup-fn-names [])
    (each [_ def (ipairs (or ff.definitions []))]
      (when (and (= def.kind :fn) (cleanup-fn-name? def.name))
        (set has-cleanup-fn true)
        (table.insert cleanup-fn-names def.name)))
    (var has-loop-cl (has-loop-cleanup? ff))
    (when (and (> reg-count 0) (= cl-count 0) (not has-cleanup-fn))
      (table.insert diagnostics
        (Diagnostics.violation
          {:constraint-id "lifecycle.event-registration-cleanup" :family "lifecycle"
           :message (.. "event registration without cleanup in " (or ff.module ff.path))
           :file ff.path :line 0 :column 0
           :evidence {:registration-count reg-count
                      :registration-forms reg-forms
                      :cleanup-forms cl-forms
                      :cleanup-functions cleanup-fn-names}
           :hint "add disconnect, unregister, clear, or drop calls or a cleanup function"})))
    (when (and (> reg-count cl-count) (> cl-count 0) (not has-cleanup-fn) (not has-loop-cl))
      (table.insert diagnostics
        (Diagnostics.violation
          {:constraint-id "lifecycle.event-registration-cleanup" :family "lifecycle"
           :message (.. "insufficient cleanup in " (or ff.module ff.path) ": " reg-count " registrations but only " cl-count " cleanups")
           :file ff.path :line 0 :column 0
           :evidence {:registration-count reg-count
                      :registration-forms reg-forms
                      :cleanup-forms cl-forms
                      :cleanup-functions cleanup-fn-names
                      :has-cleanup-function false}
           :hint "ensure each registration has a corresponding cleanup call or function"}))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn required-runtime-fails-loudly-rule-run [ctx]
  (var diagnostics [])
  (local sensitive ["app.renderers" "app.lights" "app.engine" "app.activity-registry" "app.physics-containment-config" "package.loaded"])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (var has-access false)
    (each [_ a (ipairs (or ff.accesses []))]
      (let [pt (table.concat (or a.path []) ".")]
        (each [_ sg (ipairs sensitive)]
          (when (= pt sg) (set has-access true)))))
    (when has-access
      (each [_ def (ipairs (or ff.definitions []))]
        (when (and (= def.kind :fn) def.form)
          (var matched nil)
          ;; Check for or-synthesis and if-synthesis patterns.
          ;; or-synthesis: (or SENSITIVE_GLOBAL <default>) — not followed by a dot (subfield).
          ;; if-synthesis: (if SENSITIVE_GLOBAL SENSITIVE_GLOBAL <else>) — classic fallback.
          (each [_ sg (ipairs sensitive)]
            (when (not matched)
              (let [sg-escaped (escape-pattern sg)
                    or-pat (.. "%(or%s+" sg-escaped "%s+")
                    if-pat (.. "%(if%s+" sg-escaped "%s+" sg-escaped)]
                (when (or (string.find def.form or-pat)
                          (string.find def.form if-pat))
                  (set matched sg)))))
          (when matched
            ;; Check for assert/error in the same function — if present, skip
            (var has-assert false)
            (when (or (string.find def.form "assert" 1 true) (string.find def.form "error" 1 true))
              (set has-assert true))
             (when (not has-assert)
               (table.insert diagnostics
                 (Diagnostics.violation
                   {:constraint-id "lifecycle.required-runtime-fails-loudly" :family "lifecycle"
                    :message (.. "function " (or def.name "<anonymous>") " synthesizes " matched " via or/if without assert/error")
                    :file ff.path :line (or def.line 0) :column 0
                    :evidence {:function-name (or def.name "<anonymous>") :sensitive-global matched}
                    :hint "Assert required runtime state instead of silently synthesizing or falling back to a substitute canonical state."}))))))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn M.rules []
  [{:id "lifecycle.event-registration-cleanup" :family "lifecycle" :targets [:repo] :kind :static :run event-registration-cleanup-rule-run :fn event-registration-cleanup-rule-run}
   {:id "lifecycle.required-runtime-fails-loudly" :family "lifecycle" :targets [:repo] :kind :static :run required-runtime-fails-loudly-rule-run :fn required-runtime-fails-loudly-rule-run}])

M
