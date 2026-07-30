;; Ancestor snapshot/restore precision tests for test-isolation constraint.
;; Extracted to keep precision module under 1200-line limit.
(local tests [])

(fn make-file-fact [opts]
  "Create a synthetic file-fact record for testing rule functions."
  (local o (if opts opts {}))
  {:target (if o.target o.target {:kind :repo :name :test})
   :path (if o.path o.path "/test/module.fnl")
   :module (if o.module o.module "test-module")
   :requires (if o.requires o.requires [])
   :definitions (if o.definitions o.definitions [])
   :exports (if o.exports o.exports [])
   :calls (if o.calls o.calls [])
   :accesses (if o.accesses o.accesses [])
   :mutations (if o.mutations o.mutations [])
   :metrics (if o.metrics o.metrics {:module-lines 0
                                      :max-nesting-depth 0
                                      :max-anonymous-callback-depth 0
                                      :max-table-literal-size 0
                                      :functions []})})

(fn make-fact-db [file-facts]
  (local by-file {})
  (each [_ ff (ipairs file-facts)]
    (tset by-file ff.path ff))
  {:files file-facts :by-file by-file})

(fn make-ctx [file-facts]
  {:target {:kind :repo :name :test}
   :facts (make-fact-db file-facts)
   :files []})

(fn find-rule-by-id [rules id]
  (var found nil)
  (each [_ r (ipairs rules)]
    (when (= r.id id) (set found r)))
  found)

(fn get-test-isolation-rule []
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule lifecycle.global-mutation-restoration should be in rules list")
  rule)

;; --- Ancestor snapshot/restore covering descendant mutations ---
(fn mutation-restoration-allows-ancestor-snapshot-covers-descendant-mutation []
  "Ancestor snapshot of app.engine.events covers descendant mutation
   app.engine.events.mouse-wheel when snap/restore use the same ancestor path."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-ancestor-cover"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-ancestor-cover []
  (local orig app.engine.events)
  (set app.engine.events.mouse-wheel nil)
  (do-test)
  (set app.engine.events orig))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine" "events" "mouse-wheel"]
                                           :line 7 :column 1
                                           :form "(set app.engine.events.mouse-wheel nil)"
                                           :enclosing-fn "test-ancestor-cover"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "ancestor snap of app.engine.events should cover descendant app.engine.events.mouse-wheel mutation"))
(fn mutation-restoration-allows-sensitive-base-ancestor-covers-deep-descendant []
  "Sensitive base app.engine snapshot covers 4-deep descendant mutation
   app.engine.events.mouse-wheel — ancestor at sensitive base is valid."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-base-cover"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-base-cover []
  (local orig app.engine)
  (set app.engine.events.mouse-wheel nil)
  (do-test)
  (set app.engine orig))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine" "events" "mouse-wheel"]
                                           :line 7 :column 1
                                           :form "(set app.engine.events.mouse-wheel nil)"
                                           :enclosing-fn "test-base-cover"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "sensitive base app.engine snap should cover deep descendant app.engine.events.mouse-wheel"))
(fn mutation-restoration-flags-ancestor-wrong-restore-var []
  "Ancestor snapshot of app.engine.events but restore uses wrong variable.
   Must still flag — snapshot var must match restore var."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-wrong-var"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-wrong-var []
  (local orig app.engine.events)
  (set app.engine.events.mouse-wheel nil)
  (set app.engine.events other-var))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine" "events" "mouse-wheel"]
                                           :line 7 :column 1
                                           :form "(set app.engine.events.mouse-wheel nil)"
                                           :enclosing-fn "test-wrong-var"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag when ancestor restore uses different variable")
  (assert (> (length result) 0) "should have at least one diagnostic"))
(fn mutation-restoration-flags-ancestor-restore-before-mutation []
  "Ancestor snapshot but restore happens before the descendant mutation.
   Must still flag — restore must come after mutation."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-restore-before"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-restore-before []
  (local orig app.engine.events)
  (set app.engine.events orig)
  (set app.engine.events.mouse-wheel nil))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine" "events" "mouse-wheel"]
                                           :line 8 :column 1
                                           :form "(set app.engine.events.mouse-wheel nil)"
                                           :enclosing-fn "test-restore-before"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag when ancestor restore happens before descendant mutation")
  (assert (> (length result) 0) "should have at least one diagnostic"))
