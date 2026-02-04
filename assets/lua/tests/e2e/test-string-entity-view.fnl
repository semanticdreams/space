(local Harness (require :tests.e2e.harness))
(local Dialog (require :dialog))
(local Sized (require :sized))
(local {:StringEntityNode StringEntityNode} (require :graph/nodes/string-entity))
(local StringEntityNodeView (require :graph/view/views/string-entity))
(local StringEntityStore (require :entities/string))
(local fs (require :fs))
(local glm (require :glm))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "e2e-string-entity"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "e2e-" (os.time) "-" temp-counter)))

(fn with-temp-store [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local store (StringEntityStore.StringEntityStore {:base-dir dir}))
  (local (ok result) (pcall f store dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn run [ctx]
  (with-temp-store
    (fn [store _dir]
      (local entity (store:create-entity {:value "Hello, this is a test string entity.\nIt has multiple lines.\nLine three here."}))
      (local node (StringEntityNode {:entity-id entity.id
                                     :store store}))
      (local view-builder (StringEntityNodeView node))
      (local dialog-builder
        (Dialog {:title (or node.label "String Entity")
                 :child (fn [child-ctx]
                          (view-builder child-ctx))}))
      (local sized
        (Sized {:size (glm.vec3 28 18 0)
                :child (fn [child-ctx]
                         (dialog-builder child-ctx))}))
      (local target
        (Harness.make-screen-target {:width ctx.width
                                     :height ctx.height
                                     :world-units-per-pixel ctx.units-per-pixel
                                     :builder (fn [child-ctx]
                                                (sized child-ctx))}))
      (Harness.draw-targets ctx.width ctx.height [{:target target}])
      (Harness.capture-snapshot {:name "string-entity-view"
                                 :width ctx.width
                                 :height ctx.height
                                 :tolerance 3})
      (Harness.cleanup-target target))))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E string entity view snapshot complete"))

{:run run
 :main main}
