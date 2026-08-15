(local fs (require :fs))
(local {: WorkflowStore} (require :workflows/store))
(local {: CodeEntityStore} (require :entities/code))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "agent-workflow-template"))

(local DEFINITION_ID "wf-agent-session-v1")
(local STEP_ID "step-agent-chat")
(local CODE_ENTITY_ID "space-agent-session-step-v1")

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "template-" (os.time) "-" temp-counter)))

(fn with-stores [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local workflow-store (WorkflowStore {:base-dir dir}))
  (local code-store (CodeEntityStore {:base-dir dir}))
  (local (ok result) (pcall f workflow-store code-store dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (if ok
      result
      (error result)))

(fn find-step [definition step-id]
  (var found nil)
  (each [_ step (ipairs definition.steps)]
    (when (= step.id step-id)
      (set found step)))
  found)

(fn assert-default-step-source [source]
  (assert (string.find source "WorkflowStep.AgentChatStep" 1 true)
          "default code source should reference WorkflowStep.AgentChatStep")
  (local FennelEvaluator (require :fennel-evaluator))
  (local WorkflowStep (require :llm/agent/workflow-step))
  (local eval-result (FennelEvaluator.eval-source source))
  (assert eval-result.ok "default code source should evaluate")
  (assert (= eval-result.result WorkflowStep.AgentChatStep)
          "default code source should return WorkflowStep.AgentChatStep"))

(fn ensure-definition-creates-editable-agent-workflow []
  (with-stores
    (fn [workflow-store code-store _dir]
      (local WorkflowTemplate (require :llm/agent/workflow-template))
      (local definition (WorkflowTemplate.ensure-definition {:workflow-store workflow-store
                                                             :code-store code-store
                                                             :agent-id "agent-1"}))
      (assert (= definition.id DEFINITION_ID) "definition should use stable id")
      (local step (assert (find-step definition STEP_ID) "definition should include stable agent chat step"))
      (assert (= step.code-entity-id CODE_ENTITY_ID) "step should reference stable code entity id")
      (assert (= step.config.agent-id "agent-1") "step config should preserve agent id")
      (local code-entity (assert (code-store:get-entity CODE_ENTITY_ID) "code entity should be durable"))
      (assert (= code-entity.language "fnl") "code entity language should be fnl")
      (assert-default-step-source code-entity.source))))

(fn ensure-definition-reuses-existing-definition []
  (with-stores
    (fn [workflow-store code-store _dir]
      (local WorkflowTemplate (require :llm/agent/workflow-template))
      (workflow-store:create-definition {:id DEFINITION_ID
                                         :name "User edited workflow"
                                         :description "keep me"
                                         :status :active
                                         :parameters {:custom true}
                                         :steps []
                                         :edges []})
      (local definition (WorkflowTemplate.ensure-definition {:workflow-store workflow-store
                                                             :code-store code-store}))
      (assert (= definition.name "User edited workflow") "existing definition name should not be overwritten")
      (assert (= definition.description "keep me") "existing definition description should not be overwritten")
      (assert (= definition.status :active) "existing definition status should not be overwritten")
      (assert (= definition.parameters.custom true) "existing definition parameters should not be overwritten")
      (assert (find-step definition STEP_ID) "missing stable step should be added to existing definition"))))

(fn ensure-definition-does-not-overwrite-user-edited-code []
  (with-stores
    (fn [workflow-store code-store _dir]
      (local WorkflowTemplate (require :llm/agent/workflow-template))
      (local user-source "(fn [config] {:run (fn [self ctx input state] (ctx:succeed {:custom true}))})")
      (code-store:create-entity {:id CODE_ENTITY_ID
                                 :name "User edited step"
                                 :language "fnl"
                                 :source user-source})
      (WorkflowTemplate.ensure-definition {:workflow-store workflow-store
                                           :code-store code-store})
      (local code-entity (assert (code-store:get-entity CODE_ENTITY_ID) "code entity should still exist"))
      (assert (= code-entity.name "User edited step") "existing code entity name should not be overwritten")
      (assert (= code-entity.source user-source) "existing code entity source should not be overwritten"))))

(fn agent-chat-step-starts-waiting-for-user-input []
  (local WorkflowStep (require :llm/agent/workflow-step))
  (local step (WorkflowStep.AgentChatStep {:agent-id "agent-42"}))
  (local ctx {:wait (fn [_self wait-kind request state]
                      {:status :waiting
                       :wait-kind wait-kind
                       :request request
                       :state state})})
  (local outcome (step:run ctx {:prompt "hello"} {:turn 1}))
  (assert (= outcome.status :waiting) "agent chat step should wait")
  (assert (= outcome.wait-kind :agent-user-input) "agent chat step should wait for agent user input")
  (assert (= outcome.request.agent-id "agent-42") "wait request should include configured agent id"))

(table.insert tests {:name "ensure-definition-creates-editable-agent-workflow"
                     :fn ensure-definition-creates-editable-agent-workflow})
(table.insert tests {:name "ensure-definition-reuses-existing-definition"
                     :fn ensure-definition-reuses-existing-definition})
(table.insert tests {:name "ensure-definition-does-not-overwrite-user-edited-code"
                     :fn ensure-definition-does-not-overwrite-user-edited-code})
(table.insert tests {:name "agent-chat-step-starts-waiting-for-user-input"
                     :fn agent-chat-step-starts-waiting-for-user-input})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "agent-workflow-template"
                       :tests tests})))

{:name "agent-workflow-template"
 :tests tests
 :main main}
