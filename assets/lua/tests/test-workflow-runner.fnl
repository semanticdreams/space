(local fs (require :fs))
(local {: WorkflowStore} (require :workflows/store))
(local {: WorkflowRunner} (require :workflows/runner))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "workflow-runner"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "runner-" (os.time) "-" temp-counter)))

(fn with-temp-store [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local store (WorkflowStore {:base-dir dir}))
  (local (ok result) (pcall f store))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (if ok
      result
      (error result)))

(fn make-executor [outcomes]
  (local calls [])
  {:calls calls
   :run-step (fn [_self _definition step input state]
               (table.insert calls {:method :run :step-id step.id :input input :state state})
               (local step-id step.id)
               (local item (. outcomes step-id))
               (if (= (type item) "function")
                   (item calls input state)
                   item))
   :resume-step (fn [_self _definition step wait-result state]
                  (table.insert calls {:method :resume :step-id step.id :input wait-result :state state})
                  (local step-id step.id)
                  (local item (. outcomes (.. step-id ":resume")))
                  (if (= (type item) "function")
                      (item calls wait-result state)
                      item))
   :cancel-step (fn [_self _definition step state]
                  (table.insert calls {:method :cancel :step-id step.id :state state})
                  {:status :cancelled})})

(fn make-runner [store outcomes]
  (local executor (make-executor outcomes))
  (values (WorkflowRunner {:store store :executor executor :app app}) executor))

(fn event-kind-count [store run-id kind]
  (var count 0)
  (each [_ event (ipairs (store:list-events run-id))]
    (when (= event.kind kind)
      (set count (+ count 1))))
  count)

(fn define-workflow [store steps edges]
  (store:create-definition {:name "runner"
                            :steps steps
                            :edges (if (= edges nil) [] edges)}))

(fn runner-start-run-creates-run-steps-and-events-case [store]
      (local definition (define-workflow store [{:id "a" :code-entity-id "code-a"}
                                                {:id "b" :code-entity-id "code-b"}]))
      (local (runner _executor) (make-runner store {}))
      (local run (runner:start-run definition.id {:prompt "go"} {:source :test}))
      (assert (= run.status :queued) "start-run should create queued run")
      (assert (= (. (store:get-run-step run.id "a") :status) :pending) "step a should be pending")
      (assert (= (. (store:get-run-step run.id "b") :status) :pending) "step b should be pending")
      (assert (= (event-kind-count store run.id :run-created) 1) "run-created event should be appended"))

(fn runner-start-run-creates-run-steps-and-events []
  (with-temp-store runner-start-run-creates-run-steps-and-events-case))

(fn linear-b-outcome [_calls input _state]
  {:status :succeeded :output {:seen input.question}})

(fn runner-succeeds-linear-workflow-and-data-edge-case [store]
      (local definition (define-workflow store [{:id "a" :code-entity-id "code-a"}
                                                {:id "b" :code-entity-id "code-b"}]
                                        [{:id "c-a-b" :kind :control :source-step-id "a" :target-step-id "b"}
                                         {:id "d-a-b" :kind :data :source-step-id "a" :target-step-id "b" :source-port "answer" :target-port "question"}]))
      (local (runner executor) (make-runner store {"a" {:status :succeeded :output {:answer 42}}
                                                   "b" linear-b-outcome}))
      (local run (runner:start-run definition.id {:initial true} {}))
      (runner:tick-run run.id {})
      (assert (= (length executor.calls) 1) "default tick should run one step")
      (runner:tick-run run.id {})
      (local refreshed (store:get-run run.id))
      (assert (= refreshed.status :succeeded) "linear workflow should succeed")
      (assert (= (. (store:get-run-step run.id "b") :input :question) 42) "data edge should map source port to target input"))

(fn runner-succeeds-linear-workflow-and-data-edge []
  (with-temp-store runner-succeeds-linear-workflow-and-data-edge-case))

