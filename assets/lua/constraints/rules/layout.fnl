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
  is defined in this file.  Catches both named layouter functions and inline
  :layouter (fn ...) table entries in Layout(...) calls."
  (var found false)
  ;; Named layouter functions
  (each [_ def (ipairs (or ff.definitions []))]
    (when (and (= def.kind :fn) (fn-name-is-layouter? def.name))
      (set found true)))
  ;; Export key
  (each [_ export (ipairs (or ff.exports []))]
    (when (and (not found) (= export.key "layouter"))
      (set found true)))
  ;; Call form text contains :layouter (catches inline forms)
  (each [_ call (ipairs (or ff.calls []))]
    (when (and (not found) (string.find (or call.form "") ":layouter" 1 true))
      (set found true)))
  found)

(fn no-setters-in-layouters-rule-run [ctx]
  "Rule: flag calls to forbidden setters inside layouter functions
  (named or inline :layouter fn forms)."
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (when (file-has-layouter-context? ff)
      ;; Build layouter name set for named functions
      (var layouter-names {})
      (each [_ def (ipairs (or ff.definitions []))]
        (when (and (= def.kind :fn) (fn-name-is-layouter? def.name))
          (tset layouter-names def.name true)))
      (each [_ call (ipairs (or ff.calls []))]
        (when (callee-is-forbidden-setter? call.callee)
          (let [efn (or call.enclosing-fn "")]
            (when (or (. layouter-names efn)
                      ;; In a file with layouter context, anonymous functions
                      ;; are likely inline :layouter (fn ...) entries
                      (and (= efn "<anonymous>")
                           (not (next layouter-names))))
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
  or 'hoverables' as a standalone token (not part of a dotted access or
  hyphenated identifier like 'handle-clickables')."
  (when (and def.form def.kind (= def.kind :fn))
    (var found false)
    (each [kw _ (pairs interactive-access-patterns)]
      (when (not found)
        ;; Only match when preceded by whitespace, opening paren, or at start.
        (let [after-space-pat (.. "[%s%(]" kw)]
          (when (or (def.form:find after-space-pat)
                    (= (def.form:sub 1 (length kw)) kw))
            (set found true)))))
    found))

(fn fn-def-has-assert-call? [calls def]
  "Check whether any call in the same enclosing function is to 'assert'."
  (when def.name
    (var found false)
    (each [_ call (ipairs calls)]
      (when (and (not found)
                 (= call.callee "assert")
                 (= (or call.enclosing-fn "") (or def.name "")))
        (set found true)))
    found))

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
