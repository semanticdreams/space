(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local GraphViewPersistence (require :graph/view/persistence))
(local tests [])

(local temp-root "/tmp/space/tests/graph-view-camera-persistence")

(fn reset-dir []
  (when (fs.exists temp-root)
    (fs.remove-all temp-root))
  (fs.create-dirs temp-root)
  temp-root)

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

(table.insert tests {:name "camera state saves loads and preserves metadata"
                     :fn camera-state-saves-loads-and-preserves-metadata})
(table.insert tests {:name "malformed camera state fails loudly"
                     :fn malformed-camera-state-fails-loudly})
(table.insert tests {:name "malformed false camera state fails loudly"
                     :fn malformed-false-camera-state-fails-loudly})
(table.insert tests {:name "malformed false camera rotation fails loudly"
                     :fn malformed-false-camera-rotation-fails-loudly})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-view-camera-persistence"
                       :tests tests})))

{:name "graph-view-camera-persistence"
 :tests tests
 :main main}
