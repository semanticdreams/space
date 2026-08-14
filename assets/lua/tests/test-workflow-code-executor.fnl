(local Outcomes (require :workflows/outcomes))
(local {: WorkflowCodeExecutor} (require :workflows/code-executor))

(local tests [])

(fn assert-failed-message [outcome needle]
  (assert (= outcome.status :failed) "outcome should fail")
  (assert outcome.error "failed outcome should include error")
  (assert outcome.error.message "failed outcome should include error message")
  (assert (string.find outcome.error.message needle 1 true)
          (.. "expected error message to include " needle ", got " outcome.error.message)))

(fn assert-failed-kind [outcome expected-kind]
  (assert (= outcome.status :failed) "outcome should fail")
  (assert outcome.error "failed outcome should include error")
  (assert outcome.error.data "failed outcome should include structured data")
  (assert (= outcome.error.data.kind expected-kind)
          (.. "expected error kind " (tostring expected-kind) ", got " (tostring outcome.error.data.kind))))

(fn make-code-store [entities]
  {:get-entity (fn [_self id]
                 (. entities id))})

(fn make-executor [entities]
  (WorkflowCodeExecutor {:code-store (make-code-store entities)
                         :app app}))

(fn outcome-helpers-return-strict-tables []
  (local ctx (Outcomes.make-context {:run-id "run-1" :step-id "step-1"}))
  (local succeeded (ctx:succeed {:answer 42} {:next-step-ids ["step-2"]}))
  (assert (= succeeded.status :succeeded) "succeed helper should set succeeded status")
  (assert (= succeeded.output.answer 42) "succeed helper should preserve output")
  (assert (= (. succeeded.next-step-ids 1) "step-2") "succeed helper should preserve next steps")
  (local failed (ctx:fail "boom" {:kind :test}))
  (local waiting (ctx:wait :human {:prompt "ok"} {:cursor 1}))
  (local retrying (ctx:retry 250 {:attempt 1}))
  (local cancelled (ctx:cancelled {:partial true}))
  (local skipped (ctx:skip "not needed"))
  (assert (= failed.error.message "boom") "fail helper should set message")
  (assert (= waiting.status :waiting) "wait helper should return waiting")
  (assert (= retrying.delay-ms 250) "retry helper should return delay")
  (assert (= cancelled.status :cancelled) "cancelled helper should return cancelled")
  (assert (= skipped.reason "not needed") "skip helper should return reason"))

(fn invalid-outcomes-fail-loudly []
  (local ctx (Outcomes.make-context {:run-id "run-2" :step-id "step-2"}))
  (local (nil-ok nil-err) (pcall Outcomes.validate-outcome nil ctx))
  (assert (not nil-ok) "nil outcome should raise")
  (assert (string.find nil-err "run-2" 1 true) "nil outcome error should include run id")
  (assert (string.find nil-err "step-2" 1 true) "nil outcome error should include step id")
  (local invalids [{:status :unknown}
                   {:status :failed :error {}}
                    {:status :waiting}
                    {:status :retry :delay-ms -1}
                    {:status :succeeded :next-step-ids ["ok" 3]}
                    {:status :succeeded :next-step-ids {:bad 3}}
                    {:status :cancelled :next-step-ids ["not-allowed"]}])
  (each [_ outcome (ipairs invalids)]
    (local (ok err) (pcall Outcomes.validate-outcome outcome ctx))
    (assert (not ok) "invalid outcome should raise")
    (assert (string.find err "run-2" 1 true) "validation error should include run id")
    (assert (string.find err "step-2" 1 true) "validation error should include step id"))
  (each [_ status (ipairs [:succeeded :failed :waiting :retry :cancelled :skipped])]
    (local outcome
      (if (= status :failed)
          {:status status :error {:message "expected"}}
          (= status :waiting)
          {:status status :wait-kind :human}
          (= status :retry)
          {:status status :delay-ms 0}
          (= status :skipped)
          {:status status :reason "expected" :next-step-ids ["step-3"]}
          {:status status}))
     (local normalized (Outcomes.validate-outcome outcome ctx))
     (assert (= normalized.status status) "allowed status should validate")))