(fn runner-fails-step-on-invalid-contract-case [store]
      (local definition (define-workflow store [{:id "bad" :code-entity-id "code-bad"}]))
      (local (runner _executor) (make-runner store {"bad" nil}))
      (local run (runner:start-run definition.id {} {}))
      (runner:tick-run run.id {})
      (assert (= (. (store:get-run-step run.id "bad") :status) :failed) "invalid contract should fail step")
      (assert (= (. (store:get-run run.id) :status) :failed) "invalid contract should fail run")
      (assert (= (. (store:get-run-step run.id "bad") :error :data :kind) :invalid-outcome) "invalid contract should store structured error data")
      (assert (= (event-kind-count store run.id :step-failed) 1) "step-failed event should be appended"))

(fn runner-fails-step-on-invalid-contract []
  (with-temp-store runner-fails-step-on-invalid-contract-case))

(fn runner-waits-and-resumes-human-input-case [store]
      (local definition (define-workflow store [{:id "ask" :code-entity-id "code-ask"}]))
      (local (runner executor) (make-runner store {"ask" {:status :waiting :wait-kind :human-input :request {:prompt "continue?"} :state {:token "abc"}}
                                                   "ask:resume" {:status :succeeded :output {:answer "yes"}}}))
      (local run (runner:start-run definition.id {} {}))
      (runner:tick-run run.id {})
      (assert (= (. (store:get-run run.id) :status) :waiting) "waiting step should make run waiting")
      (assert (= (. (store:get-run-step run.id "ask") :wait :kind) :human-input) "wait metadata should persist")
      (runner:resume-step run.id "ask" {:answer "yes"})
      (assert (= (. executor.calls 2 :method) :resume) "resume should call step resume method")
      (assert (= (. (store:get-run run.id) :status) :succeeded) "resumed run should succeed"))

(fn runner-waits-and-resumes-human-input []
  (with-temp-store runner-waits-and-resumes-human-input-case))

(fn runner-resume-reactivates-waiting-run-for-downstream-tick-case [store]
      (local definition (define-workflow store [{:id "ask" :code-entity-id "code-ask"}
                                                {:id "continue" :code-entity-id "code-continue"}]
                                        [{:source-step-id "ask" :target-step-id "continue"}]))
      (local (runner executor) (make-runner store {"ask" {:status :waiting :wait-kind :human-input :request {:prompt "continue?"}}
                                                   "ask:resume" {:status :succeeded :output {:answer "yes"}}
                                                   "continue" {:status :succeeded :output {:done true}}}))
      (local run (runner:start-run definition.id {} {}))
      (runner:tick-run run.id {})
      (assert (= (. (store:get-run run.id) :status) :waiting) "waiting step should remove run from active app ticks")
      (runner:resume-step run.id "ask" {:answer "yes"})
      (runner:tick {:max-steps 1})
      (assert (= (length executor.calls) 3) "app tick after resume should execute one downstream step")
      (assert (= (. executor.calls 3 :step-id) "continue") "app tick after resume should execute downstream step")
      (assert (= (. (store:get-run run.id) :status) :succeeded) "resumed workflow should complete after downstream app tick"))

(fn runner-resume-reactivates-waiting-run-for-downstream-tick []
  (with-temp-store runner-resume-reactivates-waiting-run-for-downstream-tick-case))

(fn runner-resume-cancelled-outcome-finishes-run-case [store]
      (local definition (define-workflow store [{:id "ask" :code-entity-id "code-ask"}]))
      (local (runner executor) (make-runner store {"ask" {:status :waiting :wait-kind :human-input :request {:prompt "continue?"}}
                                                   "ask:resume" {:status :cancelled}}))
      (local run (runner:start-run definition.id {} {}))
      (runner:tick-run run.id {})
      (runner:resume-step run.id "ask" {:answer "stop"})
      (local refreshed (store:get-run run.id))
      (assert (= refreshed.status :cancelled) "cancelled resume outcome should finish run as cancelled")
      (assert (= (. (store:get-run-step run.id "ask") :status) :cancelled) "cancelled resume outcome should cancel waiting step")
      (local ticked (runner:tick {:max-steps 1}))
      (assert (= (length ticked) 0) "cancelled resume outcome should leave run out of active app ticks")
      (assert (= (length executor.calls) 2) "cancelled resume outcome should not execute again after app tick"))

