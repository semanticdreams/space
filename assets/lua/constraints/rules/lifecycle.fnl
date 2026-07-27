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

(fn count-newlines [s]
  "Count the number of newline characters in s."
  (var n 0)
  (each [_ _ (s:gmatch "\n")]
    (set n (+ n 1)))
  n)

(fn find-matching-paren [s open-pos]
  "Find the position of the ')' that matches the '(' at open-pos.
  Skips over strings (double and single quotes) to avoid false matches."
  (var depth 1)
  (var pos (+ open-pos 1))
  (var in-double false)
  (var in-single false)
  (while (and (<= pos (length s)) (> depth 0))
    (let [c (s:sub pos pos)]
      (if in-double
          (when (= c "\"") (set in-double false))
          in-single
          (when (= c "'") (set in-single false))
          (= c "\"")
          (set in-double true)
          (= c "'")
          (set in-single true)
          (= c "(")
          (set depth (+ depth 1))
          (= c ")")
          (set depth (- depth 1))))
    (set pos (+ pos 1)))
  (if (= depth 0) (- pos 1) nil))

(fn find-all-loop-body-ranges [form base-line]
  "Find line ranges for each loop body within a function form.
  Returns a list of {start, end} line ranges.
  A loop body is the entire (each ...) or (for ...) or (icollect ...) form."
  (var ranges [])
  (var pos 1)
  (while (<= pos (length form))
    (var found false)
    (each [_ kw (ipairs ["each " "for " "icollect "])]
      (when (not found)
        (let [p (form:find kw pos true)]
          (when (and p (> p 1) (= (form:sub (- p 1) (- p 1)) "("))
            (set found true)
            (let [open-pos (- p 1)
                  close-pos (find-matching-paren form open-pos)]
              (if close-pos
                  (let [start-line (+ base-line (count-newlines (form:sub 1 open-pos)))
                        end-line (+ base-line (count-newlines (form:sub 1 close-pos)))]
                    (table.insert ranges {:start start-line :end end-line})
                    (set pos (+ close-pos 1)))
                  (set pos (+ p 1))))))))
    (when (not found)
      (set pos (+ (length form) 1))))
  ranges)

(fn has-loop-cleanup? [ff]
  "Check if any function definition contains a loop construct AND a real
  cleanup call falls within the loop body line range — structured by call
  location (line number) and loop containment, not raw text or whole-function
  approximation.  This prevents false suppression when a cleanup call lies
  in the same function but outside the loop, or when a loop merely prints
  or comments about a cleanup call."
  ;; Build line ranges for loop bodies (not whole functions).
  (var loop-body-ranges [])
  (each [_ def (ipairs (or ff.definitions []))]
    (when (and (= def.kind :fn) def.form
               (or (def.form:find "each " 1 true)
                   (def.form:find "for " 1 true)
                   (def.form:find "icollect " 1 true)))
      (let [body-ranges (find-all-loop-body-ranges def.form def.line)]
        (each [_ r (ipairs body-ranges)]
          (table.insert loop-body-ranges r)))))
  ;; Check by line range: a real cleanup call fact whose line falls
  ;; inside an actual loop body.
  (if (= (length loop-body-ranges) 0)
      false
      (do
        (var found false)
        (each [_ call (ipairs (or ff.calls []))]
          (when (and (not found) (cleanup-call? call.callee) call.line)
            (each [_ r (ipairs loop-body-ranges)]
              (when (and (not found)
                         (>= call.line r.start)
                         (<= call.line r.end))
                (set found true)))))
        found)))

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
