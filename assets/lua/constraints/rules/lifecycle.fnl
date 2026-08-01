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

(fn register? [c]
  (and c (if (= c :register) true
             (= c "app.engine.events.updated:connect") true
             (str-ends-with? c ":connect"))))

(fn cleanup-call? [c]
  (when c
    (if (= c :disconnect) true
        (= c :unregister) true
        (= c :clear) true
        (= c :drop) true
        (str-ends-with? c ":disconnect") true
        (str-ends-with? c ":drop") true
        (str-ends-with? c ":clear") true
        (str-ends-with? c ":unregister") true
        (c:match "^disconnect%-") true
        (c:match "^unsubscribe%-") true
        nil)))

(fn cleanup-fn-name? [n]
  (if (= n :cleanup) true
      (= n :teardown) true
      (= n :shutdown) true
      (= n :unload) true
      (= n :drop) true
      (and n (n:match "^disconnect%-")) true
      (and n (n:match "^unsubscribe%-")) true
      nil))

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
    (local c (s:sub pos pos))
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
        (set depth (- depth 1)))
    (set pos (+ pos 1)))
  (if (= depth 0) (- pos 1) nil))

(fn try-accept-loop-body [ranges form base-line open-pos p]
  "Try to extract a loop body range starting at open-pos (the '(' before the
  keyword match at p). Returns the next position to scan from."
  (local close-pos (find-matching-paren form open-pos))
  (if close-pos
      (do
        (local start-line (+ base-line (count-newlines (form:sub 1 open-pos))))
        (local end-line (+ base-line (count-newlines (form:sub 1 close-pos))))
        (table.insert ranges {:start start-line :end end-line})
        (+ close-pos 1))
      (+ p 1)))

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
        (local p (form:find kw pos true))
        (when (and p (> p 1) (= (form:sub (- p 1) (- p 1)) "("))
          (set found true)
          (local new-pos (try-accept-loop-body ranges form base-line (- p 1) p))
          (set pos new-pos))))
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
  (var definitions ff.definitions)
  (when (not definitions) (set definitions []))
  (each [_ def (ipairs definitions)]
    (when (and (= def.kind :fn) def.form)
      (var has-loop false)
      (when (def.form:find "each " 1 true) (set has-loop true))
      (when (not has-loop) (when (def.form:find "for " 1 true) (set has-loop true)))
      (when (not has-loop) (when (def.form:find "icollect " 1 true) (set has-loop true)))
      (when has-loop
        (local body-ranges (find-all-loop-body-ranges def.form def.line))
        (each [_ r (ipairs body-ranges)]
          (table.insert loop-body-ranges r)))))
  ;; Check by line range: a real cleanup call fact whose line falls
  ;; inside an actual loop body.
  (if (= (length loop-body-ranges) 0)
      false
      (do
        (var found false)
        (var calls ff.calls)
        (when (not calls) (set calls []))
        (each [_ call (ipairs calls)]
          (when (and (not found) (cleanup-call? call.callee) call.line)
            (each [_ r (ipairs loop-body-ranges)]
              (when (and (not found)
                         (>= call.line r.start)
                         (<= call.line r.end))
                (set found true)))))
        found)))

(fn file-accesses-sensitive? [ff sensitive]
  "Check whether any access in ff matches a sensitive global name."
  (var has-access false)
  (var accesses ff.accesses)
  (when (not accesses) (set accesses []))
  (each [_ a (ipairs accesses)]
    (var p [])
    (when a.path (set p a.path))
    (local pt (table.concat p "."))
    (each [_ sg (ipairs sensitive)]
      (when (= pt sg)
        (set has-access true))))
  has-access)

