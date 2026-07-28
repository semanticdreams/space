;; Shared helpers for Layout/Rendering constraint rule tests.
;; Avoids duplication across split test files.
;; Structure-compliant: no (or ...) fallbacks, no (let ...) forms.

(fn nil-default [val default]
  "Return val if non-nil, otherwise default."
  (if (= val nil) default val))

(fn make-file-fact [opts]
  "Create a synthetic file-fact record for testing rule functions."
  (local o (nil-default opts {}))
  {:target (nil-default o.target {:kind :repo :name :test})
   :path (nil-default o.path "/test/module.fnl")
   :module (nil-default o.module "test-module")
   :requires (nil-default o.requires [])
   :definitions (nil-default o.definitions [])
   :exports (nil-default o.exports [])
   :calls (nil-default o.calls [])
   :accesses (nil-default o.accesses [])
   :mutations (nil-default o.mutations [])
   :metrics (nil-default o.metrics {:module-lines 0
                                     :max-nesting-depth 0
                                     :max-anonymous-callback-depth 0
                                     :max-table-literal-size 0
                                     :functions []})})

(fn make-fact-db [file-facts]
  "Create a synthetic fact-db from a list of file-fact records."
  (local by-file {})
  (each [_ ff (ipairs file-facts)]
    (tset by-file ff.path ff))
  {:files file-facts
   :by-file by-file})

(fn make-ctx [file-facts]
  "Create a context table for rule execution."
  {:target {:kind :repo :name :test}
   :facts (make-fact-db file-facts)
   :files []})

(fn find-rule-by-id [rules id]
  "Find a rule in a rules list by its :id field."
  (var found nil)
  (each [_ r (ipairs rules)]
    (when (= r.id id)
      (set found r)))
  found)

{:make-file-fact make-file-fact
 :make-fact-db make-fact-db
 :make-ctx make-ctx
 :find-rule-by-id find-rule-by-id}
