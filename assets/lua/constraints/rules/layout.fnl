;; Layout/Rendering constraint rules for experimental Fennel constraints.
;; Three rules: no-setters-in-layouters, owned-child-drop, interactive-context-assertion.

(local Diagnostics (require :constraints.diagnostics))
(local M {})

;; ---------------------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------------------

(fn str-ends-with? [s suffix]
  "Check if string s ends with suffix."
  (and s (>= (length s) (length suffix))
       (= (s:sub (- (length s) (- (length suffix) 1))) suffix)))

(fn callee-ends-with? [callee suffix]
  "Check if a callee string ends with a method suffix."
  (str-ends-with? callee suffix))

;; Strip double-quoted string literals from form text so that pattern
;; matching does not produce false positives on string contents.
(fn strip-strings [s]
  (s:gsub "\"[^\"]*\"" ""))

;; Strip Fennel comments (; to end of line) from form text.
;; Must be called after strip-strings to avoid removing semicolons
;; that appear inside string literals.
(fn strip-comments [s]
  (let [lines []]
    (each [line (s:gmatch "[^\n]*")]
      (let [comment-pos (string.find line ";" 1 true)]
        (if comment-pos
            (table.insert lines (string.sub line 1 (- comment-pos 1)))
            (table.insert lines line))))
    (table.concat lines "\n")))

;; ---------------------------------------------------------------------------
;; Rule 1: layout.no-setters-in-layouters
;; ---------------------------------------------------------------------------

(local forbidden-setters
  {":set-position" true
   ":set-rotation" true
   ":set-size" true
   "mark-layout-dirty" true
   "mark-measure-dirty" true})

(local layouter-constructor-names
  {"Layout" true
   "LayoutRoot" true})

(fn fn-name-is-layouter? [name]
  "Check if a function name indicates it is a layouter."
  (and name (string.find name "layouter" 1 true)))

(fn callee-is-forbidden-setter? [callee]
  "Check if a callee is a forbidden setter."
  (if (. forbidden-setters callee)
      true
      (do
        (var found false)
        (each [setter _ (pairs forbidden-setters)]
          (when (and (not found) (callee-ends-with? callee setter))
            (set found true)))
        found)))

(fn file-has-layouter-context? [ff]
  "Heuristic: check if any call form text or export key indicates a layouter
  is defined in this file."
  (var found false)
  (each [_ def (ipairs (or ff.definitions []))]
    (when (and (= def.kind :fn) (fn-name-is-layouter? def.name))
      (set found true)))
  (each [_ export (ipairs (or ff.exports []))]
    (when (and (not found) (= export.key "layouter"))
      (set found true)))
  (each [_ call (ipairs (or ff.calls []))]
    (when (and (not found) (string.find (or call.form "") ":layouter" 1 true))
      (set found true)))
  found)

(fn collect-layouter-call-records [ff]
  "Return a list of {line, form} records for call forms containing :layouter."
  (var records [])
  (each [_ call (ipairs (or ff.calls []))]
    (when (string.find (or call.form "") ":layouter" 1 true)
      (table.insert records {:line (or call.line 0) :form (or call.form "")})))
  records)

(fn anonymous-def-is-layouter-callback? [def layouter-call-records]
  "Check if an anonymous definition's form text appears as a substring
  of any :layouter call form — form-text containment proves the definition
  is inside the Layout call."
  (when (not def.form) (lua "return false"))
  (var found false)
  (each [_ lc (ipairs layouter-call-records)]
    (when (and (not found)
               (string.find lc.form def.form 1 true))
      (set found true)))
  found)

(fn build-def-line-map [defs]
  "Build a sorted list of all function definitions with line and name for
  enclosure resolution by line number."
  (var fn-defs [])
  (each [_ def (ipairs (or defs []))]
    (when (and (= def.kind :fn) def.line)
      (table.insert fn-defs {:line def.line :name def.name :form def.form})))
  (table.sort fn-defs (fn [a b] (< a.line b.line)))
  fn-defs)