(fn check-function-for-synthesis [def sensitive]
  "Check if a function definition synthesizes a sensitive global via (or GLOBAL ...)
  or (if GLOBAL GLOBAL ...) without assert/error. Returns the matched global name or nil."
  (var matched nil)
  (each [_ sg (ipairs sensitive)]
    (when (not matched)
      (local sg-escaped (escape-pattern sg))
      (local or-pat (.. "%(or%s+" sg-escaped "%s+"))
      (local if-pat (.. "%(if%s+" sg-escaped "%s+" sg-escaped))
      (var found false)
      (when (string.find def.form or-pat) (set found true))
      (when (not found)
        (when (string.find def.form if-pat)
          (set found true)))
      (when found (set matched sg))))
  (when matched
    (var has-assert false)
    (when (string.find def.form "assert" 1 true) (set has-assert true))
    (when (not has-assert)
      (when (string.find def.form "error" 1 true)
        (set has-assert true)))
    (when (not has-assert)
      matched)))

(fn event-registration-cleanup-rule-run [ctx]
  (var diagnostics [])
  (var files (. ctx.facts :files))
  (when (not files) (set files []))
  (each [_ ff (ipairs files)]
    (var reg-count 0)
    (var reg-forms [])
    (var calls ff.calls)
    (when (not calls) (set calls []))
    (each [_ call (ipairs calls)]
      (when (register? call.callee)
        (set reg-count (+ reg-count 1))
        (table.insert reg-forms
         {:callee call.callee
          :line (if call.line call.line 0)
          :form (if call.form call.form "")})))
    (var cl-count 0)
    (var cl-forms [])
    (each [_ call (ipairs calls)]
      (when (cleanup-call? call.callee)
        (set cl-count (+ cl-count 1))
        (table.insert cl-forms
         {:callee call.callee
          :line (if call.line call.line 0)
          :form (if call.form call.form "")})))
    (var has-cleanup-fn false)
    (var cleanup-fn-names [])
    (var definitions ff.definitions)
    (when (not definitions) (set definitions []))
    (each [_ def (ipairs definitions)]
      (when (and (= def.kind :fn) (cleanup-fn-name? def.name))
        (set has-cleanup-fn true)
        (table.insert cleanup-fn-names def.name)))
    (var has-loop-cl (has-loop-cleanup? ff))
    (var module (if ff.module ff.module ff.path))
    (when (and (> reg-count 0) (= cl-count 0) (not has-cleanup-fn))
      (table.insert diagnostics
        (Diagnostics.violation
          {:constraint-id "lifecycle.event-registration-cleanup" :family "lifecycle"
           :message (.. "event registration without cleanup in " module)
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
           :message (.. "insufficient cleanup in " module ": " reg-count " registrations but only " cl-count " cleanups")
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
  (each [_ ff (ipairs (if (. ctx.facts :files) (. ctx.facts :files) []))]
    (when (file-accesses-sensitive? ff sensitive)
      (each [_ def (ipairs (if ff.definitions ff.definitions []))]
        (when (and (= def.kind :fn) def.form)
          (local matched (check-function-for-synthesis def sensitive))
          (when matched
            (local fn-name (if def.name def.name "<anonymous>"))
            (local def-line (if def.line def.line 0))
            (table.insert diagnostics
              (Diagnostics.violation
                {:constraint-id "lifecycle.required-runtime-fails-loudly" :family "lifecycle"
                 :message (.. "function " fn-name " synthesizes " matched " via or/if without assert/error")
                 :file ff.path :line def-line :column 0
                 :evidence {:function-name fn-name :sensitive-global matched}
                 :hint "Assert required runtime state instead of silently synthesizing or falling back to a substitute canonical state."})))))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn M.rules []
  [{:id "lifecycle.event-registration-cleanup" :family "lifecycle" :targets [:repo :unit :app :files] :kind :static :run event-registration-cleanup-rule-run :fn event-registration-cleanup-rule-run}
   {:id "lifecycle.required-runtime-fails-loudly" :family "lifecycle" :targets [:repo :unit :app :files] :kind :static :run required-runtime-fails-loudly-rule-run :fn required-runtime-fails-loudly-rule-run}])

M