(fn sparse-next-step-ids-fail-loudly []
  (local ctx (Outcomes.make-context {:run-id "run-sparse" :step-id "step-sparse"}))
  (local sparse [])
  (tset sparse 2 3)
  (local (ok err) (pcall Outcomes.validate-outcome {:status :skipped :next-step-ids sparse} ctx))
  (assert (not ok) "sparse non-string next-step-ids should raise")
  (assert (string.find err "next-step-ids" 1 true) "sparse error should describe next-step-ids"))

(fn executor-evaluates-code-entity-factory-with-full-app-access []
  (set app.workflow_executor_test_value "global-visible")
  (local definition {:id "def-1"})
  (local step {:id "step-1" :code-entity-id "code-1" :config {:configured true}})
  (local source "(fn [opts] {:run (fn [self ctx input state] (ctx:succeed {:value _G.app.workflow_executor_test_value :configured opts.configured :input input.payload :state state.saved}))})")
  (local executor (make-executor {"code-1" {:id "code-1" :language "fnl" :source source}
                                  "code-2" {:id "code-2" :language "fennel" :source "{:run (fn [self ctx input state] (ctx:succeed {:direct true}))}"}}))
  (local outcome (executor:run-step definition step {:payload "in"} {:saved "state"}))
  (assert (= outcome.status :succeeded) "factory run should succeed")
  (assert (= outcome.output.value "global-visible") "workflow code should read global app")
  (assert (= outcome.output.configured true) "factory should receive step config")
  (assert (= outcome.output.input "in") "run should receive input")
  (assert (= outcome.output.state "state") "run should receive state")
  (local direct-outcome (executor:run-step definition {:id "step-2" :code-entity-id "code-2"} {} {}))
  (assert (= direct-outcome.status :succeeded) "direct step object should succeed")
  (assert (= direct-outcome.output.direct true) "direct step object should be accepted"))

(fn executor-rejects-missing-code-entity []
  (local executor (make-executor {"lua-code" {:id "lua-code" :language "lua" :source "return {}"}}))
  (local missing (executor:run-step {:id "def-1"} {:id "step-1" :code-entity-id "missing"} {} {}))
  (assert-failed-message missing "missing code entity")
  (assert-failed-kind missing :missing-code-entity)
  (local unsupported (executor:run-step {:id "def-1"} {:id "step-2" :code-entity-id "lua-code"} {} {}))
  (assert-failed-message unsupported "unsupported code entity language")
  (assert-failed-kind unsupported :unsupported-language))

(fn executor-returns-structured-step-object-errors []
  (local executor (make-executor {"bad-eval" {:id "bad-eval" :language "fnl" :source "("}
                                  "bad-factory-return" {:id "bad-factory-return" :language "fnl" :source "(fn [opts] 3)"}
                                  "factory-error" {:id "factory-error" :language "fnl" :source "(fn [opts] (error {:reason :factory-boom}))"}}))
  (assert-failed-kind (executor:run-step {:id "def-1"} {:id "step-3" :code-entity-id "bad-eval"} {} {}) :evaluation-failed)
  (assert-failed-kind (executor:run-step {:id "def-1"} {:id "step-4" :code-entity-id "bad-factory-return"} {} {}) :bad-factory-return)
  (local factory-error (executor:run-step {:id "def-1"} {:id "step-5" :code-entity-id "factory-error"} {} {}))
  (assert-failed-kind factory-error :factory-error)
  (assert (= (type factory-error.error.message) "string") "factory error message should be a string"))

