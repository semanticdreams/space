(local Harness (require :tests.e2e.harness))
(local Dialog (require :dialog))
(local Sized (require :sized))
(local LlmMessageNode (require :graph/nodes/llm-message))
(local LlmMessageView (require :graph/view/views/llm-message))
(local glm (require :glm))

(fn run [ctx]
  (local node
    (LlmMessageNode {:role "assistant"
                     :name "space-bot"
                     :content "Here is a summary of the latest changes.\n- List view now scrolls at the dialog level.\n- Snapshots updated.\n- Tests green."
                     :tool-name "summarize"
                     :tool-call-id "call_123"}))
  (local view-builder (LlmMessageView node))
  (local dialog-builder
    (Dialog {:title "LLM Message"
             :child (fn [child-ctx]
                      (view-builder child-ctx))}))
  (local sized
    (Sized {:size (glm.vec3 28 16 0)
            :child (fn [child-ctx]
                     (dialog-builder child-ctx))}))
  (local target
    (Harness.make-screen-target {:width ctx.width
                                 :height ctx.height
                                 :world-units-per-pixel ctx.units-per-pixel
                                 :builder (fn [child-ctx]
                                            (sized child-ctx))}))
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (Harness.capture-snapshot {:name "llm-message-dialog"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 3})
  (Harness.cleanup-target target))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E llm message dialog snapshot complete"))

{:run run
 :main main}
