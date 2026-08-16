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

(fn load-required-node [graph key action]
  (assert graph (.. action " requires a graph map"))
  (assert graph.load-by-key (.. action " requires graph:load-by-key"))
  (local node (graph:load-by-key key))
  (assert node (.. action " failed to load graph node: " key))
  node)

(fn add-visible-edge [graph source target label]
  (assert graph "WorkflowRunNode requires a graph map")
  (assert graph.add-edge "WorkflowRunNode requires graph:add-edge")
  (graph:add-edge (GraphEdge {:source source :target target :label label})))

(fn graph-map? [graph]
  (and graph
       graph.graph
       (not (= graph.graph graph))
       graph.nodes
       graph.edges
       graph.edge-map
       graph.lookup
       graph.load-by-key
       graph.add-edge
       graph.node-added
       graph.edge-added
       graph.node-removed
       graph.edge-removed
       graph.node-added.emit
       graph.edge-added.emit
       graph.graph.register-key-loader))

(fn loader-graph [graph]
  (if (and graph graph.graph graph.graph.has-key-loader-for-key)
      graph.graph
      (if (and graph graph.has-key-loader-for-key)
          graph
          nil)))

(fn assert-graph-loader [graph key action label]
  (local provider (loader-graph graph))
  (assert (and provider (provider:has-key-loader-for-key key))
          (.. action " requires graph loader for " label)))

(fn assert-run-dependencies [self action]
  (assert self.workflow-store (.. action " requires workflow store"))
  (assert self.workflow-store.get-run (.. action " requires workflow store:get-run"))
  (assert self.workflow-store.list-run-steps (.. action " requires workflow store:list-run-steps"))
  (assert self.workflow-store.list-events (.. action " requires workflow store:list-events"))
  (assert (graph-map? self.graph) (.. action " requires a graph map"))
  (assert self.graph.load-by-key (.. action " requires graph:load-by-key"))
  (assert self.graph.add-edge (.. action " requires graph:add-edge")))

(fn current-run [self action]
  (local current (self.workflow-store:get-run self.workflow-run-id))
  (assert current (.. action " missing workflow run: " (tostring self.workflow-run-id)))
  current)

(fn run-step-key [run-id step-id]
  (.. "workflow-run-step:" run-id ":" step-id))

(fn timeline-key [run-id]
  (.. "workflow-run-timeline:" run-id))

(fn failed-status? [status]
  (= (status-key status) :failed))

(fn make-show-run-steps-action [node]
  {:name "Show Run Steps"
   :icon "account_tree"
   :fn (fn [_button _event]
         (node:load-run-steps-from-graph))})

(fn make-reveal-failed-action [node]
  {:name "Reveal Failed Steps"
   :icon "error"
   :fn (fn [_button _event]
         (node:reveal-failed-run-steps-from-graph))})

(fn make-open-timeline-action [node]
  {:name "Open Timeline"
   :icon "timeline"
   :fn (fn [_button _event]
         (node:open-timeline-from-graph))})

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
  (local actions [(make-show-run-steps-action self)
                  (make-reveal-failed-action self)
                  (make-open-timeline-action self)])
  (when (cancellable-run? self)
    (table.insert actions (make-cancel-action self)))
  actions)

(fn load-run-steps [self opts]
  (local action "WorkflowRunNode.load-run-steps-from-graph")
  (assert-run-dependencies self action)
  (assert-graph-loader self.graph (run-step-key self.workflow-run-id "__preflight__") action "workflow-run-step")
  (local current (current-run self action))
  (local run-steps (self.workflow-store:list-run-steps current.id))
  (local options (or opts {}))
  (local loaded [])
  (each [_ run-step (ipairs run-steps)]
    (when (or (not options.failed-only?) (failed-status? run-step.status))
      (local step-id (assert run-step.step-id (.. action " requires run step.step-id")))
      (local step-node (load-required-node self.graph (run-step-key current.id step-id) action))
      (add-visible-edge self.graph self step-node "run step")
      (table.insert loaded step-node)))
  {:run-step-count (length loaded)
   :run-steps loaded})

(fn open-timeline [self]
  (local action "WorkflowRunNode.open-timeline-from-graph")
  (assert-run-dependencies self action)
  (assert-graph-loader self.graph (timeline-key self.workflow-run-id) action "workflow-run-timeline")
  (local current (current-run self action))
  (local timeline-node (load-required-node self.graph (timeline-key current.id) action))
  (add-visible-edge self.graph self timeline-node "timeline")
  timeline-node)

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
  (set node.load-run-steps-from-graph load-run-steps)
  (set node.reveal-failed-run-steps-from-graph
       (fn [self]
         (self:load-run-steps-from-graph {:failed-only? true})))
  (set node.open-timeline-from-graph open-timeline)
  (set node.cancel-run-action (fn [_button _event]
                                (node.workflow-runner:cancel-run node.workflow-run-id "cancelled from graph")))
  (set node.actions run-actions)
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
