(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local SearchView (require :search-view))
(local Text (require :text))

(fn resolve-target [node options]
  (if node node (assert options.node "WorkflowDefinitionNodePreview requires node")))

(fn resolve-build-ctx [ctx]
  (if ctx
      ctx
      (error "WorkflowDefinitionNodePreview requires a build context")))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn start-from-preview [target]
  (assert (and target target.start-workflow-from-graph)
          "Workflow definition preview requires start-workflow-from-graph")
  (target:start-workflow-from-graph {} {}))

(fn start-click-handler [target]
  (fn [_button _event]
    (start-from-preview target)))

(fn create-step-from-preview [target]
  (assert (and target target.create-step-from-graph)
          "Workflow definition preview requires create-step-from-graph")
  (target:create-step-from-graph {}))

(fn new-step-click-handler [target]
  (fn [_button _event]
    (create-step-from-preview target)))

(fn run-items [target]
  (assert (and target target.run-items)
          "Workflow definition preview requires run-items")
  (target:run-items))

(fn step-items [target]
  (assert (and target target.step-items)
          "Workflow definition preview requires step-items")
  (target:step-items))

(fn run-created-at [run]
  (if (and run run.created-at)
      (tonumber run.created-at)
      0))

(fn run-id [run]
  (if (and run run.id)
      (tostring run.id)
      ""))

(fn later-run? [candidate current]
  (local candidate-created-at (run-created-at candidate))
  (local current-created-at (run-created-at current))
  (if (not current)
      true
      (> candidate-created-at current-created-at)
      true
      (and (= candidate-created-at current-created-at)
           (> (run-id candidate) (run-id current)))
      true
      false))

(fn latest-run-status [items]
  (var latest nil)
  (each [_ item (ipairs (if items items []))]
    (local run (. item 1))
    (when (and run (later-run? run latest))
      (set latest run)))
  (if (and latest latest.status) (tostring latest.status) "none"))

(fn definition-id [target]
  (assert target "Workflow definition preview requires target")
  (tostring (assert target.workflow-definition-id
                    "Workflow definition preview requires workflow-definition-id")))

(fn overview-label [target step-items-list run-items-list]
  (local label (if (and target target.label) target.label target.key target.key "Workflow"))
  (.. "Definition: " (definition-id target)
      "\nName: " (tostring label)
      "\nSteps: " (length step-items-list)
      "\nRuns: " (length run-items-list)
      "\nLatest: " (latest-run-status run-items-list)))

(fn step-count-label [items]
  (.. "Steps: " (length items)))

(fn run-count-label [items]
  (.. "Runs: " (length items)))

(fn select-step [target item]
  (assert (and target target.load-step-from-graph)
          "Workflow definition preview requires load-step-from-graph")
  (target:load-step-from-graph (. item 1)))

(fn select-run [target item]
  (assert (and target target.load-run-from-graph)
          "Workflow definition preview requires load-run-from-graph")
  (target:load-run-from-graph (. item 1)))

(fn reveal-all-steps [target]
  (assert (and target target.reveal-all-steps-from-graph)
          "Workflow definition preview requires reveal-all-steps-from-graph")
  (target:reveal-all-steps-from-graph))

(fn reveal-all-click-handler [target]
  (fn [_button _event]
    (reveal-all-steps target)))

(fn open-step-explorer [target]
  (assert (and target target.open-step-explorer-from-graph)
          "Workflow definition preview requires open-step-explorer-from-graph")
  (target:open-step-explorer-from-graph))

(fn open-step-explorer-click-handler [target]
  (fn [_button _event]
    (open-step-explorer target)))

(fn build-content [target build-ctx]
  (local view {})
  (local steps (step-items target))
  (local runs (run-items target))
  (local label (if (and target target.label) target.label target.key target.key "Workflow"))
  (local title ((Text {:text (tostring label)}) build-ctx))
  (local overview-text ((Text {:text (overview-label target steps runs)}) build-ctx))
  (local step-count-text ((Text {:text (step-count-label steps)}) build-ctx))
  (local run-count-text ((Text {:text (run-count-label runs)}) build-ctx))
  (local step-search
    ((SearchView {:items steps
                  :name "workflow-definition-step-search"
                  :placeholder "Search workflow steps"})
     build-ctx))
  (local run-search
    ((SearchView {:items runs
                  :name "workflow-definition-run-search"
                  :placeholder "Search workflow runs"})
     build-ctx))
  (local reveal-all-steps-button
    ((Button {:text "Reveal All Steps"
              :variant :ghost
              :padding [0.25 0.2]
              :on-click (reveal-all-click-handler target)})
     build-ctx))
  (local open-step-explorer-button
    ((Button {:text "Open Step Explorer"
              :variant :ghost
              :padding [0.25 0.2]
              :on-click (open-step-explorer-click-handler target)})
     build-ctx))
  (local start-button
    ((Button {:text "Start"
              :variant :ghost
              :padding [0.25 0.2]
              :on-click (start-click-handler target)})
     build-ctx))
  (local new-step-button
    ((Button {:text "New Step"
              :variant :ghost
              :padding [0.25 0.2]
               :on-click (new-step-click-handler target)})
      build-ctx))
  (set view.__step-search-listener
       (step-search.submitted:connect
         (fn [item]
           (select-step target item))))
  (set view.__run-search-listener
       (run-search.submitted:connect
         (fn [item]
           (select-run target item))))
  (local flex
    ((Flex {:axis 2
             :xalign :stretch
             :yspacing 0.25
             :children [(FlexChild (existing-widget title) 0)
                        (FlexChild (existing-widget overview-text) 0)
                        (FlexChild (existing-widget step-count-text) 0)
                        (FlexChild (existing-widget step-search) 1)
                        (FlexChild (existing-widget run-count-text) 0)
                        (FlexChild (existing-widget run-search) 1)
                        (FlexChild (existing-widget reveal-all-steps-button) 0)
                        (FlexChild (existing-widget open-step-explorer-button) 0)
                        (FlexChild (existing-widget start-button) 0)
                        (FlexChild (existing-widget new-step-button) 0)]})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.overview-text overview-text)
  (set view.summary-text overview-text)
  (set view.step-count-text step-count-text)
  (set view.run-count-text run-count-text)
  (set view.step-search step-search)
  (set view.run-search run-search)
  (set view.reveal-all-steps-button reveal-all-steps-button)
  (set view.open-step-explorer-button open-step-explorer-button)
  (set view.start-button start-button)
  (set view.new-step-button new-step-button)
  (set view.flex flex)
  (set view.drop
        (fn [_self]
          (assert (not view.__dropped) "WorkflowDefinitionNodePreview dropped twice")
          (set view.__dropped true)
          (when view.__step-search-listener
            (step-search.submitted:disconnect view.__step-search-listener true)
            (set view.__step-search-listener nil))
          (when view.__run-search-listener
            (run-search.submitted:disconnect view.__run-search-listener true)
            (set view.__run-search-listener nil))
          (title:drop)
          (overview-text:drop)
          (step-count-text:drop)
          (run-count-text:drop)
          (step-search:drop)
          (run-search:drop)
          (reveal-all-steps-button:drop)
          (open-step-explorer-button:drop)
          (start-button:drop)
          (new-step-button:drop)
          (set flex.children [])
          (flex:drop)))
  view)

(fn WorkflowDefinitionNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

WorkflowDefinitionNodePreview