(fn runner-resume-cancelled-outcome-finishes-run []
  (with-temp-store runner-resume-cancelled-outcome-finishes-run-case))

(fn retry-outcome [calls _input state]
  (if (= (length calls) 1)
      {:status :retry :delay-ms 0 :state {:token "again"}}
      {:status :succeeded :output {:state state.token}}))

(fn runner-retries-with-attempt-state-case [store]
      (local definition (define-workflow store [{:id "retry" :code-entity-id "code-retry" :retry {:max-attempts 1}}]))
      (local (runner _executor) (make-runner store {"retry" retry-outcome}))
      (local run (runner:start-run definition.id {} {}))
      (runner:tick-run run.id {})
      (assert (= (. (store:get-run-step run.id "retry") :attempt) 1) "retry should increment attempt")
      (assert (= (. (store:get-run-step run.id "retry") :state :token) "again") "retry should persist attempt state")
      (assert (= (event-kind-count store run.id :step-retried) 1) "retry event should be appended")
      (runner:tick-run run.id {})
      (assert (= (. (store:get-run run.id) :status) :succeeded) "retry should eventually succeed"))

(fn runner-retries-with-attempt-state []
  (with-temp-store runner-retries-with-attempt-state-case))

(fn runner-cancels-run-case [store]
      (local definition (define-workflow store [{:id "a" :code-entity-id "code-a"}]))
      (local (runner _executor) (make-runner store {}))
      (local run (runner:start-run definition.id {} {}))
      (runner:cancel-run run.id "stop")
      (assert (= (. (store:get-run run.id) :status) :cancelled) "cancel should set run cancelled")
      (assert (= (. (store:get-run-step run.id "a") :status) :cancelled) "cancel should cancel pending steps")
      (assert (= (event-kind-count store run.id :run-cancelled) 1) "cancel event should be appended"))

(fn runner-cancels-run []
  (with-temp-store runner-cancels-run-case))

(fn runner-rejects-cancel-for-succeeded-run-case [store]
      (local definition (define-workflow store [{:id "a" :code-entity-id "code-a"}]))
      (local (runner _executor) (make-runner store {"a" {:status :succeeded :output {:done true}}}))
      (local run (runner:start-run definition.id {} {}))
      (runner:tick-run run.id {})
      (local event-count-before (length (store:list-events run.id)))
      (local (ok _err) (pcall runner.cancel-run runner run.id "too late"))
      (local refreshed (store:get-run run.id))
      (assert (not ok) "cancel should reject terminal succeeded runs")
      (assert (= refreshed.status :succeeded) "cancel should not rewrite succeeded run status")
      (assert (= (. (store:get-run-step run.id "a") :status) :succeeded) "cancel should not rewrite succeeded run step")
      (assert (= (length (store:list-events run.id)) event-count-before) "cancel should not append events for terminal runs"))

(fn runner-rejects-cancel-for-succeeded-run []
  (with-temp-store runner-rejects-cancel-for-succeeded-run-case))

