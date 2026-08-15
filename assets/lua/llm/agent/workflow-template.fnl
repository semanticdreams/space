(local DEFINITION_ID "wf-agent-session-v1")
(local STEP_ID "step-agent-chat")
(local CODE_ENTITY_ID "space-agent-session-step-v1")

(fn default-source []
  "(local WorkflowStep (require :llm/agent/workflow-step))\nWorkflowStep.AgentChatStep")

(fn assert-store-method [store method-name message]
  (assert store message)
  (assert (= (type (. store method-name)) "function") message)
  store)

(fn table-or-empty [value]
  (if (= value nil) {} value))

(fn array-or-empty [value]
  (if (= value nil) [] value))

(fn find-step [definition step-id]
  (var found nil)
  (each [_ step (ipairs (array-or-empty definition.steps))]
    (when (= step.id step-id)
      (set found step)))
  found)

(fn ensure-code-entity [code-store]
  (assert-store-method code-store :get-entity "agent workflow template requires code-store:get-entity")
  (assert-store-method code-store :create-entity "agent workflow template requires code-store:create-entity")
  (local existing (code-store:get-entity CODE_ENTITY_ID))
  (if existing
      existing
      (code-store:create-entity {:id CODE_ENTITY_ID
                                 :name "Agent Chat Workflow Step"
                                 :language "fnl"
                                 :source (default-source)})))

(fn create-definition [workflow-store]
  (workflow-store:create-definition {:id DEFINITION_ID
                                     :name "Agent Session Workflow"
                                     :description "Default editable workflow for sidebar-backed agent chat sessions."
                                     :status :active
                                     :steps []
                                     :edges []}))

(fn ensure-step [workflow-store definition opts]
  (local options (table-or-empty opts))
  (if (find-step definition STEP_ID)
      definition
      (do
        (assert-store-method workflow-store :add-step "agent workflow template requires workflow-store:add-step")
        (workflow-store:add-step definition.id {:id STEP_ID
                                                :name "Agent Chat"
                                                :code-entity-id CODE_ENTITY_ID
                                                :config {:agent-id options.agent-id}})
        (workflow-store:get-definition definition.id))))

(fn ensure-definition [opts]
  (local options (table-or-empty opts))
  (local workflow-store (assert options.workflow-store "ensure-definition requires workflow-store"))
  (local code-store (assert options.code-store "ensure-definition requires code-store"))
  (assert-store-method workflow-store :get-definition "agent workflow template requires workflow-store:get-definition")
  (assert-store-method workflow-store :create-definition "agent workflow template requires workflow-store:create-definition")
  (ensure-code-entity code-store)
  (local existing-definition (workflow-store:get-definition DEFINITION_ID))
  (local definition (if existing-definition
                        existing-definition
                        (create-definition workflow-store)))
  (ensure-step workflow-store definition options))

{:ensure-definition ensure-definition
 :default-source default-source
 :definition-id DEFINITION_ID
 :step-id STEP_ID
 :code-entity-id CODE_ENTITY_ID}
