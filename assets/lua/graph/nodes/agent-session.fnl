(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local WorkflowEvents (require :llm/agent/workflow-events))
(local AgentSessionNodePreview (require :graph/view/previews/agent-session))

(local SESSION_BLUE (glm.vec4 0.32 0.48 0.9 1))
(local SESSION_BLUE_ACCENT (glm.vec4 0.45 0.62 1.0 1))

(fn session? [session]
  (if (not session)
      false
      session.agent-session?
      true
      (= session.kind :agent-session)
      true
      (= session.kind "agent-session")
      true
      false))

(fn project-session [store run-id]
  (local run (and store store.get-run (store:get-run run-id)))
  (when run
    (WorkflowEvents.project-session run)))

(fn item-count [session]
  (length (if (and session session.items) session.items [])))

(fn session-label [session run-id]
  (local status (if (and session session.status) session.status :pending))
  (.. "Agent session " run-id " (" (tostring status) ")"))

(fn require-graph-map [self context]
  (local graph (assert self.graph (.. context " requires a graph map")))
  (assert graph.load-by-key (.. context " requires graph:load-by-key"))
  (assert graph.add-edge (.. context " requires graph:add-edge"))
  graph)

(fn add-visible-edge [graph source target label]
  (when (and source target)
    (graph:add-edge (GraphEdge {:source source :target target :label label}))))

(fn load-key [graph key context]
  (local node (graph:load-by-key key))
  (assert node (.. context " failed to load graph node: " key))
  node)

(fn workflow-run-key [run-id]
  (.. "workflow-run:" run-id))

(fn workflow-event-key [run-id event-id]
  (.. "workflow-run-event:" run-id ":" event-id))

(fn current-session [self]
  (local session (project-session self.workflow-store self.workflow-run-id))
  (assert (session? session) (.. "AgentSessionNode requires an agent session run: " self.workflow-run-id))
  (set self.agent-session session)
  (set self.label (session-label session self.workflow-run-id))
  session)

(fn open-run-action [node]
  {:name "Open Workflow Run"
   :icon "account_tree"
   :fn (fn [_button _event]
         (node:load-backing-workflow-run))})

(fn show-events-action [node]
  {:name "Show Recent Events"
   :icon "history"
   :fn (fn [_button _event]
         (node:load-recent-run-events))})

(fn AgentSessionNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "AgentSessionNode requires store"))
  (local run-id (assert options.run-id "AgentSessionNode requires run-id"))
  (local session (assert (project-session store run-id)
                         "AgentSessionNode requires existing workflow run"))
  (assert (session? session) (.. "AgentSessionNode requires an agent session run: " run-id))
  (local node (GraphNode {:key (.. "agent-session:" run-id)
                          :label (session-label session run-id)
                          :color SESSION_BLUE
                          :sub-color SESSION_BLUE_ACCENT
                          :preview AgentSessionNodePreview
                          :size 8.0}))
  (set node.workflow-store store)
  (set node.workflow-run-id run-id)
  (set node.agent-session session)
  (set node.current-session (fn [self] (current-session self)))
  (set node.load-backing-workflow-run
       (fn [self]
         (current-session self)
         (local graph (require-graph-map self "AgentSessionNode.load-backing-workflow-run"))
         (local run-node (load-key graph (workflow-run-key self.workflow-run-id)
                                   "AgentSessionNode.load-backing-workflow-run"))
         (add-visible-edge graph self run-node "workflow run")
         run-node))
  (set node.load-recent-run-events
       (fn [self]
         (current-session self)
         (local graph (require-graph-map self "AgentSessionNode.load-recent-run-events"))
         (local loaded [])
         (each [_ event (ipairs (self.workflow-store:list-events self.workflow-run-id))]
           (local event-node (load-key graph (workflow-event-key self.workflow-run-id event.id)
                                      "AgentSessionNode.load-recent-run-events"))
           (add-visible-edge graph self event-node "event")
           (table.insert loaded event-node))
         loaded))
  (set node.actions [(open-run-action node) (show-events-action node)])
  (set node.item-count item-count)
  node)

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (assert options.store "agent-session.register-loader requires store"))
  (graph:register-key-loader "agent-session"
    (fn [key]
      (local prefix "agent-session:")
      (when (= (string.sub key 1 (string.len prefix)) prefix)
        (local run-id (string.sub key (+ 1 (string.len prefix))))
        (when (> (string.len run-id) 0)
          (local session (project-session store run-id))
          (when (session? session)
            (AgentSessionNode {:store store :run-id run-id})))))))

{:AgentSessionNode AgentSessionNode
 :item-count item-count
 :session? session?
 :register-loader register-loader}
