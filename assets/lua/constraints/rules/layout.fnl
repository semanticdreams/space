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

(local known-non-layout-receivers
  {"sub-app" true
   "camera" true})

(local layouter-constructor-names
  {"Layout" true
   "LayoutRoot" true})

(fn fn-name-is-layouter? [name]
  "Check if a function name indicates it is a layouter."
  (and name (string.find name "layouter" 1 true)))

(fn call-is-layouter-method? [call]
  "Check if a call fact is a method invocation where the method is 'layouter'.
  These are method calls like (obj.layout:layouter), not Layout constructor
  calls with :layouter keyword arguments."
  (and call.method (= call.method "layouter")))

(fn layouter-call-contains-fn-name? [call fn-name]
  "Check if a call form text contains :layouter and the given function name
  used as the :layouter value in a Layout constructor-like context."
  (and call.form fn-name
       (string.find call.form ":layouter" 1 true)
       ;; The function name should appear near :layouter, not be the callee itself.
       ;; Check that the callee is NOT a layouter method call (obj:layouter).
       (not (call-is-layouter-method? call))
       (string.find call.form fn-name 1 true)))

(fn extract-receiver [callee]
  "Extract the receiver name from a method-style callee string like 'sub-app:set-size'.
  Returns nil if the callee is not a method call (no colon)."
  (when callee
    (local colon-pos (string.find callee ":" 1 true))
    (when colon-pos
      (callee:sub 1 (- colon-pos 1)))))

(fn callee-is-forbidden-setter? [callee]
  "Check if a callee is a forbidden setter.
  For method-style setters (e.g., child:set-size), also checks that the
  receiver is not a known non-layout object (e.g., sub-app)."
  (if (. forbidden-setters callee)
      true
      (do
        (var found false)
        (each [setter _ (pairs forbidden-setters)]
          (when (and (not found) (callee-ends-with? callee setter))
            ;; Method-style setter: check if receiver is a known non-layout object
            (local receiver (extract-receiver callee))
            (when (not (. known-non-layout-receivers receiver))
              (set found true))))
        found)))

(fn file-has-layouter-context? [ff]
  "Heuristic: check if any call form text or export key indicates a layouter
  is defined in this file.  Excludes method calls like (obj:layouter) which
  are invocations of an existing layouter, not definitions.
  When non-method :layouter calls exist (Layout constructors), named functions
  are only accepted if correlated with a call containing :layouter <name>.
  When no :layouter calls exist at all, name-only matches are accepted."
  (var found false)
  ;; Detect non-method :layouter calls and any :layouter calls at all.
  (var has-non-method-layouter-call false)
  (var has-any-layouter-call false)
  (each [_ call (ipairs (or ff.calls []))]
    (when (string.find (or call.form "") ":layouter" 1 true)
      (set has-any-layouter-call true)
      (when (not (call-is-layouter-method? call))
        (set has-non-method-layouter-call true))))
  ;; Named functions with 'layouter' in the name.
  (each [_ def (ipairs (or ff.definitions []))]
    (when (and (not found) (= def.kind :fn) (fn-name-is-layouter? def.name))
      (if has-non-method-layouter-call
          ;; Non-method :layouter calls exist: require the function name
          ;; to appear as a :layouter value in such a call.
          (each [_ call (ipairs (or ff.calls []))]
            (when (and (not found) (layouter-call-contains-fn-name? call def.name))
              (set found true)))
          (not has-any-layouter-call)
          ;; No :layouter calls at all: accept name-only (existing tests).
          (set found true))))
  (each [_ export (ipairs (or ff.exports []))]
    (when (and (not found) (= export.key "layouter"))
      (set found true)))
  ;; Call forms containing :layouter — exclude method calls (obj:layouter).
  (each [_ call (ipairs (or ff.calls []))]
    (when (and (not found)
               (string.find (or call.form "") ":layouter" 1 true)
               (not (call-is-layouter-method? call)))
      (set found true)))
  found)