(fn mutation-restoration-flags-ancestor-no-restore []
  "Ancestor snapshot of app.engine.events but no restore after mutation.
   Must still flag — snapshot alone does not restore."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-no-restore"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-no-restore []
  (local orig app.engine.events)
  (set app.engine.events.mouse-wheel nil)
  (do-test))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine" "events" "mouse-wheel"]
                                           :line 7 :column 1
                                           :form "(set app.engine.events.mouse-wheel nil)"
                                           :enclosing-fn "test-no-restore"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag when ancestor snapshot exists but not restored")
  (assert (> (length result) 0) "should have at least one diagnostic"))
(fn mutation-restoration-flags-bare-app-not-cover []
  "Bare (local orig app) should NOT cover app.engine.events.mouse-wheel —
   app is too broad and not a sensitive base."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-app-too-broad"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-app-too-broad []
  (local orig app)
  (set app.engine.events.mouse-wheel nil)
  (do-test)
  (set app orig))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine" "events" "mouse-wheel"]
                                           :line 7 :column 1
                                           :form "(set app.engine.events.mouse-wheel nil)"
                                           :enclosing-fn "test-app-too-broad"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag — app snapshot is too broad for descendant mutation")
  (assert (> (length result) 0) "should have at least one diagnostic"))
(fn mutation-restoration-flags-unrelated-ancestor []
  "Snapshot of app.renderers should NOT cover app.engine.events mutation —
   ancestor path must be a true prefix of the mutated path."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-unrelated-ancestor"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-unrelated-ancestor []
  (local orig app.renderers)
  (set app.engine.events.mouse-wheel nil)
  (set app.renderers orig))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine" "events" "mouse-wheel"]
                                           :line 7 :column 1
                                           :form "(set app.engine.events.mouse-wheel nil)"
                                           :enclosing-fn "test-unrelated-ancestor"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag — app.renderers is unrelated to app.engine.events.mouse-wheel")
  (assert (> (length result) 0) "should have at least one diagnostic"))
(fn mutation-restoration-flags-ancestor-let-no-restore []
  "Ancestor snapshot via let but no restore after mutation.
   Must still flag — snapshot alone does not restore."
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                              :module "tests.test-module"
                              :definitions [{:kind :fn
                                             :name "test-let-no-restore"
                                             :top-level? true
                                             :line 5 :column 1
                                             :length 200
                                             :form "(fn test-let-no-restore []
  (let [orig app.engine.events]
    (set app.engine.events.mouse-wheel nil)
    (do-test))"}]
                              :mutations [{:op :set
                                           :path ["app" "engine" "events" "mouse-wheel"]
                                           :line 8 :column 1
                                           :form "(set app.engine.events.mouse-wheel nil)"
                                           :enclosing-fn "test-let-no-restore"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag when ancestor let-snapshot exists but not restored")
  (assert (> (length result) 0) "should have at least one diagnostic"))
(table.insert tests {:name "T11-10 allows ancestor snapshot covers descendant mutation" :fn mutation-restoration-allows-ancestor-snapshot-covers-descendant-mutation})
(table.insert tests {:name "T11-11 allows sensitive base ancestor covers deep descendant" :fn mutation-restoration-allows-sensitive-base-ancestor-covers-deep-descendant})
(table.insert tests {:name "T11-12 flags ancestor wrong restore var" :fn mutation-restoration-flags-ancestor-wrong-restore-var})
(table.insert tests {:name "T11-13 flags ancestor restore before mutation" :fn mutation-restoration-flags-ancestor-restore-before-mutation})
(table.insert tests {:name "T11-14 flags ancestor no restore" :fn mutation-restoration-flags-ancestor-no-restore})
(table.insert tests {:name "T11-15 flags bare app not cover" :fn mutation-restoration-flags-bare-app-not-cover})
(table.insert tests {:name "T11-16 flags unrelated ancestor" :fn mutation-restoration-flags-unrelated-ancestor})
(table.insert tests {:name "T11-17 flags ancestor let no restore" :fn mutation-restoration-flags-ancestor-let-no-restore})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-rules-test-isolation-ancestor" :tests tests})))

{:name "constraints-rules-test-isolation-ancestor" :tests tests :main main}
