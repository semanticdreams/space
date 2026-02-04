(local Harness (require :tests.e2e.harness))
(local Dialog (require :dialog))
(local Sized (require :sized))
(local LlmConversationNode (require :graph/nodes/llm-conversation))
(local LlmConversationView (require :graph/view/views/llm-conversation))
(local glm (require :glm))

(fn run [ctx]
  (local node
    (LlmConversationNode {:name "Support chat"
                          :model "gpt-4o-mini"}))
  (local view-builder (LlmConversationView node))
  (local dialog-builder
    (Dialog {:title "LLM Conversation"
             :child (fn [child-ctx]
                      (view-builder child-ctx))}))
  (local sized
    (Sized {:size (glm.vec3 30 16 0)
            :child (fn [child-ctx]
                     (dialog-builder child-ctx))}))
  (local target
    (Harness.make-screen-target {:width ctx.width
                                 :height ctx.height
                                 :world-units-per-pixel ctx.units-per-pixel
                                 :builder (fn [child-ctx]
                                            (sized child-ctx))}))
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (Harness.capture-snapshot {:name "llm-conversation-dialog"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 3})
  (Harness.cleanup-target target))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E llm conversation dialog snapshot complete"))

{:run run
 :main main}