(fn find-enclosing-fn-def [sorted-fn-defs call-line]
  "Find the function definition that most likely encloses a call at call-line.
  Returns the definition with the greatest line <= call-line, or nil."
  (var enclosing nil)
  (each [_ d (ipairs sorted-fn-defs)]
    (when (<= d.line call-line)
      (set enclosing d)))
  enclosing)

(fn no-setters-in-layouters-rule-run [ctx]
  "Rule: flag calls to forbidden setters inside layouter functions
  (named or inline :layouter fn forms)."
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (when (file-has-layouter-context? ff)
      ;; Named layouter functions (by name)
      (var layouter-names {})
      (each [_ def (ipairs (or ff.definitions []))]
        (when (and (= def.kind :fn) (fn-name-is-layouter? def.name))
          (tset layouter-names def.name true)))
      ;; :layouter call records for anonymous correlation
      (var layouter-call-records (collect-layouter-call-records ff))
       ;; Identify anonymous definitions that are inline layouter callbacks
       ;; by form-text containment — the def form appears as a substring
       ;; of a :layouter call form.  Store as a map from def line to form text.
       (var layouter-anon-by-line {})
       (each [_ def (ipairs (or ff.definitions []))]
         (when (and (= def.kind :fn) (= def.name "<anonymous>")
                    (anonymous-def-is-layouter-callback? def layouter-call-records))
           (tset layouter-anon-by-line (or def.line 0) def.form)))
       ;; Resolve duplicate entries: when multiple anonymous defs share the
       ;; same form text and that form appears in a layouter call, skip ALL
       ;; of them conservatively.  Choosing by distance to the outer Layout
       ;; call start can pick the wrong callback when identical forms appear
       ;; under different keys in the same Layout call (e.g., :measurer vs
       ;; :layouter).  This is a deliberate false-negative tradeoff to avoid
       ;; false positives.
       (var form-counts {})
       (each [line form (pairs layouter-anon-by-line)]
         (tset form-counts form (+ 1 (or (. form-counts form) 0))))
       (each [form count (pairs form-counts)]
         (when (> count 1)
           (each [line lform (pairs layouter-anon-by-line)]
             (when (= lform form)
               (tset layouter-anon-by-line line nil)))))
       ;; Build sorted list of all fn definitions for enclosure resolution
      (var all-fn-defs (build-def-line-map ff.definitions))
      ;; Check each call
      (each [_ call (ipairs (or ff.calls []))]
        (when (callee-is-forbidden-setter? call.callee)
          (let [efn (or call.enclosing-fn "")]
            (when (or (. layouter-names efn)
                      ;; Anonymous: find the actual enclosing definition by
                      ;; line, and flag only if that definition is a verified
                      ;; layouter callback.
                      (and (= efn "<anonymous>")
                           (not (next layouter-names))
                           (let [enclosing-def (find-enclosing-fn-def all-fn-defs (or call.line 0))]
                             (and enclosing-def
                                  (= enclosing-def.name "<anonymous>")
                                  (. layouter-anon-by-line enclosing-def.line)
                                  (string.find (or enclosing-def.form "")
                                               (or call.form "") 1 true)))))
              (table.insert diagnostics
                (Diagnostics.violation
                  {:constraint-id "layout.no-setters-in-layouters"
                   :family "layout-rendering"
                   :message (.. "forbidden setter " call.callee " inside layouter "
                                (or call.enclosing-fn "<anonymous>") " in " (or ff.module ff.path))
                   :file ff.path :line (or call.line 0) :column (or call.column 0)
                   :evidence {:callee call.callee
                              :layouter (or call.enclosing-fn "<anonymous>")
                              :form (or call.form "")}
                   :hint "Inside layouters, assign child layout fields directly instead of calling setters that dirty layout mid-pass."}))))))))
  (if (> (length diagnostics) 0) diagnostics nil))

;; ---------------------------------------------------------------------------
;; Rule 2: layout.owned-child-drop
;; ---------------------------------------------------------------------------

(local child-creation-callees
  {"Layout" true
   "LayoutRoot" true})

(local child-creation-access-keys
  {"children" true
   "scene-children" true
   "scene-objects" true
   "scene-terrains" true})

(local child-cleanup-calrees
  {"clear-children" true
   "drop-children" true})

