(local {: Flex : FlexChild} (require :flex))
(local Input (require :input))
(local Text (require :text))

(fn resolve-target [node options]
  (if node node (assert options.node "WorkflowDefinitionNodeView requires node")))

(fn resolve-build-ctx [ctx]
  (if ctx
      ctx
      (error "WorkflowDefinitionNodeView requires a build context")))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn current-definition [target]
  (assert (and target target.workflow-store)
          "WorkflowDefinitionNodeView requires workflow store")
  (assert (and target.workflow-store target.workflow-store.get-definition)
          "WorkflowDefinitionNodeView requires workflow store:get-definition")
  (assert target.workflow-definition-id
          "WorkflowDefinitionNodeView requires workflow definition id")
  (local definition (target.workflow-store:get-definition target.workflow-definition-id))
  (assert definition
          (.. "WorkflowDefinitionNodeView missing workflow definition: "
              (tostring target.workflow-definition-id)))
  definition)

(fn rename-on-change [target]
  (fn [_input new-value]
    (assert (and target target.update-name)
            "WorkflowDefinitionNodeView requires target:update-name")
    (target:update-name new-value)))

(fn build-content [target build-ctx]
  (local view {})
  (local definition (current-definition target))
  (local title ((Text {:text "Workflow Definition"}) build-ctx))
  (local help-text
    ((Text {:text "Edit this name to rename the existing workflow definition."})
     build-ctx))
  (local initial-name (if definition.name definition.name ""))
  (local name-input
    ((Input {:text initial-name
             :placeholder "Workflow name..."
             :on-change (rename-on-change target)})
     build-ctx))
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.35
            :children [(FlexChild (existing-widget title) 0)
                       (FlexChild (existing-widget name-input) 0)
                       (FlexChild (existing-widget help-text) 0)]})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.name-input name-input)
  (set view.help-text help-text)
  (set view.flex flex)
  (set view.drop
       (fn [_self]
         (title:drop)
         (name-input:drop)
         (help-text:drop)
         (set flex.children [])
         (flex:drop)))
  view)

(fn WorkflowDefinitionNodeView [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

WorkflowDefinitionNodeView
