(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local WorkflowRunNodePreview (require :graph/view/previews/workflow-run))

(local STATUS_COLORS
  {:pending (glm.vec4 0.55 0.55 0.55 1)
   :queued (glm.vec4 0.55 0.55 0.55 1)
   :ready (glm.vec4 0.2 0.55 0.95 1)
   :running (glm.vec4 0.2 0.55 0.95 1)
   :waiting (glm.vec4 0.9 0.65 0.18 1)
   :failed (glm.vec4 0.88 0.2 0.2 1)
   :succeeded (glm.vec4 0.2 0.72 0.32 1)
   :skipped (glm.vec4 0.45 0.45 0.55 1)
   :cancelled (glm.vec4 0.45 0.45 0.55 1)})

(fn status-key [status]
  (if (= status nil)
      :pending
      (= (type status) :string)
      (case status
        "pending" :pending
        "queued" :queued
        "ready" :ready
        "running" :running
        "waiting" :waiting
        "failed" :failed
        "succeeded" :succeeded
        "skipped" :skipped
        "cancelled" :cancelled
        _ :pending)
      status))

(fn status-color [status]
  (local color (. STATUS_COLORS (status-key status)))
  (if color color (. STATUS_COLORS :pending)))

(fn status-tone [status]
  (case (status-key status)
    :ready :info
    :running :info
    :waiting :warning
    :failed :danger
    :succeeded :success
    :skipped :neutral
    :cancelled :neutral
    :pending :neutral
    :queued :neutral
    _ :neutral))

(fn run-label [run run-id]
  (local status (if (and run run.status) run.status :pending))
  (.. "Workflow run " run-id " (" (tostring status) ")"))

(fn resolve-node [graph key]
  (var node nil)
  (when (and graph key graph.lookup)
    (set node (graph:lookup key)))
  (when (and (= node nil) graph key graph.create-node-by-key)
    (set node (graph:create-node-by-key key)))
  (when (and (= node nil) graph key graph.load-by-key)
    (set node (graph:load-by-key key)))
  node)

(fn add-edge [edges source target label]
  (when (and source target)
    (table.insert edges (GraphEdge {:source source :target target :label label}))))

(fn event-key [run-id event-id]
  (.. "workflow-run-event:" run-id ":" event-id))

(fn run-step-key [run-id step-id]
  (.. "workflow-run-step:" run-id ":" step-id))

(fn make-toggle-action [node]
  {:name (if node.details-expanded? "Hide Details" "Show Details")
   :icon (if node.details-expanded? "visibility_off" "visibility")
   :fn node.toggle-details-action})

(fn make-cancel-action [node]
  {:name "Cancel Run"
   :icon "cancel"
   :fn node.cancel-run-action})

(fn cancellable-run-status? [status]
  (local key (status-key status))
  (if (= key :queued)
      true
      (= key :running)
      true
      (= key :waiting)
      true
      false))

(fn cancellable-run? [node]
  (local run (and node node.workflow-store (node.workflow-store:get-run node.workflow-run-id)))
  (and run (cancellable-run-status? run.status)))

(fn run-actions [self]
  (local actions [(make-toggle-action self)])
  (when (cancellable-run? self)
    (table.insert actions (make-cancel-action self)))
  actions)

(fn WorkflowRunNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "WorkflowRunNode requires store"))
  (local runner (assert options.runner "WorkflowRunNode requires runner"))
  (local run-id (assert options.run-id "WorkflowRunNode requires run-id"))
  (local run (store:get-run run-id))
  (local node (GraphNode {:key (.. "workflow-run:" run-id)
                          :label (run-label run run-id)
                          :color (status-color (and run run.status))
                          :sub-color (status-color (and run run.status))
                          :preview WorkflowRunNodePreview
                          :size 8.0}))
  (set node.workflow-run-id run-id)
  (set node.workflow-store store)
  (set node.workflow-runner runner)
  (set node.details-expanded? false)
  (set node.show-details (fn [self]
                           (set self.details-expanded? true)
                           true))
  (set node.hide-details (fn [self]
                           (set self.details-expanded? false)
                           true))
  (set node.toggle-details (fn [self]
                             (if self.details-expanded?
                                 (self:hide-details)
                                 (self:show-details))))
  (set node.toggle-details-action (fn [_button _event]
                                    (node:toggle-details)))
  (set node.cancel-run-action (fn [_button _event]
                                (node.workflow-runner:cancel-run node.workflow-run-id "cancelled from graph")))
  (set node.actions run-actions)
  (set node.get-edges
       (fn [self]
         (local current (self.workflow-store:get-run self.workflow-run-id))
         (local edges [])
          (when current
            (set self.color (status-color current.status))
            (set self.label (run-label current self.workflow-run-id))
            (add-edge edges self (resolve-node self.graph (.. "workflow-definition:" current.definition-id)) "definition")
           (when self.details-expanded?
             (each [_ run-step (ipairs (self.workflow-store:list-run-steps current.id))]
               (add-edge edges self (resolve-node self.graph (run-step-key current.id run-step.step-id)) "run step"))
             (each [_ event (ipairs (self.workflow-store:list-events current.id))]
               (add-edge edges self (resolve-node self.graph (event-key current.id event.id)) "event"))))
         edges))
  node)

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (assert options.store "workflow-run.register-loader requires store"))
  (local runner (assert options.runner "workflow-run.register-loader requires runner"))
  (graph:register-key-loader "workflow-run"
    (fn [key]
      (local prefix "workflow-run:")
      (when (= (string.sub key 1 (string.len prefix)) prefix)
        (local run-id (string.sub key (+ 1 (string.len prefix))))
        (when (and (> (string.len run-id) 0) (store:get-run run-id))
          (WorkflowRunNode {:run-id run-id :store store :runner runner}))))))

{:WorkflowRunNode WorkflowRunNode
  :STATUS_COLORS STATUS_COLORS
  :status-color status-color
  :status-tone status-tone
  :register-loader register-loader}
