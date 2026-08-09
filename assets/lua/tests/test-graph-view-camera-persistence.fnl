(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphView (require :graph/view))
(local GraphViewPersistence (require :graph/view/persistence))
(local BuildContext (require :build-context))
(local Camera (require :camera))
(local Clickables (require :clickables))
(local {: FocusManager} (require :focus))
(local tests [])

(local temp-root "/tmp/space/tests/graph-view-camera-persistence")

(fn reset-dir []
  (when (fs.exists temp-root)
    (fs.remove-all temp-root))
  (fs.create-dirs temp-root)
  temp-root)

(fn test-theme []
  {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)
           :label-color (glm.vec4 1 1 1 1)
           :label-target-pixels 13.0
           :label-min-scale 4.0
           :edge-color (glm.vec4 0.6 0.6 0.6 1)}
   :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}})

(fn make-view-fixture [dir]
  (local focus-manager (FocusManager {:root-name "graph-camera-persistence"}))
  (local focus-scope (focus-manager:create-scope {:name "graph-camera-persistence-scope"}))
  (local ctx (BuildContext {:clickables (Clickables)
                            :theme (test-theme)
                            :focus-manager focus-manager
                            :focus-scope focus-scope}))
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local graph (Graph {:with-start false}))
  (local view (GraphView {:graph-map graph
                          :ctx ctx
                          :camera camera
                          :data-dir dir}))
  {:camera camera
   :focus-manager focus-manager
   :graph-map graph
   :view view})

(fn drop-view-fixture! [fixture]
  (when fixture.view (fixture.view:drop))
  (when fixture.graph-map (fixture.graph-map:drop))
  (when fixture.camera (fixture.camera:drop))
  (when fixture.focus-manager (fixture.focus-manager:drop)))

(fn camera-state-saves-loads-and-preserves-metadata []
  (local dir (reset-dir))
  (local persistence (GraphViewPersistence {:data-dir dir :map-id "main"}))
  (persistence:set-size {:key "node-a"} {:x 12 :y 8})
  (persistence:set-camera-state {:position [11 22 33] :rotation [1 0 0 0]})
  (persistence:persist {} true)
  (local decoded (json.loads (fs.read-file persistence.metadata-path)))
  (assert (= (. decoded.camera.position 1) 11)
          "camera position x should persist")
  (assert (= (. decoded.camera.position 2) 22)
          "camera position y should persist")
  (assert (= (. decoded.camera.position 3) 33)
          "camera position z should persist")
  (assert decoded.sizes.node-a
          "camera persistence should preserve existing size metadata")
  (local reloaded (GraphViewPersistence {:data-dir dir :map-id "main"}))
  (local camera-state (reloaded:saved-camera-state))
  (assert (= (. camera-state.position 1) 11)
          "saved-camera-state should return persisted position x")
  (assert (= (. camera-state.rotation 1) 1)
          "saved-camera-state should return persisted rotation w"))

(fn malformed-camera-state-fails-loudly []
  (local dir (reset-dir))
  (local persistence (GraphViewPersistence {:data-dir dir :map-id "main"}))
  (fs.create-dirs (fs.join-path dir "graph" "maps" "main"))
  (JsonUtils.write-json! persistence.metadata-path {:camera {:position ["bad" 2 3]}})
  (local (ok err) (pcall (fn [] (GraphViewPersistence {:data-dir dir :map-id "main"}))))
  (assert (not ok) "malformed camera metadata should fail")
  (assert (string.find (tostring err) "GraphViewPersistence" 1 true)
          "camera error should name GraphViewPersistence")
  (assert (string.find (tostring err) "main" 1 true)
          "camera error should name map id")
  (assert (string.find (tostring err) "camera" 1 true)
          "camera error should name camera field"))

(fn malformed-false-camera-state-fails-loudly []
  (local dir (reset-dir))
  (local persistence (GraphViewPersistence {:data-dir dir :map-id "main"}))
  (fs.create-dirs (fs.join-path dir "graph" "maps" "main"))
  (JsonUtils.write-json! persistence.metadata-path {:camera false})
  (local (ok err) (pcall (fn [] (GraphViewPersistence {:data-dir dir :map-id "main"}))))
  (assert (not ok) "false camera metadata should fail")
  (assert (string.find (tostring err) "GraphViewPersistence" 1 true)
          "false camera error should name GraphViewPersistence")
  (assert (string.find (tostring err) "main" 1 true)
          "false camera error should name map id")
  (assert (string.find (tostring err) "camera" 1 true)
          "false camera error should name camera field"))

