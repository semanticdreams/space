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
  "Check if a callee string ends with a method suffix like ':set-position'."
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

(fn fn-name-is-layouter? [name]
  "Check if a function name indicates it is a layouter.
  Matches any function whose name contains 'layouter'."
  (and name (string.find name "layouter" 1 true)))

(fn callee-is-forbidden-setter? [callee]
  "Check if a callee is a forbidden setter.
  Matches both method calls (obj:set-position) and direct calls (mark-layout-dirty)."
  (if (. forbidden-setters callee)
      true
      (do
        (var found false)
        (each [setter _ (pairs forbidden-setters)]
          (when (and (not found) (callee-ends-with? callee setter))
            (set found true)))
        found)))

(fn no-setters-in-layouters-rule-run [ctx]
  "Rule: flag calls to set-position/set-rotation/set-size/mark-layout-dirty/mark-measure-dirty
  inside functions whose name contains 'layouter'."
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    ;; Find all layouter function names in this file
    (var layouter-names {})
    (each [_ def (ipairs (or ff.definitions []))]
      (when (and (= def.kind :fn) (fn-name-is-layouter? def.name))
        (tset layouter-names def.name true)))
    ;; If there are layouter functions, check their calls
    (when (next layouter-names)
      (each [_ call (ipairs (or ff.calls []))]
        (when (and call.enclosing-fn (. layouter-names call.enclosing-fn)
                   (callee-is-forbidden-setter? call.callee))
          (table.insert diagnostics
            (Diagnostics.violation
              {:constraint-id "layout.no-setters-in-layouters"
               :family "layout-rendering"
               :message (.. "forbidden setter " call.callee " inside layouter "
                            call.enclosing-fn " in " (or ff.module ff.path))
               :file ff.path
               :line (or call.line 0)
               :column (or call.column 0)
               :evidence {:callee call.callee
                          :layouter call.enclosing-fn
                          :form (or call.form "")}
               :hint "Inside layouters, assign child layout fields directly instead of calling setters that dirty layout mid-pass."}))))))
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

(local drop-evidence-calrees
  {"clear-children" true
   "drop-children" true})

(fn callee-is-drop-method? [callee]
  "Check if a callee is a :drop method call (e.g. obj:drop)."
  (and callee (callee-ends-with? callee ":drop")))

(fn has-child-creation-evidence? [ff]
  "Check if a file-fact has evidence of retained child creation."
  (var found false)
  ;; Check calls to Layout or LayoutRoot
  (each [_ call (ipairs (or ff.calls []))]
    (when (. child-creation-callees call.callee)
      (set found true)))
  ;; Check accesses to children, scene-children, scene-objects, scene-terrains
  (each [_ access (ipairs (or ff.accesses []))]
    (when (not found)
      (let [p (or access.path [])
            plen (length p)]
        (when (and (>= plen 2) (. child-creation-access-keys (. p plen)))
          (set found true)))))
  ;; Check renderer child fields (e.g. renderer.children)
  (each [_ access (ipairs (or ff.accesses []))]
    (when (not found)
      (let [p (or access.path [])
            plen (length p)]
        (when (and (>= plen 2)
                   (= (. p 1) "renderer")
                   (. child-creation-access-keys (. p plen)))
          (set found true)))))
  found)

(fn has-drop-evidence? [ff]
  "Check if a file-fact has evidence of child drop/cleanup."
  (var found false)
  ;; Check for a function named 'drop'
  (each [_ def (ipairs (or ff.definitions []))]
    (when (and (= def.kind :fn) (= def.name "drop"))
      (set found true)))
  ;; Check for :drop method calls
  (each [_ call (ipairs (or ff.calls []))]
    (when (and (not found) (callee-is-drop-method? call.callee))
      (set found true)))
  ;; Check for clear-children or drop-children calls
  (each [_ call (ipairs (or ff.calls []))]
    (when (and (not found) (. drop-evidence-calrees call.callee))
      (set found true)))
  found)

(fn owned-child-drop-rule-run [ctx]
  "Rule: flag modules creating retained children (Layout, LayoutRoot, scene-children, etc.)
  without providing a drop path."
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (when (and (has-child-creation-evidence? ff)
               (not (has-drop-evidence? ff)))
      (table.insert diagnostics
        (Diagnostics.violation
          {:constraint-id "layout.owned-child-drop"
           :family "layout-rendering"
           :message (.. "retained child creation without drop in " (or ff.module ff.path))
           :file ff.path
           :line 0
           :column 0
           :evidence {:file ff.path
                      :module (or ff.module ff.path)}
           :hint "Provide a drop function, :drop method, clear-children, or drop-children for retained children"}))))
  (if (> (length diagnostics) 0) diagnostics nil))

;; ---------------------------------------------------------------------------
;; Rule 3: layout.interactive-context-assertion
;; ---------------------------------------------------------------------------

(local interactive-access-patterns
  {"clickables" true
   "hoverables" true})

(fn access-is-interactive? [access]
  "Check if an access record refers to clickables or hoverables
  (either bare or as ctx.clickables / ctx.hoverables)."
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

(fn fn-def-has-assert? [def]
  "Check if a function definition's form text contains 'assert'."
  (and def.form def.kind (= def.kind :fn)
       (string.find def.form "assert" 1 true)))

(fn interactive-context-assertion-rule-run [ctx]
  "Rule: flag interactive widgets using clickables or hoverables without assert
  in the same enclosing function."
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    ;; Collect all unique interactive access texts from the file's access list
    (var interactive-access-texts [])
    (each [_ access (ipairs (or ff.accesses []))]
      (when (access-is-interactive? access)
        (let [text (or access.text "")]
          (var already false)
          (each [_ t (ipairs interactive-access-texts)]
            (when (= t text)
              (set already true)))
          (when (not already)
            (table.insert interactive-access-texts text)))))
    ;; For each function definition that references an interactive access...
    (each [_ def (ipairs (or ff.definitions []))]
      (when (fn-def-has-interactive-access? interactive-access-texts def)
        ;; If the function does not have assert, flag it
        (when (not (fn-def-has-assert? def))
          ;; Find the specific interactive access text used in this function
          (var access-used nil)
          (each [_ text (ipairs interactive-access-texts)]
            (when (and (not access-used) (string.find def.form text 1 true))
              (set access-used text)))
          (table.insert diagnostics
            (Diagnostics.violation
              {:constraint-id "layout.interactive-context-assertion"
               :family "layout-rendering"
               :message (.. "function " (or def.name "<anonymous>") " uses "
                            (or access-used "interactive context") " without assert in "
                            (or ff.module ff.path))
               :file ff.path
               :line (or def.line 0)
               :column (or def.column 0)
               :evidence {:function-name (or def.name "<anonymous>")
                          :interactive-access (or access-used "clickables/hoverables")}
               :hint (.. "Assert that " (or access-used "the interactive context")
                         " is available before using it, instead of silently no-oping")}))))))
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
