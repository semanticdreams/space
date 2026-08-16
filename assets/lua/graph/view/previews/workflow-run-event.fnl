(local {: Flex : FlexChild} (require :flex))
(local Text (require :text))
(local PreviewSummary (require :workflows/preview-summary))

(fn resolve-target [node options]
  (if node node (assert options.node "WorkflowRunEventNodePreview requires node")))

(fn resolve-build-ctx [ctx]
  (if ctx
      ctx
      (error "WorkflowRunEventNodePreview requires a build context")))

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn find-event [store run-id event-id]
  (var found nil)
  (local run (store:get-run run-id))
  (when run
    (each [_ event (ipairs run.events)]
      (when (= event.id event-id)
        (set found event))))
  found)

(fn current-event [target]
  (local store (assert target.workflow-store "WorkflowRunEventNodePreview requires workflow store"))
  (local run-id (assert target.workflow-run-id "WorkflowRunEventNodePreview requires workflow run id"))
  (local event-id (assert target.workflow-event-id "WorkflowRunEventNodePreview requires workflow event id"))
  (assert (find-event store run-id event-id)
          (.. "WorkflowRunEventNodePreview requires an existing run event: " run-id ":" event-id)))

(local METADATA_KEYS {:id true
                      :run-id true
                      :kind true
                      :step-id true
                      :created-at true})

(fn has-payload-details? [event]
  (var found false)
  (when event
    (each [key _value (pairs event)]
      (when (not (. METADATA_KEYS key))
        (set found true))))
  found)

(fn build-content [target build-ctx]
  (local view {})
  (local label (if (and target target.label) target.label target.key target.key "Workflow run event"))
  (local title ((Text {:text (tostring label)}) build-ctx))
  (local event (current-event target))
  (local summary (PreviewSummary.run-event-summary event))
  (local summary-text ((Text {:text summary}) build-ctx))
  (local payload-hint
    (when (has-payload-details? event)
      ((Text {:text "Open node for payload panel"}) build-ctx)))
  (local children [(FlexChild (existing-widget title) 0)
                   (FlexChild (existing-widget summary-text) 0)])
  (when payload-hint
    (table.insert children (FlexChild (existing-widget payload-hint) 0)))
  (local flex
    ((Flex {:axis 2
            :xalign :stretch
            :yspacing 0.25
            :children children})
     build-ctx))
  (set view.layout flex.layout)
  (set view.title title)
  (set view.summary-text summary-text)
  (set view.payload-hint payload-hint)
  (set view.flex flex)
  (set view.drop
       (fn [_self]
         (title:drop)
         (summary-text:drop)
         (when payload-hint
           (payload-hint:drop))
         (flex:drop)))
  view)

(fn WorkflowRunEventNodePreview [node opts]
  (local options (if opts opts {}))
  (local target (resolve-target node options))
  (fn build [ctx]
    (build-content target (resolve-build-ctx ctx))))

WorkflowRunEventNodePreview