(fn callee-is-drop-method? [callee]
  "Check if a callee is a :drop method call."
  (and callee (callee-ends-with? callee ":drop")))

(fn has-child-creation-evidence? [ff]
  "Check if a file-fact has evidence of retained child creation."
  (var found false)
  (each [_ call (ipairs (or ff.calls []))]
    (when (. child-creation-callees call.callee)
      (set found true)))
  (each [_ access (ipairs (or ff.accesses []))]
    (when (not found)
      (let [p (or access.path [])
            plen (length p)]
        (when (and (>= plen 2) (. child-creation-access-keys (. p plen)))
          (set found true)))))
  (each [_ access (ipairs (or ff.accesses []))]
    (when (not found)
      (let [p (or access.path [])
            plen (length p)]
        (when (and (>= plen 2)
                   (= (. p 1) "renderer")
                   (. child-creation-access-keys (. p plen)))
          (set found true)))))
  found)

(fn has-public-drop-path? [ff]
  "Check if a module exposes a public drop path: a function named 'drop'
  (either fn or local definition) OR an export key 'drop'."
  (var found false)
  (each [_ export (ipairs (or ff.exports []))]
    (when (= export.key "drop")
      (set found true)))
  (each [_ def (ipairs (or ff.definitions []))]
    (when (and (not found)
               (= def.name "drop")
               (or (= def.kind :fn) (= def.kind :local)))
      (set found true)))
  found)

(fn has-child-cleanup-evidence? [ff]
  "Check if a file-fact has evidence of child cleanup."
  (var found false)
  (each [_ call (ipairs (or ff.calls []))]
    (when (and (not found) (callee-is-drop-method? call.callee))
      (set found true)))
  (each [_ call (ipairs (or ff.calls []))]
    (when (and (not found) (. child-cleanup-calrees call.callee))
      (set found true)))
  found)

(fn owned-child-drop-rule-run [ctx]
  "Rule: flag modules creating retained children without a public
  drop path AND child cleanup evidence."
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (when (has-child-creation-evidence? ff)
      (let [has-drop-path (has-public-drop-path? ff)
            has-cleanup (has-child-cleanup-evidence? ff)]
        (when (not has-drop-path)
          (table.insert diagnostics
            (Diagnostics.violation
              {:constraint-id "layout.owned-child-drop"
               :family "layout-rendering"
               :message (.. "retained child creation without public drop path in " (or ff.module ff.path))
               :file ff.path :line 0 :column 0
               :evidence {:file ff.path :module (or ff.module ff.path)
                          :missing "drop definition or returned table :drop"}
               :hint "Define a drop function or return a table with a :drop key"})))
        (when (not has-cleanup)
          (table.insert diagnostics
            (Diagnostics.violation
              {:constraint-id "layout.owned-child-drop"
               :family "layout-rendering"
               :message (.. "retained child creation without cleanup evidence in " (or ff.module ff.path))
               :file ff.path :line 0 :column 0
               :evidence {:file ff.path :module (or ff.module ff.path)
                          :missing "child drop evidence"}
               :hint "Add :drop calls, clear-children, or drop-children"}))))))
  (if (> (length diagnostics) 0) diagnostics nil))

;; ---------------------------------------------------------------------------
;; Rule 3: layout.interactive-context-assertion
;; ---------------------------------------------------------------------------

(local interactive-access-patterns
  {"clickables" true
   "hoverables" true})

(fn access-is-interactive? [access]
  "Check if an access record refers to clickables or hoverables."
  (let [p (or access.path [])
        plen (length p)
        last-seg (and (>= plen 1) (. p plen))]
    (and last-seg (. interactive-access-patterns last-seg))))

(fn fn-def-has-interactive-access? [access-texts def]
  "Check if a function definition's form text contains one of the interactive access texts."
  (when (and def.form def.kind (= def.kind :fn))
    (var found false)
    (each [_ pat (ipairs access-texts)]
      (when (and (not found) (string.find def.form pat 1 true))
        (set found true)))
    found))