(fn executor-normalizes-non-string-method-errors []
  (local source "{:run (fn [self ctx input state] (error {:reason :method-boom}))}")
  (local executor (make-executor {"code-1" {:id "code-1" :language "fnl" :source source}}))
  (local outcome (executor:run-step {:id "def-1"} {:id "step-1" :code-entity-id "code-1"} {} {}))
  (assert-failed-kind outcome :method-error)
  (assert (= (type outcome.error.message) "string") "method error message should be a string"))

(fn ctx-helper-does-not-complete-without-returned-outcome []
  (local source "{:run (fn [self ctx input state] (ctx:succeed {:ignored true}) nil)}")
  (local executor (make-executor {"code-1" {:id "code-1" :language "fnl" :source source}}))
  (local outcome (executor:run-step {:id "def-1"} {:id "step-1" :code-entity-id "code-1"} {} {}))
  (assert-failed-message outcome "invalid outcome")
  (assert-failed-kind outcome :invalid-outcome))

(fn executor-reports-missing-method-kind []
  (local source "{:run (fn [self ctx input state] (ctx:succeed {:ok true}))}")
  (local executor (make-executor {"code-1" {:id "code-1" :language "fnl" :source source}}))
  (local outcome (executor:resume-step {:id "def-1"} {:id "step-1" :code-entity-id "code-1"} {} {}))
  (assert-failed-message outcome "missing required method")
  (assert-failed-kind outcome :missing-method))

(fn executor-adapts-resume-and-cancel-methods []
  (local source "{:run (fn [self ctx input state] (ctx:wait :signal {:id input.id} state)) :resume (fn [self ctx wait-result state] (ctx:succeed {:resumed wait-result.value :state state.token})) :cancel (fn [self ctx state] (ctx:cancelled {:state state.token}))}")
  (local executor (make-executor {"code-1" {:id "code-1" :language "fennel" :source source}}))
  (local definition {:id "def-1"})
  (local step {:id "step-1" :code-entity-id "code-1"})
  (local waiting (executor:run-step definition step {:id "wait-1"} {:token "run"}))
  (assert (= waiting.status :waiting) "run should return waiting")
  (assert (= waiting.wait-kind :signal) "waiting should include wait kind")
  (local resumed (executor:resume-step definition step {:value "done"} {:token "resume"}))
  (assert (= resumed.status :succeeded) "resume should succeed")
  (assert (= resumed.output.resumed "done") "resume should receive wait result")
  (assert (= resumed.output.state "resume") "resume should receive state")
  (local cancelled (executor:cancel-step definition step {:token "cancel"}))
  (assert (= cancelled.status :cancelled) "cancel should return cancelled")
  (assert (= cancelled.output.state "cancel") "cancel should receive state"))

(table.insert tests {:name "outcome helpers return strict tables"
                     :fn outcome-helpers-return-strict-tables})
(table.insert tests {:name "invalid outcomes fail loudly"
                      :fn invalid-outcomes-fail-loudly})
(table.insert tests {:name "sparse next step ids fail loudly"
                     :fn sparse-next-step-ids-fail-loudly})
(table.insert tests {:name "executor evaluates code entity factory with full app access"
                     :fn executor-evaluates-code-entity-factory-with-full-app-access})
(table.insert tests {:name "executor rejects missing code entity"
                      :fn executor-rejects-missing-code-entity})
(table.insert tests {:name "executor returns structured step object errors"
                     :fn executor-returns-structured-step-object-errors})
(table.insert tests {:name "executor normalizes non-string method errors"
                     :fn executor-normalizes-non-string-method-errors})
(table.insert tests {:name "ctx helper does not complete without returned outcome"
                      :fn ctx-helper-does-not-complete-without-returned-outcome})
(table.insert tests {:name "executor reports missing method kind"
                     :fn executor-reports-missing-method-kind})
(table.insert tests {:name "executor adapts resume and cancel methods"
                     :fn executor-adapts-resume-and-cancel-methods})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "workflow-code-executor"
                       :tests tests})))

{:name "workflow-code-executor"
 :tests tests
 :main main}
