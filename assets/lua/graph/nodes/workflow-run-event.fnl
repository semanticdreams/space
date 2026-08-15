(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local WorkflowRunEventNodePreview (require :graph/view/previews/workflow-run-event))

(local EVENT_ORANGE (glm.vec4 0.85 0.45 0.15 1))
(local EVENT_ORANGE_ACCENT (glm.vec4 0.95 0.56 0.22 1))

(fn split-key-parts [text]
  (assert text "split-key-parts requires text")
  (local parts [])
  (each [part (string.gmatch text "[^:]+")]
    (table.insert parts part))
  parts)

(fn find-event [store run-id event-id]
  (var found nil)
  (local run (store:get-run run-id))
  (when run
    (each [_ event (ipairs run.events)]
      (when (= event.id event-id)
        (set found event))))
  found)

(fn resolve-node [graph key]
  (var node nil)
  (when (and graph key graph.lookup)
    (set node (graph:lookup key)))
  (when (and (= node nil) graph key graph.create-node-by-key)
    (set node (graph:create-node-by-key key)))
  (when (and (= node nil) graph key graph.load-by-key)
    (set node (graph:load-by-key key)))
  node)

(fn event-key [run-id event-id]
  (.. "workflow-run-event:" run-id ":" event-id))

(fn event-step-edge [source graph run-id event]
  (when (and event event.step-id)
    (local target (resolve-node graph (.. "workflow-run-step:" run-id ":" event.step-id)))
    (when target
      (GraphEdge {:source source :target target :label "step"}))))

(fn WorkflowRunEventNode [opts]
  (local options (or opts {}))
  (local store (assert options.store "WorkflowRunEventNode requires store"))
  (local run-id (assert options.run-id "WorkflowRunEventNode requires run-id"))
  (local event-id (assert options.event-id "WorkflowRunEventNode requires event-id"))
  (local event (find-event store run-id event-id))
  (local node (GraphNode {:key (event-key run-id event-id)
                          :label (.. "Event " (tostring (or (and event event.kind) event-id)))
                          :color EVENT_ORANGE
                          :sub-color EVENT_ORANGE_ACCENT
                          :preview WorkflowRunEventNodePreview
                          :size 6.5}))
  (set node.workflow-run-id run-id)
  (set node.workflow-event-id event-id)
  (set node.workflow-store store)
  (set node.get-edges
       (fn [self]
         (local edges [])
         (local event-current (find-event self.workflow-store self.workflow-run-id self.workflow-event-id))
         (local edge (event-step-edge self self.graph self.workflow-run-id event-current))
         (when edge
           (table.insert edges edge))
         edges))
  node)

(fn parse-key [key]
  (local prefix "workflow-run-event:")
  (when (= (string.sub key 1 (string.len prefix)) prefix)
    (local parts (split-key-parts (string.sub key (+ 1 (string.len prefix)))))
    (when (= (length parts) 2)
      (values (. parts 1) (. parts 2)))))

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (assert options.store "workflow-run-event.register-loader requires store"))
  (graph:register-key-loader "workflow-run-event"
    (fn [key]
      (local (run-id event-id) (parse-key key))
      (when (and run-id event-id (find-event store run-id event-id))
        (WorkflowRunEventNode {:run-id run-id :event-id event-id :store store})))))

{:WorkflowRunEventNode WorkflowRunEventNode
 :find-event find-event
 :parse-key parse-key
 :register-loader register-loader}