(fn fn-def-has-bare-interactive? [def]
  "Check if a function definition's form text contains bare 'clickables'
  or 'hoverables' as standalone tokens, excluding string/comment text
  and hyphenated identifiers.  String literals and comments are stripped first."
  (when (and def.form def.kind (= def.kind :fn))
    (let [no-strings (strip-strings def.form)
          clean (strip-comments no-strings)]
      (var found false)
      (each [kw _ (pairs interactive-access-patterns)]
        (when (not found)
          (let [after-space-pat (.. "[%s%(]" kw)]
            (when (or (clean:find after-space-pat)
                      (= (clean:sub 1 (length kw)) kw))
              (set found true)))))
      found)))

(fn fn-def-has-assert-call? [calls def]
  "Check whether any call in the same enclosing function is to 'assert'.
  For anonymous functions, fall back to per-definition form-text detection
  to avoid cross-anonymous-function correlation."
  (if (not def.name)
      false
      (= def.name "<anonymous>")
      ;; Anonymous functions: check the definition's own form text for
      ;; an actual (assert ...) or (assert) call — no cross-correlation.
      ;; Strip strings and comments first to avoid false positives.
      (do
        (let [no-strings (strip-strings def.form)
              clean (strip-comments no-strings)]
          (or (clean:find "(assert " 1 true)
              (clean:find "(assert)" 1 true))))
      ;; Named functions: correlate via call facts.
      (do
        (var found false)
        (each [_ call (ipairs calls)]
          (when (and (not found)
                     (= call.callee "assert")
                     (= (or call.enclosing-fn "") (or def.name "")))
            (set found true)))
        found)))

(fn interactive-context-assertion-rule-run [ctx]
  "Rule: flag interactive widgets using clickables or hoverables without
  an actual assert call in the same enclosing function."
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (var interactive-access-texts [])
    (each [_ access (ipairs (or ff.accesses []))]
      (when (access-is-interactive? access)
        (let [text (or access.text "")]
          (var already false)
          (each [_ t (ipairs interactive-access-texts)]
            (when (= t text) (set already true)))
          (when (not already)
            (table.insert interactive-access-texts text)))))
    (let [calls (or ff.calls [])]
      (each [_ def (ipairs (or ff.definitions []))]
        (let [has-access (fn-def-has-interactive-access? interactive-access-texts def)
              has-bare (fn-def-has-bare-interactive? def)]
          (when (and (or has-access has-bare)
                     (not (fn-def-has-assert-call? calls def)))
            (var access-used nil)
            (each [_ text (ipairs interactive-access-texts)]
              (when (and (not access-used) (string.find def.form text 1 true))
                (set access-used text)))
            (when (not access-used)
              (each [kw _ (pairs interactive-access-patterns)]
                (when (and (not access-used) (string.find def.form kw 1 true))
                  (set access-used kw))))
            (table.insert diagnostics
              (Diagnostics.violation
                {:constraint-id "layout.interactive-context-assertion"
                 :family "layout-rendering"
                 :message (.. "function " (or def.name "<anonymous>") " uses "
                              (or access-used "interactive context") " without assert in "
                              (or ff.module ff.path))
                 :file ff.path :line (or def.line 0) :column (or def.column 0)
                 :evidence {:function-name (or def.name "<anonymous>")
                            :interactive-access (or access-used "clickables/hoverables")}
                 :hint (.. "Assert that " (or access-used "the interactive context")
                           " is available before using it")})))))))
  (if (> (length diagnostics) 0) diagnostics nil))

;; ---------------------------------------------------------------------------
;; Rule registry
;; ---------------------------------------------------------------------------

(fn M.rules []
  "Return the list of layout-rendering rules."
  [{:id "layout.no-setters-in-layouters"
    :family "layout-rendering"
    :targets [:repo]
    :kind :static
    :run no-setters-in-layouters-rule-run
    :fn no-setters-in-layouters-rule-run}
   {:id "layout.owned-child-drop"
    :family "layout-rendering"
    :targets [:repo]
    :kind :static
    :run owned-child-drop-rule-run
    :fn owned-child-drop-rule-run}
   {:id "layout.interactive-context-assertion"
    :family "layout-rendering"
    :targets [:repo]
    :kind :static
    :run interactive-context-assertion-rule-run
    :fn interactive-context-assertion-rule-run}])

M