(fn name-is-verified-layouter? [ff def-name]
  "Check if a function named def-name should be treated as a verified
  layouter in file ff.  Uses the same logic as file-has-layouter-context?:
  correlation with non-method :layouter calls when they exist, name-only
  when no :layouter calls exist at all."
  (var verified false)
  ;; Quick pre-scan: are there any :layouter calls?
  (var has-any-layouter-call false)
  (var has-non-method-layouter-call false)
  (each [_ call (ipairs (or ff.calls []))]
    (when (string.find (or call.form "") ":layouter" 1 true)
      (set has-any-layouter-call true)
      (when (not (call-is-layouter-method? call))
        (set has-non-method-layouter-call true))))
  (if has-non-method-layouter-call
      ;; Require correlation with a Layout constructor call.
      (each [_ call (ipairs (or ff.calls []))]
        (when (and (not verified) (layouter-call-contains-fn-name? call def-name))
          (set verified true)))
      (not has-any-layouter-call)
      ;; No :layouter calls at all: accept name-only.
      (set verified true))
  verified)

(fn collect-layouter-call-records [ff]
  "Return a list of {line, form} records for call forms containing :layouter
  as a keyword argument (not as a method call like obj:layouter)."
  (var records [])
  (each [_ call (ipairs (or ff.calls []))]
    (when (and (string.find (or call.form "") ":layouter" 1 true)
               (not (call-is-layouter-method? call)))
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
      ;; Named layouter functions (by name), verified via correlation
      (var layouter-names {})
      (each [_ def (ipairs (or ff.definitions []))]
        (when (and (= def.kind :fn) (fn-name-is-layouter? def.name)
                   (name-is-verified-layouter? ff def.name))
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

(fn def-creates-children? [ff def-name]
  (var found false)
  (local calls (if (= ff.calls nil) [] ff.calls))
  (each [_ call (ipairs calls)]
    (when (and (not found)
               (. child-creation-callees call.callee)
               (= (if (= call.enclosing-fn nil) "" call.enclosing-fn) def-name))
      (set found true)))
  found)

(fn def-has-returned-drop? [ff def]
  "Check if def returns a table with :drop (fn ...) or :drop (lambda ...).
  Symbolic :drop <symbol> is NOT accepted — proven same-scope binding
  detection is not reliably available from file-facts."
  (when (and def.form (def-creates-children? ff def.name))
    (if (string.find def.form ":drop[%s\n]*%(fn[%s\n%(]")
        true
        (string.find def.form ":drop[%s\n]*%(lambda[%s\n%(]")
        true
        false)))

(fn has-global-drop-path? [ff]
  "Check for file-level public drop paths: export key 'drop',
  definitions named 'drop', or set/tset mutations assigning .drop
  to a function literal."
  (var found false)
  (each [_ export (ipairs (if (= ff.exports nil) [] ff.exports))]
    (when (= export.key "drop")
      (set found true)))
  (each [_ def (ipairs (if (= ff.definitions nil) [] ff.definitions))]
    (when (and (not found)
               (= def.name "drop")
               (if (= def.kind :fn) true (= def.kind :local) true false))
      (set found true)))
  ;; Recognize set/tset assignment of .drop to a function as a public
  ;; drop path.  This handles factory patterns like (set button.drop (fn ...))
  ;; and (tset obj :drop (fn ...)).  Must be a function assignment — non-fn
  ;; values like nil/false/symbol do NOT count as a public drop path.
  (each [_ mut (ipairs (if (= ff.mutations nil) [] ff.mutations))]
    (when (and (not found)
               (if (= mut.op :set) true (= mut.op :tset) true false))
      (local p (if (= mut.path nil) [] mut.path))
      (local plen (length p))
      (when (and (>= plen 1) (= (. p plen) "drop")
                 (string.find (if (= mut.form nil) "" mut.form) "(fn " 1 true))
        (set found true))))
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
      (let [has-global-drop (has-global-drop-path? ff)
            has-cleanup (has-child-cleanup-evidence? ff)
            all-defs (or ff.definitions [])]
        ;; Track whether all child-creating defs have a drop path
        (var all-covered has-global-drop)
        (when (not has-global-drop)
          (set all-covered true)
          (each [_ def (ipairs all-defs)]
            (when (and all-covered
                       (def-creates-children? ff def.name)
                       (not (def-has-returned-drop? ff def)))
              (set all-covered false)))
          ;; Also check file-level creation (nil enclosing-fn) and access-based
          (when all-covered
            (each [_ call (ipairs (or ff.calls []))]
              (when (and all-covered
                         (. child-creation-callees call.callee)
                         (= call.enclosing-fn nil))
                (set all-covered false))))
          (when all-covered
            (each [_ access (ipairs (or ff.accesses []))]
              (when all-covered
                (local p (if (= access.path nil) [] access.path))
                (local plen (length p))
                (when (and (>= plen 2) (. child-creation-access-keys (. p plen)))
                  (set all-covered false)))))
          (when all-covered
            (each [_ access (ipairs (or ff.accesses []))]
              (when all-covered
                (local p (if (= access.path nil) [] access.path))
                (local plen (length p))
                (when (and (>= plen 2)
                           (= (. p 1) "renderer")
                           (. child-creation-access-keys (. p plen)))
                  (set all-covered false))))))
        (when (not all-covered)
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

(fn fn-def-has-interactive-access? [access-texts def cleaned-form]
  "Check if a function definition's form text contains one of the interactive
  access texts.  If cleaned-form is given, scan that instead of def.form."
  (when (and def.form def.kind (= def.kind :fn))
    (local form (if (not= cleaned-form nil) cleaned-form def.form))
    (var found false)
    (each [_ pat (ipairs access-texts)]
      (when (and (not found) (string.find form pat 1 true))
        (set found true)))
    found))

(fn fn-def-has-bare-interactive? [def cleaned-form]
  "Check if a function definition's form text contains bare 'clickables'
  or 'hoverables' as standalone tokens, excluding string/comment text
  and hyphenated identifiers.  String literals and comments are stripped first.
  If cleaned-form is given, scan that instead of def.form."
  (when (and def.form def.kind (= def.kind :fn))
    (local form (if (not= cleaned-form nil) cleaned-form def.form))
    (let [no-strings (strip-strings form)
          clean (strip-comments no-strings)]
      (var found false)
      (each [kw _ (pairs interactive-access-patterns)]
        (when (not found)
          (let [after-space-pat (.. "[%s%(]" kw)]
            (when (or (clean:find after-space-pat)
                      (= (clean:sub 1 (length kw)) kw))
              (set found true)))))
      found)))

(fn fn-def-has-dotted-interactive? [def cleaned-form]
  "Check if a function definition's form text contains a dotted interactive
  access like ctx.clickables, options.hoverables, app.clickables, etc.
  Strips string literals and comments first to avoid false positives.
  If cleaned-form is given, scan that instead of def.form."
  (when (and def.form def.kind (= def.kind :fn))
    (local form (if (not= cleaned-form nil) cleaned-form def.form))
    (local no-strings (strip-strings form))
    (local clean (strip-comments no-strings))
    (var found false)
    (each [kw _ (pairs interactive-access-patterns)]
      (when (not found)
        (local dotted-pat (.. "%." kw))
        (when (clean:find dotted-pat)
          (set found true))))
    found))

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

;; ---- nested-def masking for outer-fn false positives ----

(fn outer-only-form [def all-defs]
  "Return def.form with any nested definition forms blanked, so scanning
  the outer function does not attribute inner function accesses to it.
  All nested defs are blanked regardless of name, including <anonymous>."
  (var cleaned def.form)
  (each [_ other (ipairs all-defs)]
    (when (and (not= other def)
               cleaned
               other.form
               (string.find cleaned other.form 1 true))
      (local start (string.find cleaned other.form 1 true))
      (set cleaned (.. (cleaned:sub 1 (- start 1))
                       (string.rep "." (length other.form))
                       (cleaned:sub (+ start (length other.form)))))))
  cleaned)

(fn has-asserted-local? [form-text kw]
  "Check if form-text (with strings/comments stripped) contains
  (local kw (assert ...)) or (let [kw (assert ...)] ...) indicating
  kw was bound from an assert expression in this scope."
  (when form-text
    (local no-strings (strip-strings form-text))
    (local clean (strip-comments no-strings))
    (local pat (.. "%(local[%s\n]+" kw "[%s\n]+%(assert[%s\n]"))
    (if (clean:find pat)
        true
        (do
          (local let-pat (.. "%(let[%s\n]+%[" kw "[%s\n]+%(assert[%s\n]"))
          (if (clean:find let-pat) true false)))))

(fn has-bare-keyword? [form-text kw]
  "Check if kw appears as a bare standalone token in form-text
  (with strings/comments stripped), excluding hyphenated identifiers."
  (when form-text
    (local no-strings (strip-strings form-text))
    (local clean (strip-comments no-strings))
    (local after-space-pat (.. "[%s%(]" kw))
    (if (clean:find after-space-pat)
        true
        (= (clean:sub 1 (length kw)) kw))))

(fn shadows-keyword? [form-text kw]
  "Check if form-text shadows or reassigns kw with a local binding,
  let binding, set mutation, or parameter declaration."
  (when form-text
    (local no-strings (strip-strings form-text))
    (local clean (strip-comments no-strings))
    (if (clean:find (.. "%(local[%s\n]+" kw "[%s\n]"))
        true
        (if (clean:find (.. "%(let[%s\n]+%[" kw "[%s\n]"))
            true
            (if (clean:find (.. "(set " kw) 1 true)
                true
                false)))))

;; ---- precision helpers for interactive-context-assertion ----

(fn parent-has-asserted-local-before-child? [calls parent child kw]
  "Scope-safe closure-helper bypass predicate.  Returns true if ALL of:
  1) parent.form contains child.form;
  2) an assert call fact exists for callee 'assert' with enclosing-fn == parent.name
     and call.line < child.line (conservative on same-line);
  3) parent form text BEFORE the child occurrence (strings/comments stripped)
     contains either:
     a) (local kw (assert ...)) or (let [kw (assert ...)] ...), OR
     b) (local kw ...) (separate-local pattern where assert is a separate call)."
  (when (and parent.form child.form parent.name (not= parent.name "<anonymous>"))
    (local child-pos (string.find parent.form child.form 1 true))
    (when child-pos
      ;; Check criterion 2: assert call in parent scope before child
      (var assert-before-child false)
      (each [_ call (ipairs calls)]
        (when (and (not assert-before-child)
                   (= call.callee "assert")
                   call.enclosing-fn
                   (= call.enclosing-fn parent.name)
                   call.line
                   child.line
                   (< call.line child.line))
          (set assert-before-child true)))
      (when assert-before-child
        ;; Check criterion 3: parent form before child contains the binding pattern
        (local prefix (parent.form:sub 1 (- child-pos 1)))
        (local no-strings (strip-strings prefix))
        (local clean (strip-comments no-strings))
        ;; Try strict pattern: (local kw (assert ...))
        (local local-assert-pat (.. "%(local[%s\n]+" kw "[%s\n]+%(assert[%s\n]"))
        (if (clean:find local-assert-pat)
            true
            (do
              (local let-assert-pat (.. "%(let[%s\n]+%[" kw "[%s\n]+%(assert[%s\n]"))
              (if (clean:find let-assert-pat)
                  true
                  ;; Try separate-local pattern: (local kw <anything>)
                  ;; kw is bound as a local, and assert is a separate call
                  ;; fact (already verified via assert-before-child above).
                  (do
                    (local local-any-pat (.. "%(local[%s\n]+" kw "[%s\n]"))
                    (if (clean:find local-any-pat)
                        true
                        (do
                          (local let-any-pat (.. "%(let[%s\n]+%[" kw "[%s\n]"))
                          (if (clean:find let-any-pat) true false)))))))))))

;; ---- precision helpers for interactive-context-assertion ----

(fn extract-fn-params [def-form]
  "Extract the parameter names from a function definition form.
  Returns a table of param-name→true, or nil on failure."
  (var params {})
  (when def-form
    (var done false)
    (each [_ kw (ipairs ["(fn " "(lambda "])]
      (when (not done)
        (local start (def-form:find kw 1 true))
        (when start
          (var pos (+ start (length kw)))
          ;; Skip optional fn name past non-bracket/paren chars.
          ;; Avoid (or ...) by using a flag-based loop.
          (var still-scanning true)
          (while (and (<= pos (length def-form)) still-scanning)
            (local c (def-form:sub pos pos))
            (if (= c "[") (set still-scanning false)
                (= c "(") (set still-scanning false)
                (= c ")") (set still-scanning false)
                (= c "]") (set still-scanning false))
            (when still-scanning
              (set pos (+ pos 1))))
          (when (and (<= pos (length def-form))
                     (if (= (def-form:sub pos pos) "[") true
                         (= (def-form:sub pos pos) "(") true
                         false))
            (local open-char (def-form:sub pos pos))
            (local close-char (if (= open-char "[") "]" ")"))
            (set pos (+ pos 1))
            (local param-start pos)
            (var depth 1)
            (while (and (> depth 0) (<= pos (length def-form)))
              (when (= (def-form:sub pos pos) open-char)
                (set depth (+ depth 1)))
              (when (= (def-form:sub pos pos) close-char)
                (set depth (- depth 1)))
              (when (> depth 0)
                (set pos (+ pos 1))))
            (when (= depth 0)
              (local param-str (def-form:sub param-start (- pos 1)))
              (each [name (param-str:gmatch "%S+")]
                (tset params name true))))
          (set done true)))))
  (if (next params) params))

(fn interactive-context-assertion-rule-run [ctx]
  "Rule: flag interactive widgets using clickables or hoverables without
  an actual assert call in the same enclosing function."
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (var interactive-access-texts [])
    ;; Check whether this file is the interaction-router module — its
    ;; router.clickables / router.hoverables are internally owned arrays,
    ;; not external routing services that need assertion.
    (var is-interaction-router false)
    (when (if (= (or ff.module "") "next-app.interaction-router")
            true
            (and ff.path (str-ends-with? ff.path "next-app/interaction-router.fnl")))
      (set is-interaction-router true))
    (each [_ access (ipairs (or ff.accesses []))]
      (when (access-is-interactive? access)
        (let [text (or access.text "")]
          ;; Narrowly skip router.clickables / router.hoverables in the
          ;; interaction-router module — these are receiver-owned
          ;; infrastructure collections, not external ctx/app routing.
          (var router-owned false)
          (when is-interaction-router
            (when (if (= text "router.clickables") true (= text "router.hoverables") true)
              (set router-owned true)))
          (when (not router-owned)
            (var already false)
            (each [_ t (ipairs interactive-access-texts)]
              (when (= t text) (set already true)))
            (when (not already)
              (table.insert interactive-access-texts text))))))
    (let [calls (or ff.calls [])
          all-defs (or ff.definitions [])]
      (each [_ def (ipairs all-defs)]
        (var skip-because-param false)
        ;; Build a form that excludes nested named function definitions,
        ;; so accesses inside nested functions are not attributed to the
        ;; outer enclosing function (e.g., Button containing an asserted build).
        (local cleaned (outer-only-form def all-defs))
        (when def.form
          (local params (extract-fn-params def.form))
          (when params
            (each [kw _ (pairs interactive-access-patterns)]
              (when (and (not skip-because-param) (. params kw))
                ;; Only skip if the function has NO dotted interactive access.
                ;; A function with clickables as a parameter but also reading
                ;; ctx.clickables must still be flagged.
                (when (not (fn-def-has-dotted-interactive? def cleaned))
                  (when (fn-def-has-bare-interactive? def cleaned)
                    (set skip-because-param true)))))))
        (when (not skip-because-param)
          (let [has-access (fn-def-has-interactive-access? interactive-access-texts def cleaned)
                has-bare (fn-def-has-bare-interactive? def cleaned)
                asserted (fn-def-has-assert-call? calls def)]
            ;; Closure-helper bypass: if this def has bare interactive usage
            ;; and no assert of its own, check per keyword whether a parent
            ;; asserts it via (local kw (assert ...)) before the child def.
            ;; Uses scope-safe parent-has-asserted-local-before-child?
            ;; instead of the outer-only-form + has-asserted-local? approach
            ;; which over-masked parent form text.
            (var bare-covered {})
            (when (and (not asserted) has-bare (not has-access)
                       (not (fn-def-has-dotted-interactive? def cleaned)))
              (each [kw _ (pairs interactive-access-patterns)]
                (when (and (not (. bare-covered kw))
                           (has-bare-keyword? cleaned kw)
                           (not (shadows-keyword? def.form kw)))
                  (each [_ parent (ipairs all-defs)]
                    (when (and (not (. bare-covered kw))
                               (not= parent def)
                               (parent-has-asserted-local-before-child? calls parent def kw))
                      (tset bare-covered kw true))))))
            ;; Flag only if there is uncovered bare interactive usage
            (var has-uncovered-bare false)
            (when (and (not asserted) has-bare (not has-access)
                       (not (fn-def-has-dotted-interactive? def cleaned)))
              (each [kw _ (pairs interactive-access-patterns)]
                (when (and (not has-uncovered-bare)
                           (has-bare-keyword? cleaned kw)
                           (not (. bare-covered kw)))
                  (set has-uncovered-bare true))))
            (when (and (not asserted)
                       (if has-access
                           true
                           (and has-bare
                                (not (fn-def-has-dotted-interactive? def cleaned))
                                has-uncovered-bare)))
              (var access-used nil)
              (each [_ text (ipairs interactive-access-texts)]
                (when (and (not access-used) (string.find cleaned text 1 true))
                  (set access-used text)))
              (when (not access-used)
                (each [kw _ (pairs interactive-access-patterns)]
                  (when (and (not access-used) (string.find cleaned kw 1 true))
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
                             " is available before using it")}))))))))
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
