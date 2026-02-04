(local Harness (require :tests.e2e.harness))
(local Dialog (require :dialog))
(local Sized (require :sized))
(local {:LinkEntityNode LinkEntityNode} (require :graph/nodes/link-entity))
(local LinkEntityNodeView (require :graph/view/views/link-entity))
(local LinkEntityStore (require :entities/link))
(local fs (require :fs))
(local glm (require :glm))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "e2e-link-entity"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "e2e-" (os.time) "-" temp-counter)))

(fn with-temp-store [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
  (local (ok result) (pcall f store dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn run [ctx]
  (with-temp-store
    (fn [store _dir]
      (local entity (store:create-entity {:source-key "start"
                                          :target-key "conversation-123"
                                          :metadata {:created-by "user"
                                                     :type "navigation"}}))
      (local node (LinkEntityNode {:entity-id entity.id
                                   :store store}))
      (local view-builder (LinkEntityNodeView node))
      (local dialog-builder
        (Dialog {:title (or node.label "Link Entity")
                 :child (fn [child-ctx]
                          (view-builder child-ctx))}))
      (local sized
        (Sized {:size (glm.vec3 30 20 0)
                :child (fn [child-ctx]
                         (dialog-builder child-ctx))}))
      (local target
        (Harness.make-screen-target {:width ctx.width
                                     :height ctx.height
                                     :world-units-per-pixel ctx.units-per-pixel
                                     :builder (fn [child-ctx]
                                                (sized child-ctx))}))
      (Harness.draw-targets ctx.width ctx.height [{:target target}])
      (Harness.capture-snapshot {:name "link-entity-view"
                                 :width ctx.width
                                 :height ctx.height
                                 :tolerance 3})
      (Harness.cleanup-target target))))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E link entity view snapshot complete"))

{:run run
 :main main}
