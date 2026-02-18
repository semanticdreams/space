(local Harness (require :tests.e2e.harness))
(local Dialog (require :dialog))
(local Sized (require :sized))
(local Graph (require :graph/init))
(local {:register-loader register-string-entity-loader} (require :graph/nodes/string-entity))
(local {:NotebookNode NotebookNode} (require :graph/nodes/notebook))
(local NotebookNodeView (require :graph/view/views/notebook))
(local StringEntityStore (require :entities/string))
(local NotebookStore (require :notebooks/store))
(local fs (require :fs))
(local glm (require :glm))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "e2e-notebook"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "e2e-" (os.time) "-" temp-counter)))

(fn with-temp-stores [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")}))
  (local notebook-store (NotebookStore.NotebookStore {:base-dir (fs.join-path dir "notebooks")}))
  (local (ok result) (pcall f {:root dir
                               :string-store string-store
                               :notebook-store notebook-store}))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn run [ctx]
  (with-temp-stores
    (fn [deps]
      (local graph (Graph {:with-start false}))
      (register-string-entity-loader graph {:store deps.string-store})

      (local s1 (deps.string-store:create-entity {:value "Patient summary: stable vitals"}))
      (local s2 (deps.string-store:create-entity {:value "Plan: follow-up labs tomorrow"}))
      (local notebook (deps.notebook-store:create-notebook
                        {:name "Rounds Notes"
                         :items [(.. "string-entity:" s1.id)
                                 (.. "string-entity:" s2.id)]}))
      (local node (NotebookNode {:notebook-id notebook.id
                                 :store deps.notebook-store}))
      (graph:add-node node {})

      (local view-builder (NotebookNodeView node))
      (local dialog-builder
        (Dialog {:title (or node.label "Notebook")
                 :child (fn [child-ctx]
                          (view-builder child-ctx))}))
      (local sized
        (Sized {:size (glm.vec3 34 24 0)
                :child (fn [child-ctx]
                         (dialog-builder child-ctx))}))
      (local target
        (Harness.make-screen-target {:width ctx.width
                                     :height ctx.height
                                     :world-units-per-pixel ctx.units-per-pixel
                                     :builder (fn [child-ctx]
                                                (sized child-ctx))}))

      (Harness.draw-targets ctx.width ctx.height [{:target target}])
      (Harness.capture-snapshot {:name "notebook-view"
                                 :width ctx.width
                                 :height ctx.height
                                 :tolerance 3})

      (Harness.cleanup-target target)
      (graph:drop))))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E notebook view snapshot complete"))

{:run run
 :main main}
