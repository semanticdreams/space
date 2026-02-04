(local Harness (require :tests.e2e.harness))
(local LlmChatView (require :llm-chat-view))
(local LlmStore (require :llm/store))
(local Sized (require :sized))
(local glm (require :glm))
(local fs (require :fs))

(fn run [ctx]
  (local base-dir "/tmp/space/tests/llm-chat-e2e")
  (when (fs.exists base-dir)
    (fs.remove-all base-dir))
  (fs.create-dirs base-dir)
  (local store (LlmStore.Store {:base-dir base-dir}))
  (local conversation
    (store:create-conversation {:name "Design Sync"
                                :model "gpt-4o-mini"
                                :temperature 0.6}))
  (store:set-active-conversation-id conversation.id)
  (store:add-message conversation.id {:role "user"
                                      :content "Can you summarize today's changes?"})
  (store:add-message conversation.id {:role "assistant"
                                      :content "Themes are in; status panel and skybox are updated."})
  (local view-builder (LlmChatView {:store store
                                    :title "LLM Chat"}))
  (local sized
    (Sized {:size (glm.vec3 48 26 0)
            :child (fn [child-ctx]
                     (view-builder child-ctx))}))
  (local target
    (Harness.make-screen-target {:width 960
                                 :height 540
                                 :world-units-per-pixel ctx.units-per-pixel
                                 :builder (fn [child-ctx]
                                            (sized child-ctx))}))
  (Harness.draw-targets 960 540 [{:target target}])
  (Harness.capture-snapshot {:name "llm-chat-view"
                             :width 960
                             :height 540
                             :tolerance 3})
  (Harness.cleanup-target target))

(fn main []
  (Harness.with-app {:width 960
                     :height 540}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E llm chat view snapshot complete"))

{:run run
 :main main}
