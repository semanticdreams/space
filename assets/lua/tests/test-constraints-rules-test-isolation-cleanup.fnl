;; Cleanup-closure restore precision tests for test-isolation constraint.
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

;; C1: parent snapshot before child + child restore assignment → pass
(fn mutation-restoration-allows-child-cleanup-restoring-parent-snapshot []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl" :module "tests.test-module"
                              :definitions [{:kind :fn :name "setup-scene" :top-level? true :line 10 :column 1 :length 200
                                             :form "(fn setup-scene []\n  (local snap app.physics-containment-config)\n  (fn cleanup []\n    (set app.physics-containment-config snap)))"}
                                            {:kind :fn :name "cleanup" :top-level? false :line 12 :column 3 :length 60
                                             :form "(fn cleanup []\n    (set app.physics-containment-config snap))"}]
                              :mutations [{:op :set :path ["app" "physics-containment-config"] :line 13 :column 5
                                           :form "(set app.physics-containment-config snap)" :enclosing-fn "cleanup"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "C1: child cleanup restoring parent snapshot should pass"))

;; C2: child mutates unrelated var → still flags
(fn mutation-restoration-flags-cleanup-unrelated-mutation []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl" :module "tests.test-module"
                              :definitions [{:kind :fn :name "setup-scene" :top-level? true :line 10 :column 1 :length 200
                                             :form "(fn setup-scene []\n  (local snap app.physics-containment-config)\n  (fn cleanup []\n    (set app.engine leaky)))"}
                                            {:kind :fn :name "cleanup" :top-level? false :line 12 :column 3 :length 60
                                             :form "(fn cleanup []\n    (set app.engine leaky))"}]
                              :mutations [{:op :set :path ["app" "engine"] :line 13 :column 5
                                           :form "(set app.engine leaky)" :enclosing-fn "cleanup"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "C2: cleanup mutates unrelated var should flag")
  (assert (> (length result) 0) "C2: should have at least one diagnostic"))

;; C3: parent snapshot after child definition → still flags
(fn mutation-restoration-flags-parent-snapshot-after-child []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl" :module "tests.test-module"
                              :definitions [{:kind :fn :name "setup-scene" :top-level? true :line 10 :column 1 :length 200
                                             :form "(fn setup-scene []\n  (fn cleanup []\n    (set app.physics-containment-config snap))\n  (local snap app.physics-containment-config))"}
                                            {:kind :fn :name "cleanup" :top-level? false :line 11 :column 3 :length 60
                                             :form "(fn cleanup []\n    (set app.physics-containment-config snap))"}]
                              :mutations [{:op :set :path ["app" "physics-containment-config"] :line 12 :column 5
                                           :form "(set app.physics-containment-config snap)" :enclosing-fn "cleanup"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "C3: parent snapshot after child should flag")
  (assert (> (length result) 0) "C3: should have at least one diagnostic"))

;; C4: wrong-path parent snapshot → still flags
(fn mutation-restoration-flags-parent-wrong-path-snapshot []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl" :module "tests.test-module"
                              :definitions [{:kind :fn :name "setup-scene" :top-level? true :line 10 :column 1 :length 200
                                             :form "(fn setup-scene []\n  (local snap app.engine)\n  (fn cleanup []\n    (set app.physics-containment-config new-config)))"}
                                            {:kind :fn :name "cleanup" :top-level? false :line 12 :column 3 :length 60
                                             :form "(fn cleanup []\n    (set app.physics-containment-config new-config))"}]
                              :mutations [{:op :set :path ["app" "physics-containment-config"] :line 13 :column 5
                                           :form "(set app.physics-containment-config new-config)" :enclosing-fn "cleanup"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "C4: wrong-path parent snapshot should flag")
  (assert (> (length result) 0) "C4: should have at least one diagnostic"))

;; C5: child assigns nil (not a restore) → still flags
(fn mutation-restoration-flags-cleanup-assigns-nil []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl" :module "tests.test-module"
                              :definitions [{:kind :fn :name "setup-scene" :top-level? true :line 10 :column 1 :length 200
                                             :form "(fn setup-scene []\n  (local snap app.physics-containment-config)\n  (fn cleanup []\n    (set app.physics-containment-config nil)))"}
                                            {:kind :fn :name "cleanup" :top-level? false :line 12 :column 3 :length 60
                                             :form "(fn cleanup []\n    (set app.physics-containment-config nil))"}]
                              :mutations [{:op :set :path ["app" "physics-containment-config"] :line 13 :column 5
                                           :form "(set app.physics-containment-config nil)" :enclosing-fn "cleanup"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "C5: cleanup assigns nil should flag")
  (assert (> (length result) 0) "C5: should have at least one diagnostic"))

;; C6: no parent snapshot → still flags
(fn mutation-restoration-flags-cleanup-no-parent-snapshot []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl" :module "tests.test-module"
                              :definitions [{:kind :fn :name "setup-scene" :top-level? true :line 10 :column 1 :length 200
                                             :form "(fn setup-scene []\n  (fn cleanup []\n    (set app.physics-containment-config new-config)))"}
                                            {:kind :fn :name "cleanup" :top-level? false :line 11 :column 3 :length 60
                                             :form "(fn cleanup []\n    (set app.physics-containment-config new-config))"}]
                              :mutations [{:op :set :path ["app" "physics-containment-config"] :line 12 :column 5
                                           :form "(set app.physics-containment-config new-config)" :enclosing-fn "cleanup"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "C6: no parent snapshot should flag")
  (assert (> (length result) 0) "C6: should have at least one diagnostic"))

;; C7: child assigns different value (not the snapshot var) → still flags
(fn mutation-restoration-flags-cleanup-assigns-other-var []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl" :module "tests.test-module"
                              :definitions [{:kind :fn :name "setup-scene" :top-level? true :line 10 :column 1 :length 200
                                             :form "(fn setup-scene []\n  (local snap app.physics-containment-config)\n  (fn cleanup []\n    (set app.physics-containment-config other-var)))"}
                                            {:kind :fn :name "cleanup" :top-level? false :line 12 :column 3 :length 60
                                             :form "(fn cleanup []\n    (set app.physics-containment-config other-var))"}]
                              :mutations [{:op :set :path ["app" "physics-containment-config"] :line 13 :column 5
                                           :form "(set app.physics-containment-config other-var)" :enclosing-fn "cleanup"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "C7: cleanup assigns other var should flag")
  (assert (> (length result) 0) "C7: should have at least one diagnostic"))

;; C8: tset restore also supported
(fn mutation-restoration-allows-child-tset-restoring-parent-snapshot []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl" :module "tests.test-module"
                              :definitions [{:kind :fn :name "setup-scene" :top-level? true :line 10 :column 1 :length 200
                                             :form "(fn setup-scene []\n  (local snap app.engine)\n  (fn cleanup []\n    (tset app :engine snap)))"}
                                            {:kind :fn :name "cleanup" :top-level? false :line 12 :column 3 :length 60
                                             :form "(fn cleanup []\n    (tset app :engine snap))"}]
                              :mutations [{:op :tset :path ["app" "engine"] :line 13 :column 5
                                           :form "(tset app :engine snap)" :enclosing-fn "cleanup"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil)
          "C8: child tset restoring parent snapshot should pass"))

;; Register all tests
(table.insert tests {:name "C1 allows child cleanup restoring parent snapshot" :fn mutation-restoration-allows-child-cleanup-restoring-parent-snapshot})
(table.insert tests {:name "C2 flags cleanup unrelated mutation" :fn mutation-restoration-flags-cleanup-unrelated-mutation})
(table.insert tests {:name "C3 flags parent snapshot after child" :fn mutation-restoration-flags-parent-snapshot-after-child})
(table.insert tests {:name "C4 flags parent wrong-path snapshot" :fn mutation-restoration-flags-parent-wrong-path-snapshot})
(table.insert tests {:name "C5 flags cleanup assigns nil" :fn mutation-restoration-flags-cleanup-assigns-nil})
(table.insert tests {:name "C6 flags cleanup no parent snapshot" :fn mutation-restoration-flags-cleanup-no-parent-snapshot})
(table.insert tests {:name "C7 flags cleanup assigns other var" :fn mutation-restoration-flags-cleanup-assigns-other-var})
(table.insert tests {:name "C8 allows child tset restoring parent snapshot" :fn mutation-restoration-allows-child-tset-restoring-parent-snapshot})

;; R1-1 (C9): snapshot inside earlier sibling nested fn must not count
(fn mutation-restoration-flags-sibling-scope-snapshot []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl" :module "tests.test-module"
                              :definitions [{:kind :fn :name "setup-scene" :top-level? true :line 10 :column 1 :length 250
                                             :form "(fn setup-scene []\n  (fn other []\n    (local snap app.engine))\n  (fn cleanup []\n    (set app.engine snap)))"}
                                            {:kind :fn :name "other" :top-level? false :line 11 :column 3 :length 60
                                             :form "(fn other []\n    (local snap app.engine))"}
                                            {:kind :fn :name "cleanup" :top-level? false :line 13 :column 3 :length 60
                                             :form "(fn cleanup []\n    (set app.engine snap))"}]
                              :mutations [{:op :set :path ["app" "engine"] :line 14 :column 5
                                           :form "(set app.engine snap)" :enclosing-fn "cleanup"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "C9: sibling-scope snapshot should not suppress cleanup diagnostic")
  (assert (> (length result) 0) "C9: should have at least one diagnostic"))

;; R1-2 (C10): tset with wrong path — parent snapshots app.engine, child tsets app.renderers
(fn mutation-restoration-flags-tset-wrong-path []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl" :module "tests.test-module"
                              :definitions [{:kind :fn :name "setup-scene" :top-level? true :line 10 :column 1 :length 200
                                             :form "(fn setup-scene []\n  (local snap app.engine)\n  (fn cleanup []\n    (tset app :renderers snap)))"}
                                            {:kind :fn :name "cleanup" :top-level? false :line 12 :column 3 :length 60
                                             :form "(fn cleanup []\n    (tset app :renderers snap))"}]
                              :mutations [{:op :tset :path ["app" "renderers"] :line 13 :column 5
                                           :form "(tset app :renderers snap)" :enclosing-fn "cleanup"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "C10: tset with wrong path should flag")
  (assert (> (length result) 0) "C10: should have at least one diagnostic"))

;; R1-2 (C11): tset with mismatched variable — parent snapshots app.engine, child tsets different var
(fn mutation-restoration-flags-tset-mismatched-var []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl" :module "tests.test-module"
                              :definitions [{:kind :fn :name "setup-scene" :top-level? true :line 10 :column 1 :length 200
                                             :form "(fn setup-scene []\n  (local snap app.engine)\n  (fn cleanup []\n    (tset app :engine other-var)))"}
                                            {:kind :fn :name "cleanup" :top-level? false :line 12 :column 3 :length 60
                                             :form "(fn cleanup []\n    (tset app :engine other-var))"}]
                              :mutations [{:op :tset :path ["app" "engine"] :line 13 :column 5
                                           :form "(tset app :engine other-var)" :enclosing-fn "cleanup"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "C11: tset with mismatched var should flag")
  (assert (> (length result) 0) "C11: should have at least one diagnostic"))

;; R1-1 lambda: sibling lambda snapshot must not count as parent-scope
(fn mutation-restoration-flags-sibling-lambda-snapshot []
  (local rule (get-test-isolation-rule))
  (local ff (make-file-fact {:path "/tests/test-module.fnl" :module "tests.test-module"
                              :definitions [{:kind :fn :name "setup-scene" :top-level? true :line 10 :column 1 :length 250
                                             :form "(fn setup-scene []\n  (local other (lambda []\n    (local snap app.engine)))\n  (fn cleanup []\n    (set app.engine snap)))"}
                                            {:kind :fn :name "cleanup" :top-level? false :line 13 :column 3 :length 60
                                             :form "(fn cleanup []\n    (set app.engine snap))"}]
                              :mutations [{:op :set :path ["app" "engine"] :line 14 :column 5
                                           :form "(set app.engine snap)" :enclosing-fn "cleanup"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "C12: sibling lambda snapshot should not suppress cleanup diagnostic")
  (assert (> (length result) 0) "C12: should have at least one diagnostic"))

(table.insert tests {:name "C9 flags sibling-scope snapshot" :fn mutation-restoration-flags-sibling-scope-snapshot})
(table.insert tests {:name "C10 flags tset wrong path" :fn mutation-restoration-flags-tset-wrong-path})
(table.insert tests {:name "C11 flags tset mismatched var" :fn mutation-restoration-flags-tset-mismatched-var})
(table.insert tests {:name "C12 flags sibling lambda snapshot" :fn mutation-restoration-flags-sibling-lambda-snapshot})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-rules-test-isolation-cleanup" :tests tests})))

{:tests tests :main main}
