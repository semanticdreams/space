(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Input (require :input))
(local SearchView (require :search-view))
(local Text (require :text))

(fn resolve-target [node options]
  (if node node (assert options.node "WorkflowsNodePreview requires node")))

(fn resolve-build-ctx [ctx]
  (if ctx
      ctx
      (error "WorkflowsNodePreview requires a build context")))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn trim-text [text]
  (string.match (tostring text) "^%s*(.-)%s*$"))

(fn create-workflow-from-preview [target workflow-name-input]
  (assert (and target target.create-workflow-from-graph)
          "Workflows preview requires create-workflow-from-graph")
  (assert workflow-name-input "Workflows preview requires workflow name input")
  (assert workflow-name-input.get-text "Workflows preview workflow name input requires get-text")
  (local raw-name (workflow-name-input:get-text))
  (assert (not (= raw-name nil)) "Workflows preview workflow name input returned nil")
  (local name (trim-text raw-name))
  (if (> (string.len name) 0)
      (target:create-workflow-from-graph {:name name})
      (target:create-workflow-from-graph {})))

(fn definition-items [target]
  (assert (and target target.workflow-store) "Workflows preview requires workflow store")
  (assert (and target target.definition-items)
          "Workflows preview requires definition-items")
  (target:definition-items))

(fn definition-count-label [items]
  (.. "Definitions: " (length items)))

(fn new-workflow-click-handler [target workflow-name-input]
  (fn [_button _event]
    (create-workflow-from-preview target workflow-name-input)))

(fn select-definition [target item]
  (assert (and target target.load-definition-from-graph)
          "Workflows preview requires load-definition-from-graph")
  (target:load-definition-from-graph (. item 1)))

(fn build-content [target build-ctx]
  (local view {})
  (local items (definition-items target))
  (local title ((Text {:text "Workflows"}) build-ctx))
  (local definition-count-text ((Text {:text (definition-count-label items)}) build-ctx))
  (local workflow-name-input
    ((Input {:text ""
             :placeholder "Workflow name..."})
     build-ctx))
  (local new-workflow-button
    ((Button {:text "New Workflow"
               :variant :ghost
               :padding [0.25 0.2]
               :on-click (new-workflow-click-handler target workflow-name-input)})
      build-ctx))
  (local definition-search
    ((SearchView {:items items
                  :name "workflow-definition-search"
                  :placeholder "Search workflow definitions"})
     build-ctx))
  (set view.__definition-search-listener
       (definition-search.submitted:connect
         (fn [item]
           (select-definition target item))))
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.25
             :children [(FlexChild (existing-widget title) 0)
                         (FlexChild (existing-widget definition-count-text) 0)
                         (FlexChild (existing-widget workflow-name-input) 0)
                         (FlexChild (existing-widget definition-search) 1)
                         (FlexChild (existing-widget new-workflow-button) 0)]})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.summary-text definition-count-text)
  (set view.definition-count-text definition-count-text)
  (set view.workflow-name-input workflow-name-input)
  (set view.definition-search definition-search)
  (set view.new-workflow-button new-workflow-button)
  (set view.flex flex)
  (set view.drop
       (fn [_self]
          (when view.__definition-search-listener
            (definition-search.submitted:disconnect view.__definition-search-listener true)
            (set view.__definition-search-listener nil))
           (title:drop)
           (definition-count-text:drop)
           (workflow-name-input:drop)
           (definition-search:drop)
          (new-workflow-button:drop)
          (set flex.children [])
          (flex:drop)))
  view)

(fn WorkflowsNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

WorkflowsNodePreview
