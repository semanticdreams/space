;; Lifecycle constraint rules for experimental Fennel constraints.
;; Two rules: event-registration-cleanup and required-runtime-fails-loudly.

(local Diagnostics (require :constraints.diagnostics))
(local M {})

(fn str-ends-with? [s suffix]
  (and s (>= (length s) (length suffix))
       (= (s:sub (- (length s) (- (length suffix) 1))) suffix)))

(fn register? [c] (and c (or (= c :register) (= c "app.engine.events.updated:connect") (str-ends-with? c ":connect"))))
(fn cleanup-call? [c] (and c (or (= c :disconnect) (= c :unregister) (= c :clear) (= c :drop) (str-ends-with? c ":disconnect") (str-ends-with? c ":drop") (str-ends-with? c ":clear") (str-ends-with? c ":unregister"))))
(fn cleanup-fn-name? [n] (or (= n :cleanup) (= n :teardown) (= n :shutdown) (= n :unload) (= n :drop)))

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
    (when (and (> reg-count cl-count) (> cl-count 0) (not has-cleanup-fn))
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
          (each [_ sg (ipairs sensitive)]
            (when (and (not matched) (string.find def.form sg 1 true))
              (set matched sg)))
          (when matched
            (var has-syn false)
            (when (or (string.find def.form "(or " 1 true) (string.find def.form "(when " 1 true) (string.find def.form "(if " 1 true))
              (set has-syn true))
            (when has-syn
              (var has-assert false)
              (when (or (string.find def.form "assert" 1 true) (string.find def.form "error" 1 true))
                (set has-assert true))
              (when (not has-assert)
                (table.insert diagnostics
                  (Diagnostics.violation
                    {:constraint-id "lifecycle.required-runtime-fails-loudly" :family "lifecycle"
                     :message (.. "function " (or def.name "<anonymous>") " uses or/when/if with " matched " without assert/error")
                     :file ff.path :line (or def.line 0) :column 0
                     :evidence {:function-name (or def.name "<anonymous>") :sensitive-global matched}
                     :hint "Assert required runtime state instead of silently no-oping or synthesizing canonical state."})))))))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn M.rules []
  [{:id "lifecycle.event-registration-cleanup" :family "lifecycle" :targets [:repo] :kind :static :run event-registration-cleanup-rule-run :fn event-registration-cleanup-rule-run}
   {:id "lifecycle.required-runtime-fails-loudly" :family "lifecycle" :targets [:repo] :kind :static :run required-runtime-fails-loudly-rule-run :fn required-runtime-fails-loudly-rule-run}])

M