(fn runner-branches-from-next-step-ids-case [store]
      (local definition (define-workflow store [{:id "start" :code-entity-id "code-start"}
                                                {:id "left" :code-entity-id "code-left"}
                                                {:id "right" :code-entity-id "code-right"}]
                                        [{:source-step-id "start" :target-step-id "left"}
                                         {:source-step-id "start" :target-step-id "right"}]))
      (local (runner executor) (make-runner store {"start" {:status :succeeded :next-step-ids ["right"]}
                                                   "right" {:status :succeeded :output {:ok true}}}))
      (local run (runner:start-run definition.id {} {}))
      (runner:tick-run run.id {})
      (runner:tick-run run.id {})
      (assert (= (. executor.calls 2 :step-id) "right") "branch should run selected target")
      (assert (= (. (store:get-run-step run.id "left") :status) :skipped) "unselected branch should be skipped")
      (assert (= (. (store:get-run run.id) :status) :succeeded) "selected branch should complete run"))

(fn runner-branches-from-next-step-ids []
  (with-temp-store runner-branches-from-next-step-ids-case))

(fn runner-skips-unselected-branch-descendants-case [store]
      (local definition (define-workflow store [{:id "start" :code-entity-id "code-start"}
                                                {:id "left" :code-entity-id "code-left"}
                                                {:id "child" :code-entity-id "code-child"}
                                                {:id "right" :code-entity-id "code-right"}]
                                        [{:source-step-id "start" :target-step-id "left"}
                                         {:source-step-id "start" :target-step-id "right"}
                                         {:source-step-id "left" :target-step-id "child"}]))
      (local (runner executor) (make-runner store {"start" {:status :succeeded :next-step-ids ["right"]}
                                                   "child" {:status :succeeded :output {:side-effect true}}
                                                   "right" {:status :succeeded :output {:ok true}}}))
      (local run (runner:start-run definition.id {} {}))
      (runner:tick-run run.id {})
      (runner:tick-run run.id {})
      (assert (= (. executor.calls 2 :step-id) "right") "selected branch should run before any unselected descendant")
      (assert (= (. (store:get-run-step run.id "left") :status) :skipped) "unselected branch root should be skipped")
      (assert (= (. (store:get-run-step run.id "child") :status) :skipped) "unselected branch descendant should be skipped")
      (assert (= (. (store:get-run run.id) :status) :succeeded) "workflow should succeed without running unselected descendant"))

(fn runner-skips-unselected-branch-descendants []
  (with-temp-store runner-skips-unselected-branch-descendants-case))

(fn loop-outcome [calls _input _state]
  (if (< (length calls) 3)
      {:status :succeeded :next-step-ids ["loop"] :output {:count (length calls)}}
      {:status :succeeded :output {:count (length calls)}}))

(fn runner-loops-with-one-step-per-tick-case [store]
      (local definition (define-workflow store [{:id "loop" :code-entity-id "code-loop"}]
                                        [{:source-step-id "loop" :target-step-id "loop"}]))
      (local (runner executor) (make-runner store {"loop" loop-outcome}))
      (local run (runner:start-run definition.id {} {}))
      (runner:tick-run run.id {})
      (assert (= (length executor.calls) 1) "first tick should run one loop iteration")
      (runner:tick-run run.id {})
      (assert (= (length executor.calls) 2) "second tick should run one more loop iteration")
      (runner:tick-run run.id {})
      (assert (= (. (store:get-run run.id) :status) :succeeded) "loop should finish when it stops selecting itself"))

(fn runner-loops-with-one-step-per-tick []
  (with-temp-store runner-loops-with-one-step-per-tick-case))

(fn loop-exit-outcome [calls _input _state]
  (if (= (length calls) 1)
      {:status :succeeded :next-step-ids ["loop"] :output {:iteration 1}}
      {:status :succeeded :output {:iteration 2}}))

