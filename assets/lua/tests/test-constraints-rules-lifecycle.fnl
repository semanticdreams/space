;; Tests for Lifecycle constraint rules.
;; Follows TDD: these tests must FAIL before lifecycle.fnl is implemented.

(local tests [])

;; --- Helpers for constructing synthetic fact DBs ---

(fn make-file-fact [opts]
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
    (when (= r.id id)
      (set found r)))
  found)

(fn get-lifecycle-rule [id]
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules id))
  (assert rule (.. "rule " id " should be in rules list"))
  rule)

;; Sensitive globals as defined by the lifecycle/test-isolation spec.
(local sensitive-globals
  ["app.renderers" "app.lights" "app.engine"
   "app.activity-registry" "app.physics-containment-config" "package.loaded"])

;; ======================================================================
;; lifecycle.event-registration-cleanup
;; ======================================================================

(fn registration-cleanup-allows-file-without-registrations []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/clean-module.fnl" :module "clean-module"
                              :calls [{:callee "print" :receiver nil :method nil
                                       :line 1 :column 1 :form "(print :hello)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file without registrations should pass"))

(fn registration-cleanup-allows-file-with-registration-and-cleanup []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :calls [{:callee "some-obj:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(some-obj:connect handler)"}
                                      {:callee "some-obj:disconnect" :receiver nil :method nil
                                       :line 20 :column 1 :form "(some-obj:disconnect handler)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with registration and cleanup should pass"))

(fn registration-cleanup-allows-register-with-unregister []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :calls [{:callee "register" :receiver nil :method nil
                                       :line 10 :column 1 :form "(register event-handler)"}
                                      {:callee "unregister" :receiver nil :method nil
                                       :line 20 :column 1 :form "(unregister event-handler)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with register and unregister should pass"))

(fn registration-cleanup-allows-connect-with-drop-cleanup []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :calls [{:callee "some-obj:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(some-obj:connect handler)"}
                                      {:callee "some-obj:drop" :receiver nil :method nil
                                       :line 25 :column 1 :form "(some-obj:drop)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with connect and :drop cleanup should pass"))

(fn registration-cleanup-flags-file-with-connect-no-cleanup []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :calls [{:callee "event-system:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(event-system:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup") "diagnostic should have correct constraint-id")
  (assert (= d.family "lifecycle") "diagnostic should have family lifecycle")
  (assert (= d.file ff.path) "diagnostic should include file path")
  (assert d.evidence "diagnostic should include evidence")
  (assert (= d.evidence.registration-count 1) "evidence should report registration count")
  (assert (> (length d.evidence.registration-forms) 0) "evidence should include registration forms"))

(fn registration-cleanup-flags-app-engine-events-updated-connect []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :calls [{:callee "app.engine.events.updated:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(app.engine.events.updated:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for app.engine.events.updated:connect")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup") "diagnostic should have correct constraint-id")
  (assert d.evidence "diagnostic should include evidence")
  (assert (> (length d.evidence.registration-forms) 0) "evidence should include registration forms")
  (assert (= d.evidence.registration-count 1) "evidence should report registration count"))

(fn registration-cleanup-flags-register-without-unregister []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :calls [{:callee "register" :receiver nil :method nil
                                       :line 10 :column 1 :form "(register event-handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for register without unregister")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup") "diagnostic should have correct constraint-id"))

(fn registration-cleanup-allows-connect-with-clear-cleanup []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :calls [{:callee "some-obj:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(some-obj:connect handler)"}
                                      {:callee "clear" :receiver nil :method nil
                                       :line 25 :column 1 :form "(clear handlers)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with connect and clear cleanup should pass"))

(fn registration-cleanup-allows-function-named-cleanup []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :definitions [{:kind :fn :name "cleanup" :top-level? true
                                             :line 30 :column 1 :length 10
                                             :form "(fn cleanup [] (some-obj:disconnect handler))"}]
                              :calls [{:callee "some-obj:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(some-obj:connect handler)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with function named cleanup should pass"))

(fn registration-cleanup-allows-function-named-teardown []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :definitions [{:kind :fn :name "teardown" :top-level? true
                                             :line 30 :column 1 :length 10
                                             :form "(fn teardown [] (disconnect handler))"}]
                              :calls [{:callee "some-obj:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(some-obj:connect handler)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with function named teardown should pass"))

(fn registration-cleanup-allows-function-named-shutdown []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :definitions [{:kind :fn :name "shutdown" :top-level? true
                                             :line 30 :column 1 :length 10
                                             :form "(fn shutdown [] (some-obj:disconnect handler))"}]
                              :calls [{:callee "some-obj:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(some-obj:connect handler)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with function named shutdown should pass"))

(fn registration-cleanup-allows-connect-with-clear-method []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :calls [{:callee "some-signal:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(some-signal:connect handler)"}
                                      {:callee "some-signal:clear" :receiver nil :method nil
                                       :line 25 :column 1 :form "(some-signal:clear)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with connect and :clear method should pass"))

(fn registration-cleanup-allows-connect-with-unregister-method []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :calls [{:callee "registry:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(registry:connect handler)"}
                                      {:callee "registry:unregister" :receiver nil :method nil
                                       :line 25 :column 1 :form "(registry:unregister handler)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with connect and :unregister method should pass"))

(fn registration-cleanup-allows-function-named-unload []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :definitions [{:kind :fn :name "unload" :top-level? true
                                             :line 30 :column 1 :length 10
                                             :form "(fn unload [] (some-obj:disconnect handler))"}]
                              :calls [{:callee "some-obj:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(some-obj:connect handler)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with function named unload should pass"))

;; --- Precision: disconnect-* helper calls and functions ---

(fn registration-cleanup-allows-disconnect-dash-helper-call []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :calls [{:callee "some-obj:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(some-obj:connect handler)"}
                                      {:callee "disconnect-input" :receiver nil :method nil
                                       :line 25 :column 1 :form "(disconnect-input)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with disconnect-* helper call should pass"))

(fn registration-cleanup-allows-disconnect-dash-function-name []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :definitions [{:kind :fn :name "disconnect-update" :top-level? true
                                             :line 30 :column 1 :length 10
                                             :form "(fn disconnect-update [] (some-obj:disconnect handler))"}]
                              :calls [{:callee "some-obj:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(some-obj:connect handler)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with function named disconnect-* should pass"))

;; --- R1-3: handler-record cleanup loops ---

(fn registration-cleanup-allows-loop-cleanup-over-handler-records []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :definitions [{:kind :fn :name "cleanup-handlers" :top-level? true
                                             :line 30 :column 1 :length 20
                                             :form "(fn cleanup-handlers []
  (each [_ record (ipairs handlers)]
    (record.signal:disconnect record.handler true)))"}]
                              :calls [{:callee "signal-a:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(signal-a:connect handler1)"}
                                      {:callee "signal-b:connect" :receiver nil :method nil
                                       :line 12 :column 1 :form "(signal-b:connect handler2)"}
                                      {:callee "signal-c:connect" :receiver nil :method nil
                                       :line 14 :column 1 :form "(signal-c:connect handler3)"}
                                      {:callee "record.signal:disconnect" :receiver nil :method nil
                                       :line 32 :column 1 :form "(record.signal:disconnect record.handler true)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "loop cleanup over handler records should pass"))

(fn registration-cleanup-allows-loop-cleanup-in-drop-function []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :definitions [{:kind :fn :name "drop" :top-level? true
                                             :line 30 :column 1 :length 20
                                             :form "(fn drop []
  (each [_ record (ipairs view.handlers)]
    (record.signal:disconnect record.handler true)))"}]
                              :calls [{:callee "signal-a:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(signal-a:connect handler1)"}
                                      {:callee "signal-b:connect" :receiver nil :method nil
                                       :line 12 :column 1 :form "(signal-b:connect handler2)"}
                                      {:callee "record.signal:disconnect" :receiver nil :method nil
                                       :line 32 :column 1 :form "(record.signal:disconnect record.handler true)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "drop function with loop cleanup should pass"))

(fn registration-cleanup-still-flags-no-cleanup-at-all []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :definitions [{:kind :fn :name "do-stuff" :top-level? true
                                             :line 30 :column 1 :length 10
                                             :form "(fn do-stuff []
  (each [_ x (ipairs items)]
    (print x)))"}]
                              :calls [{:callee "signal-a:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(signal-a:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should still flag registrations with no cleanup calls at all")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup") "diagnostic should have correct constraint-id"))

(fn registration-cleanup-still-flags-connect-without-any-cleanup []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :calls [{:callee "event-system:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(event-system:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for connect without cleanup")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup") "diagnostic should have correct constraint-id"))

;; --- R2-2: helper loops should be recognized ---

(fn registration-cleanup-allows-loop-with-disconnect-dash-helper []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :definitions [{:kind :fn :name "cleanup-handlers" :top-level? true
                                             :line 30 :column 1 :length 20
                                             :form "(fn cleanup-handlers []
  (each [_ record (ipairs handlers)]
    (disconnect-input record)))"}]
                              :calls [{:callee "signal-a:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(signal-a:connect handler1)"}
                                      {:callee "signal-b:connect" :receiver nil :method nil
                                       :line 12 :column 1 :form "(signal-b:connect handler2)"}
                                      {:callee "disconnect-input" :receiver nil :method nil
                                       :line 32 :column 1 :form "(disconnect-input record)"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "loop with disconnect-* helper call should pass"))

(fn registration-cleanup-flags-file-with-loop-but-no-cleanup-calls []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :definitions [{:kind :fn :name "log-loop" :top-level? true
                                             :line 30 :column 1 :length 10
                                             :form "(fn log-loop []
  (each [_ x (ipairs items)]
    (print \"use :disconnect to clean up\")))"}]
                              :calls [{:callee "signal-a:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(signal-a:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag no-cleanup when loop has :disconnect text but no cleanup calls")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup") "diagnostic should have correct constraint-id"))

;; --- R3-1: partial cleanup + cleanup-like loop text must still flag ---

(fn registration-cleanup-flags-partial-cleanup-with-fake-loop-text []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :definitions [{:kind :fn :name "log-reminder" :top-level? true
                                             :line 30 :column 1 :length 20
                                             :form "(fn log-reminder []
  (each [_ x (ipairs items)]
    (print \"(some-obj:disconnect handler1)\")))"}]
                              :calls [{:callee "signal-a:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(signal-a:connect handler1)"}
                                      {:callee "signal-b:connect" :receiver nil :method nil
                                       :line 12 :column 1 :form "(signal-b:connect handler2)"}
                                      {:callee "some-obj:disconnect" :receiver nil :method nil
                                       :line 20 :column 1 :form "(some-obj:disconnect handler1)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag insufficient cleanup — loop has no real cleanup call")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup") "diagnostic should have correct constraint-id"))

;; --- R5-1: same-function cleanup call outside loop must still flag ---

(fn registration-cleanup-flags-cleanup-outside-loop-with-fake-text-inside []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :definitions [{:kind :fn :name "process-handlers" :top-level? true
                                             :line 10 :column 1 :length 20
                                             :form "(fn process-handlers []
  (some-obj:disconnect handler1)
  (each [_ x (ipairs items)]
    (print \"(some-obj:disconnect handler1)\")))"}]
                              :calls [{:callee "signal-a:connect" :receiver nil :method nil
                                       :line 5 :column 1 :form "(signal-a:connect handler1)"}
                                      {:callee "signal-b:connect" :receiver nil :method nil
                                       :line 7 :column 1 :form "(signal-b:connect handler2)"}
                                      {:callee "some-obj:disconnect" :receiver nil :method nil
                                       :line 11 :column 1 :form "(some-obj:disconnect handler1)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag insufficient cleanup — cleanup call is outside loop body")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup") "diagnostic should have correct constraint-id"))

(fn registration-cleanup-flags-file-with-partial-cleanup []
  (local rule (get-lifecycle-rule "lifecycle.event-registration-cleanup"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :calls [{:callee "some-obj:connect" :receiver nil :method nil
                                       :line 10 :column 1 :form "(some-obj:connect handler1)"}
                                      {:callee "other-obj:connect" :receiver nil :method nil
                                       :line 12 :column 1 :form "(other-obj:connect handler2)"}
                                      {:callee "some-obj:disconnect" :receiver nil :method nil
                                       :line 20 :column 1 :form "(some-obj:disconnect handler1)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for unmatched registration")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup") "diagnostic should have correct constraint-id"))


;; ======================================================================
;; lifecycle.required-runtime-fails-loudly
;; ======================================================================

(fn required-runtime-allows-file-with-no-sensitive-accesses []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/clean-module.fnl" :module "clean-module"
                              :accesses [] :definitions []}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file without sensitive accesses should pass"))

(fn required-runtime-allows-file-with-assert-and-sensitive-access []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :accesses [{:path ["app" "engine"] :text "app.engine"
                                          :line 5 :column 1 :form "app.engine"}]
                              :definitions [{:kind :fn :name "do-work" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn do-work []
  (assert app.engine \"requires engine\"))"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with assert and sensitive access should pass"))

(fn required-runtime-allows-file-with-error-and-sensitive-access []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :accesses [{:path ["app" "renderers"] :text "app.renderers"
                                          :line 8 :column 1 :form "app.renderers"}]
                              :definitions [{:kind :fn :name "get-renderer" :top-level? true
                                             :line 5 :column 1 :length 120
                                             :form "(fn get-renderer []
  (when (not app.renderers)
    (error \"app.renderers is nil, required runtime not loaded\")))"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with error in same function should pass"))

(fn required-runtime-flags-file-with-or-synthesizing-sensitive-global []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :accesses [{:path ["app" "renderers"] :text "app.renderers"
                                          :line 5 :column 1 :form "app.renderers"}]
                              :definitions [{:kind :fn :name "get-renderer" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn get-renderer []
  (or app.renderers {}))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for or-pattern without assert")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.required-runtime-fails-loudly") "diagnostic should have correct constraint-id")
  (assert (= d.family "lifecycle") "diagnostic should have family lifecycle")
  (assert (= d.file ff.path) "diagnostic should include file path")
  (assert d.evidence "diagnostic should include evidence")
  (assert d.hint "diagnostic should include hint"))

(fn required-runtime-allows-when-conditional-execution []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :accesses [{:path ["app" "lights"] :text "app.lights"
                                          :line 5 :column 1 :form "app.lights"}]
                              :definitions [{:kind :fn :name "add-light" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn add-light [l]
  (when app.lights
    (tset app.lights :extra l)))"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "file with when-pattern should pass — when is guard, not synthesis"))

;; --- R1-1: if-based synthesis should still be caught ---

(fn required-runtime-flags-if-synthesizing-engine []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :accesses [{:path ["app" "engine"] :text "app.engine"
                                          :line 5 :column 1 :form "app.engine"}]
                              :definitions [{:kind :fn :name "get-engine" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn get-engine []
  (if app.engine
    app.engine
    (make-debug-engine)))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for if-synthesis pattern")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.required-runtime-fails-loudly") "diagnostic should have correct constraint-id"))

(fn required-runtime-flags-if-synthesizing-renderers []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :accesses [{:path ["app" "renderers"] :text "app.renderers"
                                          :line 5 :column 1 :form "app.renderers"}]
                              :definitions [{:kind :fn :name "get-renderers" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn get-renderers []
  (if app.renderers
    app.renderers
    {}))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for if-synthesis of renderers")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.required-runtime-fails-loudly") "diagnostic should have correct constraint-id"))

(fn required-runtime-allows-if-benign-branch []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :accesses [{:path ["app" "engine"] :text "app.engine"
                                          :line 5 :column 1 :form "app.engine"}]
                              :definitions [{:kind :fn :name "maybe-process" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn maybe-process []
  (if app.engine
    (process app.engine)
    (log-missing)))"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "benign if branch should not be flagged as synthesis"))

;; --- Precision: guard patterns should NOT be flagged ---

(fn required-runtime-allows-and-guard-pattern []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :accesses [{:path ["app" "engine"] :text "app.engine"
                                          :line 5 :column 1 :form "app.engine"}]
                              :definitions [{:kind :fn :name "get-frame-id" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn get-frame-id []
  (and app.engine app.engine.frame-id))"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "and guard pattern should not be flagged as synthesis"))

(fn required-runtime-allows-or-with-and-guard []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :accesses [{:path ["app" "engine"] :text "app.engine"
                                          :line 5 :column 1 :form "app.engine"}]
                              :definitions [{:kind :fn :name "get-frame-id" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn get-frame-id []
  (or (and app.engine app.engine.frame-id) 0))"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "or with and-guard should not be flagged as synthesis"))

;; --- Precision: subfield defaults should NOT be flagged ---

(fn required-runtime-allows-subfield-default []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :accesses [{:path ["app" "engine"] :text "app.engine"
                                          :line 5 :column 1 :form "app.engine"}]
                              :definitions [{:kind :fn :name "get-mouse-x" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn get-mouse-x []
  (or app.engine.input.mouse.x 0))"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "subfield default should not be flagged as synthesis"))

(fn required-runtime-allows-renderers-subfield-default []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :accesses [{:path ["app" "renderers"] :text "app.renderers"
                                          :line 5 :column 1 :form "app.renderers"}]
                              :definitions [{:kind :fn :name "get-layer" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn get-layer []
  (or app.renderers.render-layer 0))"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "renderers subfield default should not be flagged"))

;; --- R1-2: hyphenated sensitive globals must still be matched ---

(fn required-runtime-flags-activity-registry-synthesis []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :accesses [{:path ["app" "activity-registry"] :text "app.activity-registry"
                                          :line 5 :column 1 :form "app.activity-registry"}]
                              :definitions [{:kind :fn :name "get-registry" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn get-registry []
  (or app.activity-registry {}))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for hyphenated global synthesis")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.required-runtime-fails-loudly") "diagnostic should have correct constraint-id"))

(fn required-runtime-flags-physics-containment-config-synthesis []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :accesses [{:path ["app" "physics-containment-config"] :text "app.physics-containment-config"
                                          :line 5 :column 1 :form "app.physics-containment-config"}]
                              :definitions [{:kind :fn :name "get-config" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn get-config []
  (or app.physics-containment-config {}))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for multi-hyphen global synthesis")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.required-runtime-fails-loudly") "diagnostic should have correct constraint-id"))

(fn required-runtime-allows-hyphenated-subfield-default []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/good-module.fnl" :module "good-module"
                              :accesses [{:path ["app" "activity-registry"] :text "app.activity-registry"
                                          :line 5 :column 1 :form "app.activity-registry"}]
                              :definitions [{:kind :fn :name "get-entry" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn get-entry []
  (or app.activity-registry.default-entry {}))"}]}))
  (assert (= (rule.run (make-ctx [ff])) nil) "hyphenated subfield default should not be flagged"))

;; --- Precision: genuine or-synthesis should still be flagged ---

(fn required-runtime-flags-file-with-set-or-synthesizing-global []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :accesses [{:path ["app" "engine"] :text "app.engine"
                                          :line 5 :column 1 :form "app.engine"}]
                              :definitions [{:kind :fn :name "ensure-engine" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn ensure-engine []
  (set app.engine (or app.engine {})))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for set+or synthesis pattern")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.required-runtime-fails-loudly") "diagnostic should have correct constraint-id"))

(fn required-runtime-flags-file-with-or-synthesizing-engine []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/bad-module.fnl" :module "bad-module"
                              :accesses [{:path ["app" "engine"] :text "app.engine"
                                          :line 5 :column 1 :form "app.engine"}]
                              :definitions [{:kind :fn :name "get-engine" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn get-engine []
  (or app.engine {}))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for or-synthesis of app.engine")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.required-runtime-fails-loudly") "diagnostic should have correct constraint-id"))

(fn required-runtime-allows-file-with-assert-in-outer-fn []
  (local rule (get-lifecycle-rule "lifecycle.required-runtime-fails-loudly"))
  (local ff (make-file-fact {:path "/src/mixed-module.fnl" :module "mixed-module"
                              :accesses [{:path ["app" "renderers"] :text "app.renderers"
                                          :line 5 :column 1 :form "app.renderers"}]
                              :definitions [{:kind :fn :name "get-renderers" :top-level? true
                                             :line 3 :column 1 :length 100
                                             :form "(fn get-renderers []
  (or app.renderers {}))"}
                                            {:kind :fn :name "assert-renderers" :top-level? true
                                             :line 10 :column 1 :length 80
                                             :form "(fn assert-renderers []
  (assert app.renderers \"no renderers\"))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for or-pattern function")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (var found-or-diag false)
  (each [_ d (ipairs result)]
    (when (and (= d.constraint-id "lifecycle.required-runtime-fails-loudly")
               (. d.evidence :function-name)
               (= d.evidence.function-name "get-renderers"))
      (set found-or-diag true)))
  (assert found-or-diag "should flag the function with or-pattern"))


;; ======================================================================
;; Rules list structure tests
;; ======================================================================

(fn lifecycle-rules-returns-table-with-two-rules []
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (assert (= (type rules) :table) "rules should be a table")
  (assert (= (length rules) 2) (.. "expected 2 rules, got " (length rules))))

(fn lifecycle-rules-have-required-structure []
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (each [_ rule (ipairs rules)]
    (assert (= (type rule.id) :string) (.. "rule should have string :id, got " (tostring rule.id)))
    (assert (= rule.family "lifecycle") "rule should have family lifecycle")
    (assert (= (type rule.targets) :table) "rule should have :targets table")
    (assert (= rule.kind :static) (.. "rule should be kind static, got " (tostring rule.kind)))
    (assert (= (type rule.run) :function) (.. "rule should have :run function for id " (tostring rule.id)))
    (assert (= (type rule.fn) :function) (.. "rule should have :fn function for id " (tostring rule.id)))
    (assert (= rule.fn rule.run) (.. ":fn should alias :run for id " (tostring rule.id)))))

;; ======================================================================
;; Runner integration test
;; ======================================================================

(fn lifecycle-runner-executable []
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local ConstraintRunner (require :constraints.runner))
  (local rules (Lifecycle.rules))
  (local target {:kind :repo :name :test
                 :facts (make-fact-db [(make-file-fact {:path "/test/clean.fnl" :module "test-clean"
                                                         :accesses [] :calls [] :definitions []})])
                 :files []})
  (local result (ConstraintRunner.run {:rules rules :target target :baseline-data false}))
  (assert result "runner should return a result table")
  (assert (= (type result.status) :string) "result should have a status")
  (assert (= result.status :pass) (.. "expected :pass status, got " result.status))
  (assert (= (length result.diagnostics) 0)
          (.. "expected 0 diagnostics, got " (length result.diagnostics))))

;; ======================================================================
;; Register all tests
;; ======================================================================

(table.insert tests {:name "registration-cleanup allows file without registrations" :fn registration-cleanup-allows-file-without-registrations})
(table.insert tests {:name "registration-cleanup allows file with registration and cleanup" :fn registration-cleanup-allows-file-with-registration-and-cleanup})
(table.insert tests {:name "registration-cleanup allows register with unregister" :fn registration-cleanup-allows-register-with-unregister})
(table.insert tests {:name "registration-cleanup allows connect with drop cleanup" :fn registration-cleanup-allows-connect-with-drop-cleanup})
(table.insert tests {:name "registration-cleanup flags file with connect no cleanup" :fn registration-cleanup-flags-file-with-connect-no-cleanup})
(table.insert tests {:name "registration-cleanup flags app.engine.events.updated:connect" :fn registration-cleanup-flags-app-engine-events-updated-connect})
(table.insert tests {:name "registration-cleanup flags register without unregister" :fn registration-cleanup-flags-register-without-unregister})
(table.insert tests {:name "registration-cleanup allows connect with clear cleanup" :fn registration-cleanup-allows-connect-with-clear-cleanup})
(table.insert tests {:name "registration-cleanup allows function named cleanup" :fn registration-cleanup-allows-function-named-cleanup})
(table.insert tests {:name "registration-cleanup allows function named teardown" :fn registration-cleanup-allows-function-named-teardown})
(table.insert tests {:name "registration-cleanup allows function named shutdown" :fn registration-cleanup-allows-function-named-shutdown})
(table.insert tests {:name "registration-cleanup allows connect with clear method" :fn registration-cleanup-allows-connect-with-clear-method})
(table.insert tests {:name "registration-cleanup allows connect with unregister method" :fn registration-cleanup-allows-connect-with-unregister-method})
(table.insert tests {:name "registration-cleanup allows function named unload" :fn registration-cleanup-allows-function-named-unload})
(table.insert tests {:name "registration-cleanup allows disconnect-dash helper call" :fn registration-cleanup-allows-disconnect-dash-helper-call})
(table.insert tests {:name "registration-cleanup allows disconnect-dash function name" :fn registration-cleanup-allows-disconnect-dash-function-name})
(table.insert tests {:name "registration-cleanup allows loop cleanup over handler records" :fn registration-cleanup-allows-loop-cleanup-over-handler-records})
(table.insert tests {:name "registration-cleanup allows loop cleanup in drop function" :fn registration-cleanup-allows-loop-cleanup-in-drop-function})
(table.insert tests {:name "registration-cleanup still flags no cleanup at all" :fn registration-cleanup-still-flags-no-cleanup-at-all})
(table.insert tests {:name "registration-cleanup still flags connect without any cleanup" :fn registration-cleanup-still-flags-connect-without-any-cleanup})
(table.insert tests {:name "registration-cleanup allows loop with disconnect-dash helper" :fn registration-cleanup-allows-loop-with-disconnect-dash-helper})
(table.insert tests {:name "registration-cleanup flags loop but no cleanup calls" :fn registration-cleanup-flags-file-with-loop-but-no-cleanup-calls})
(table.insert tests {:name "registration-cleanup flags partial cleanup with fake loop text" :fn registration-cleanup-flags-partial-cleanup-with-fake-loop-text})
(table.insert tests {:name "registration-cleanup flags cleanup outside loop with fake text inside" :fn registration-cleanup-flags-cleanup-outside-loop-with-fake-text-inside})
(table.insert tests {:name "registration-cleanup flags file with partial cleanup" :fn registration-cleanup-flags-file-with-partial-cleanup})

(table.insert tests {:name "required-runtime allows file with no sensitive accesses" :fn required-runtime-allows-file-with-no-sensitive-accesses})
(table.insert tests {:name "required-runtime allows file with assert and sensitive access" :fn required-runtime-allows-file-with-assert-and-sensitive-access})
(table.insert tests {:name "required-runtime allows file with error and sensitive access" :fn required-runtime-allows-file-with-error-and-sensitive-access})
(table.insert tests {:name "required-runtime flags file with or synthesizing sensitive global" :fn required-runtime-flags-file-with-or-synthesizing-sensitive-global})
(table.insert tests {:name "required-runtime allows when conditional execution" :fn required-runtime-allows-when-conditional-execution})
(table.insert tests {:name "required-runtime flags if synthesizing engine" :fn required-runtime-flags-if-synthesizing-engine})
(table.insert tests {:name "required-runtime flags if synthesizing renderers" :fn required-runtime-flags-if-synthesizing-renderers})
(table.insert tests {:name "required-runtime allows if benign branch" :fn required-runtime-allows-if-benign-branch})
(table.insert tests {:name "required-runtime allows and guard pattern" :fn required-runtime-allows-and-guard-pattern})
(table.insert tests {:name "required-runtime allows or with and guard" :fn required-runtime-allows-or-with-and-guard})
(table.insert tests {:name "required-runtime allows subfield default" :fn required-runtime-allows-subfield-default})
(table.insert tests {:name "required-runtime allows renderers subfield default" :fn required-runtime-allows-renderers-subfield-default})
(table.insert tests {:name "required-runtime flags activity-registry synthesis" :fn required-runtime-flags-activity-registry-synthesis})
(table.insert tests {:name "required-runtime flags physics-containment-config synthesis" :fn required-runtime-flags-physics-containment-config-synthesis})
(table.insert tests {:name "required-runtime allows hyphenated subfield default" :fn required-runtime-allows-hyphenated-subfield-default})
(table.insert tests {:name "required-runtime flags set+or synthesizing global" :fn required-runtime-flags-file-with-set-or-synthesizing-global})
(table.insert tests {:name "required-runtime flags or synthesizing engine" :fn required-runtime-flags-file-with-or-synthesizing-engine})
(table.insert tests {:name "required-runtime only checks per-function, not file-level" :fn required-runtime-allows-file-with-assert-in-outer-fn})

(table.insert tests {:name "lifecycle rules returns table with two rules" :fn lifecycle-rules-returns-table-with-two-rules})
(table.insert tests {:name "lifecycle rules have required structure" :fn lifecycle-rules-have-required-structure})
(table.insert tests {:name "lifecycle rules executable by runner" :fn lifecycle-runner-executable})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-rules-lifecycle" :tests tests})))

{:name "constraints-rules-lifecycle" :tests tests :main main}