(fn malformed-false-camera-rotation-fails-loudly []
  (local dir (reset-dir))
  (local persistence (GraphViewPersistence {:data-dir dir :map-id "main"}))
  (fs.create-dirs (fs.join-path dir "graph" "maps" "main"))
  (JsonUtils.write-json! persistence.metadata-path {:camera {:position [1 2 3]
                                                     :rotation false}})
  (local (ok err) (pcall (fn [] (GraphViewPersistence {:data-dir dir :map-id "main"}))))
  (assert (not ok) "false camera rotation metadata should fail")
  (assert (string.find (tostring err) "GraphViewPersistence" 1 true)
          "false rotation error should name GraphViewPersistence")
  (assert (string.find (tostring err) "main" 1 true)
          "false rotation error should name map id")
  (assert (string.find (tostring err) "camera" 1 true)
          "false rotation error should name camera field"))

(fn no-saved-camera-existing-node-centers-node []
  (local dir (reset-dir))
  (local fixture (make-view-fixture dir))
  (local node (Graph.GraphNode {:key "existing"}))
  (fixture.graph-map:add-node node {:position (glm.vec3 123 456 0)})
  (fixture.view:apply-initial-camera-policy!)
  (assert (= fixture.camera.position.x 123)
          "initial camera policy should center existing node x")
  (assert (= fixture.camera.position.y 456)
          "initial camera policy should center existing node y")
  (drop-view-fixture! fixture))

(fn no-saved-camera-prefers-mounted-start-node []
  (local dir (reset-dir))
  (local fixture (make-view-fixture dir))
  (local other (Graph.GraphNode {:key "other"}))
  (local start (Graph.GraphNode {:key "start"}))
  (fixture.graph-map:add-node other {:position (glm.vec3 900 800 0)})
  (fixture.graph-map:add-node start {:position (glm.vec3 12 34 0)})
  (fixture.view:apply-initial-camera-policy!)
  (assert (= fixture.camera.position.x 12)
          "initial camera policy should prefer mounted start node x")
  (assert (= fixture.camera.position.y 34)
          "initial camera policy should prefer mounted start node y")
  (drop-view-fixture! fixture))

(fn no-saved-camera-empty-map-centers-first-added-node-once []
  (local dir (reset-dir))
  (local fixture (make-view-fixture dir))
  (fixture.view:apply-initial-camera-policy!)
  (assert (= fixture.camera.position.x 0)
          "empty map should start from default camera x before first node")
  (assert (= fixture.camera.position.y 0)
          "empty map should start from default camera y before first node")
  (local first (Graph.GraphNode {:key "first"}))
  (fixture.graph-map:add-node first {:position (glm.vec3 20 30 0)})
  (assert (= fixture.camera.position.x 20)
          "first added node should consume pending initial center x")
  (assert (= fixture.camera.position.y 30)
          "first added node should consume pending initial center y")
  (local second (Graph.GraphNode {:key "second"}))
  (fixture.graph-map:add-node second {:position (glm.vec3 500 600 0)})
  (assert (= fixture.camera.position.x 20)
          "second added node should not recenter x")
  (assert (= fixture.camera.position.y 30)
          "second added node should not recenter y")
  (drop-view-fixture! fixture))

(table.insert tests {:name "camera state saves loads and preserves metadata"
                     :fn camera-state-saves-loads-and-preserves-metadata})
(table.insert tests {:name "malformed camera state fails loudly"
                     :fn malformed-camera-state-fails-loudly})
(table.insert tests {:name "malformed false camera state fails loudly"
                     :fn malformed-false-camera-state-fails-loudly})
(table.insert tests {:name "malformed false camera rotation fails loudly"
                      :fn malformed-false-camera-rotation-fails-loudly})
(table.insert tests {:name "no saved camera existing node centers node"
                     :fn no-saved-camera-existing-node-centers-node})
(table.insert tests {:name "no saved camera prefers mounted start node"
                     :fn no-saved-camera-prefers-mounted-start-node})
(table.insert tests {:name "no saved camera empty map centers first added node once"
                     :fn no-saved-camera-empty-map-centers-first-added-node-once})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-view-camera-persistence"
                       :tests tests})))

{:name "graph-view-camera-persistence"
 :tests tests
 :main main}