(fn runner-loop-exit-clears-stale-next-step-ids-case [store]
      (local definition (define-workflow store [{:id "loop" :code-entity-id "code-loop"}
                                                {:id "done" :code-entity-id "code-done"}]
                                        [{:source-step-id "loop" :target-step-id "loop"}
                                         {:source-step-id "loop" :target-step-id "done"}]))
      (local (runner executor) (make-runner store {"loop" loop-exit-outcome
                                                   "done" {:status :succeeded :output {:complete true}}}))
      (local run (runner:start-run definition.id {} {}))
      (runner:tick-run run.id {})
      (runner:tick-run run.id {})
      (local done-status (. (store:get-run-step run.id "done") :status))
      (local loop-next (. (store:get-run-step run.id "loop") :next-step-ids))
      (assert (= done-status :ready) (.. "downstream continuation should become ready after loop exits, status=" (tostring done-status) " next=" (tostring loop-next)))
      (runner:tick-run run.id {})
      (assert (= (. executor.calls 3 :step-id) "done") "loop exit without next-step-ids should select downstream continuation")
      (assert (= (. (store:get-run run.id) :status) :succeeded) "loop exit workflow should succeed"))

(fn runner-loop-exit-clears-stale-next-step-ids []
  (with-temp-store runner-loop-exit-clears-stale-next-step-ids-case))

(fn runner-joins-after-all-inbound-steps-succeed-case [store]
      (local definition (define-workflow store [{:id "start" :code-entity-id "code-start"}
                                                {:id "a" :code-entity-id "code-a"}
                                                {:id "b" :code-entity-id "code-b"}
                                                {:id "join" :code-entity-id "code-join"}]
                                        [{:source-step-id "start" :target-step-id "a"}
                                         {:source-step-id "start" :target-step-id "b"}
                                         {:source-step-id "a" :target-step-id "join"}
                                         {:source-step-id "b" :target-step-id "join"}]))
      (local (runner executor) (make-runner store {"start" {:status :succeeded :next-step-ids ["a" "b"]}
                                                   "a" {:status :succeeded}
                                                   "b" {:status :succeeded}
                                                   "join" {:status :succeeded :output {:joined true}}}))
      (local run (runner:start-run definition.id {} {}))
      (runner:tick-run run.id {:max-steps 3})
      (assert (= (. (store:get-run-step run.id "join") :status) :ready) "join should become ready only after all selected inbound steps")
      (runner:tick-run run.id {})
      (assert (= (. executor.calls 4 :step-id) "join") "join should run after both inbound steps succeed")
      (assert (= (. (store:get-run run.id) :status) :succeeded) "join workflow should succeed"))

(fn runner-joins-after-all-inbound-steps-succeed []
  (with-temp-store runner-joins-after-all-inbound-steps-succeed-case))

(fn runner-tick-advances-active-app-scoped-runs-case [store]
      (local definition (define-workflow store [{:id "app-step" :code-entity-id "code-app-step"}]))
      (local (runner executor) (make-runner store {"app-step" {:status :succeeded :output {:app true}}}))
      (local run (runner:start-run definition.id {:prompt "tick"} {:scope :app}))
      (local ticked (runner:tick {:max-steps 1}))
      (assert (= (length ticked) 1) "runner tick should return the active app-scoped run")
      (assert (= (. executor.calls 1 :step-id) "app-step") "runner tick should execute the active run step")
      (assert (= (. (store:get-run run.id) :status) :succeeded) "runner tick should advance active runs to completion"))

(fn runner-tick-advances-active-app-scoped-runs []
  (with-temp-store runner-tick-advances-active-app-scoped-runs-case))

(fn runner-tick-does-not-scan-completed-run-history-case [store]
      (local definition (define-workflow store [{:id "active" :code-entity-id "code-active"}]))
      (local historical (store:create-run definition.id {} {:scope :history}))
      (store:update-run historical.id {:status :succeeded :finished-at (os.time)})
      (local (runner executor) (make-runner store {"active" {:status :succeeded :output {:ok true}}}))
      (local active (runner:start-run definition.id {:prompt "tick"} {:scope :app}))
      (local original-list-runs store.list-runs)
      (set store.list-runs (fn [_self _opts]
                             (error "runner.tick must not scan complete run history via list-runs")))
      (local (ok result) (pcall (fn [] (runner:tick {:max-steps 1}))))
      (set store.list-runs original-list-runs)
      (assert ok result)
      (assert (= (length result) 1) "runner tick should return only active runs")
      (assert (= (. result 1 :id) active.id) "runner tick should advance the active run")
      (assert (= (length executor.calls) 1) "runner tick should execute active run only"))

