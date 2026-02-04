(local Harness (require :tests.e2e.harness))
(local Dialog (require :dialog))
(local Sized (require :sized))
(local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
(local ListEntityNodeView (require :graph/view/views/list-entity))
(local ListEntityStore (require :entities/list))
(local fs (require :fs))
(local glm (require :glm))

(fn snapshot-update-allowed? [name]
  (local targets (os.getenv "SPACE_SNAPSHOT_UPDATE"))
  (if (not targets)
      false
      (let [names {}]
        (each [entry (string.gmatch targets "[^,]+")]
          (local trimmed (string.gsub entry "^%s*(.-)%s*$" "%1"))
          (when (> (length trimmed) 0)
            (set (. names trimmed) true)))
        (or (not (= (. names "all") nil))
            (not (= (. names name) nil))))))

(fn snapshot-golden-path [name]
  (local base (assert (os.getenv "SPACE_ASSETS_PATH")
                      "SPACE_ASSETS_PATH is required for list entity snapshots"))
  (fs.join-path base "lua/tests/data/snapshots" (.. name ".png")))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "e2e-list-entity"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "e2e-" (os.time) "-" temp-counter)))

(fn with-temp-store [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local store (ListEntityStore.ListEntityStore {:base-dir dir}))
  (local (ok result) (pcall f store dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn run [ctx]
  (with-temp-store
    (fn [store _dir]
      (local entity (store:create-entity {:name "My List"
                                          :items ["node-key-alpha"
                                                  "node-key-beta"
                                                  "node-key-gamma"]}))
      (local node (ListEntityNode {:entity-id entity.id
                                   :store store}))
      (local view-builder (ListEntityNodeView node))
      (local dialog-builder
        (Dialog {:title (or node.label "List Entity")
                 :child (fn [child-ctx]
                          (view-builder child-ctx))}))
      (local sized
        (Sized {:size (glm.vec3 30 22 0)
                :child (fn [child-ctx]
                         (dialog-builder child-ctx))}))
      (local target
        (Harness.make-screen-target {:width ctx.width
                                     :height ctx.height
                                     :world-units-per-pixel ctx.units-per-pixel
                                     :builder (fn [child-ctx]
                                                (sized child-ctx))}))
      (Harness.draw-targets ctx.width ctx.height [{:target target}])
      (local golden (snapshot-golden-path "list-entity-view"))
      (if (or (snapshot-update-allowed? "list-entity-view")
              (fs.exists golden))
          (Harness.capture-snapshot {:name "list-entity-view"
                                     :width ctx.width
                                     :height ctx.height
                                     :tolerance 3})
          (print (.. "[snapshot] skipping list-entity-view (missing golden " golden ")")))
      (Harness.cleanup-target target))))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E list entity view snapshot complete"))

{:run run
 :main main}