(fn runner-tick-does-not-scan-completed-run-history []
  (with-temp-store runner-tick-does-not-scan-completed-run-history-case))

(fn runner-tick-leaves-waiting-runs-stable-case [store]
      (local definition (define-workflow store [{:id "ask" :code-entity-id "code-ask"}]))
      (local (runner _executor) (make-runner store {"ask" {:status :waiting :wait-kind :human-input :request {:prompt "continue?"}}}))
      (local run (runner:start-run definition.id {} {}))
      (runner:tick-run run.id {})
      (local event-count-before (length (store:list-events run.id)))
      (local waiting-count-before (event-kind-count store run.id :run-waiting))
      (runner:tick {:max-steps 1})
      (runner:tick {:max-steps 1})
      (assert (= (. (store:get-run run.id) :status) :waiting) "waiting run should remain waiting across app ticks")
      (assert (= (length (store:list-events run.id)) event-count-before) "app ticks should not append duplicate events for waiting runs")
      (assert (= (event-kind-count store run.id :run-waiting) waiting-count-before) "app ticks should not duplicate run-waiting events"))

(fn runner-tick-leaves-waiting-runs-stable []
  (with-temp-store runner-tick-leaves-waiting-runs-stable-case))

(table.insert tests {:name "runner-start-run-creates-run-steps-and-events" :fn runner-start-run-creates-run-steps-and-events})
(table.insert tests {:name "runner-succeeds-linear-workflow-and-data-edge" :fn runner-succeeds-linear-workflow-and-data-edge})
(table.insert tests {:name "runner-fails-step-on-invalid-contract" :fn runner-fails-step-on-invalid-contract})
(table.insert tests {:name "runner-waits-and-resumes-human-input" :fn runner-waits-and-resumes-human-input})
(table.insert tests {:name "runner-resume-reactivates-waiting-run-for-downstream-tick" :fn runner-resume-reactivates-waiting-run-for-downstream-tick})
(table.insert tests {:name "runner-resume-cancelled-outcome-finishes-run" :fn runner-resume-cancelled-outcome-finishes-run})
(table.insert tests {:name "runner-retries-with-attempt-state" :fn runner-retries-with-attempt-state})
(table.insert tests {:name "runner-cancels-run" :fn runner-cancels-run})
(table.insert tests {:name "runner-rejects-cancel-for-succeeded-run" :fn runner-rejects-cancel-for-succeeded-run})
(table.insert tests {:name "runner-branches-from-next-step-ids" :fn runner-branches-from-next-step-ids})
(table.insert tests {:name "runner-skips-unselected-branch-descendants" :fn runner-skips-unselected-branch-descendants})
(table.insert tests {:name "runner-loops-with-one-step-per-tick" :fn runner-loops-with-one-step-per-tick})
(table.insert tests {:name "runner-loop-exit-clears-stale-next-step-ids" :fn runner-loop-exit-clears-stale-next-step-ids})
(table.insert tests {:name "runner-joins-after-all-inbound-steps-succeed" :fn runner-joins-after-all-inbound-steps-succeed})
(table.insert tests {:name "runner-tick-advances-active-app-scoped-runs" :fn runner-tick-advances-active-app-scoped-runs})
(table.insert tests {:name "runner-tick-does-not-scan-completed-run-history" :fn runner-tick-does-not-scan-completed-run-history})
(table.insert tests {:name "runner-tick-leaves-waiting-runs-stable" :fn runner-tick-leaves-waiting-runs-stable})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "workflow-runner"
                       :tests tests})))

{:name "workflow-runner"
 :tests tests
 :main main}
