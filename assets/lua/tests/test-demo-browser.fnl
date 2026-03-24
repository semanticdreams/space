(local glm (require :glm))
(local Scene (require :scene))
(local Camera (require :camera))
(local BuildContext (require :build-context))
(local Hud (require :hud))
(local Graph (require :graph/init))
(local DemoDialogs (require :demo-dialogs))
(local HeightfieldTargetCapture (require :graph/view/heightfield-target-capture))
(local HeightfieldPaintCapture (require :graph/view/heightfield-paint-capture))
(local States (require :states))
(local TerrainRectPickState (require :terrain-rect-pick-state))
(local TerrainPaintManager (require :graph/view/terrain-paint-manager))
(local TerrainPaintState (require :terrain-paint-state))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))
(local bt (require :bt))
(local fs (require :fs))
(local json (require :json))
(local HeightfieldTerrainData (require :heightfield-terrain-data))
(local TerrainQuery (require :terrain-query))
(local HeightfieldTerrainQuery (require :heightfield-terrain-query))

(local tests [])

(local approx (. MathUtils :approx))

(fn vec3-approx= [a b]
  (and (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn find-close-button [element]
  (local dialog (or element.front element.__front_widget element.child element))
  (local titlebar-meta (. dialog.children 1))
  (local titlebar titlebar-meta.element)
  (local title-flex (. titlebar.children 2))
  (local action-row-meta (. title-flex.children (length title-flex.children)))
  (local action-row action-row-meta.element)
  (local close-meta (. action-row.children (length action-row.children)))
  close-meta.element)

(fn make-icons-stub []
  (local stub {:font {:glyph-map {65533 {:advance 1.0}}
                      :metadata {:metrics {:lineHeight 1.0
                                           :ascender 0.5
                                           :descender -0.5}
                                 :atlas {:width 1
                                         :height 1}}}})
  (set stub.get
       (fn [_self _name]
         4242))
  (set stub.resolve
       (fn [self name]
         (local code (self:get name))
         {:type :font
          :codepoint code
          :font self.font}))
  stub)

(fn make-stub-movables []
  (local registered [])
  (local movables {:registered registered :unregistered []})
  (set movables.register
       (fn [self widget opts]
         (table.insert self.registered {:widget widget
                                        :opts opts})))
  (set movables.unregister
       (fn [self key]
         (table.insert self.unregistered key)))
  movables)

(fn read-json [path]
  (json.loads (fs.read-file path)))

(fn array->vec3 [arr]
  (glm.vec3 (. arr 1) (. arr 2) (. arr 3)))

(fn array->quat [arr]
  (glm.quat (. arr 1) (. arr 2) (. arr 3) (. arr 4)))

(fn random-range [min-value max-value]
  (+ min-value (* (math.random) (- max-value min-value))))

(fn setup-scene [opts]
  (local options (or opts {}))
  (local original-scene app.scene)
  (local original-layout-root app.layout-root)
  (local original-movables app.movables)
  (local original-camera app.camera)
  (local original-hud app.hud)
  (var scene nil)
  (var movables nil)
  (var hud nil)
  (local icons (make-icons-stub))

  (fn cleanup []
    (when scene
      (scene:drop)
      (set scene nil))
    (set app.scene original-scene)
    (set app.layout-root original-layout-root)
    (set app.movables original-movables)
    (set app.camera original-camera)
    (set app.hud original-hud))

  (let [(ok payload)
        (pcall (fn []
                 (set movables (make-stub-movables))
                 (set scene (Scene {:icons icons
                                    :position (or options.scene-position nil)
                                    :rotation (or options.scene-rotation nil)}))
                 (set hud {:world-units-per-pixel 1})
                 (set hud.build-context (BuildContext {:pointer-target hud}))
                 (set hud.on-viewport-changed (fn [_self _viewport] nil))
                 (set app.scene scene)
                 (set app.hud hud)
                 (set app.layout-root scene.layout-root)
                 (set app.movables movables)
                 (when options.camera
                   (set app.camera options.camera))
                 (scene:build-default)
                 {:scene scene :movables movables :icons icons :hud hud}))]
    (if ok
        {:cleanup cleanup :scene-result payload}
        (do
          (cleanup)
          (error payload)))))

(fn random-flat-heights [width depth]
  (local heights [])
  (for [_ 1 (* width depth)]
    (table.insert heights 0.0))
  heights)

(fn random-heightfield-record [seed]
  (math.randomseed seed)
  (local chunk-width 5)
  (local chunk-length 5)
  (local min-chunk-x (- (math.random 0 1)))
  (local max-chunk-x (+ min-chunk-x (math.random 0 2)))
  (local min-chunk-z (- (math.random 0 1)))
  (local max-chunk-z (+ min-chunk-z (math.random 0 2)))
  (local chunks [])
  (for [chunk-z min-chunk-z max-chunk-z]
    (for [chunk-x min-chunk-x max-chunk-x]
      (table.insert chunks
        {:coord [chunk-x chunk-z]
         :size [chunk-width chunk-length]
         :heights (random-flat-heights chunk-width chunk-length)})))
  (local yaw (random-range (- math.pi) math.pi))
  (local half-angle (/ yaw 2))
  {:id "terrain-a"
   :kind "heightfield-terrain"
   :options {:position [(random-range -10 10) 0 (random-range -10 10)]
             :rotation [(math.cos half-angle) 0 (math.sin half-angle) 0]
             :sample-spacing [(random-range 0.75 3.5) (random-range 0.75 3.5)]
             :chunk-samples [chunk-width chunk-length]
             :default-height 0.0}
   :chunks chunks})

(fn camera-looking-at [position target]
  (local direction (glm.normalize (- target position)))
  (local yaw (math.atan direction.x (- direction.z)))
  (local horizontal (math.sqrt (+ (* direction.x direction.x)
                                  (* direction.z direction.z))))
  (local pitch (- (math.atan direction.y horizontal)))
  (Camera {:position position
           :rotation (glm.quat (glm.vec3 pitch yaw 0))}))

(fn translated-query-record [metadata]
  (local record metadata.record)
  (local layout metadata.element.layout)
  (local bounds (HeightfieldTerrainData.sample-bounds record))
  (local spacing (or (and record.options record.options.sample-spacing) [20 20]))
  (local spacing-x (or (. spacing 1) spacing.x 20))
  (local spacing-z (or (. spacing 2) spacing.y spacing.z 20))
  (local canonical-origin-offset
    (glm.vec3 (* bounds.min-sample-x spacing-x)
              0
              (* bounds.min-sample-z spacing-z)))
  (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
  (local canonical-position
    (- layout.position (rotation:rotate canonical-origin-offset)))
  {:id record.id
   :kind record.kind
   :options {:position [canonical-position.x canonical-position.y canonical-position.z]
             :rotation [rotation.w rotation.x rotation.y rotation.z]
             :sample-spacing record.options.sample-spacing
             :chunk-samples record.options.chunk-samples
             :default-height record.options.default-height}
   :chunks record.chunks})

(fn oracle-scene-domain-hit [scene pos opts]
  (local ray (scene:screen-pos-ray pos opts))
  (var best nil)
  (each [_ metadata (ipairs (or scene.scene-terrains []))]
    (local record metadata.record)
    (local query-record (translated-query-record metadata))
    (local hit (and query-record (HeightfieldTerrainQuery.raycast-record-exact query-record ray)))
    (when (and hit (or (not best) (< hit.distance best.distance)))
      (set best {:terrain-record record
                 :terrain-id record.id
                 :terrain-kind record.kind
                 :distance hit.distance
                 :world-point hit.world-point
                 :local-point hit.local-point
                 :sample hit.sample
                 :target hit.target})))
  best)

(fn oracle-scene-domain-hit-fast [scene pos opts]
  (local ray (scene:screen-pos-ray pos opts))
  (var best nil)
  (each [_ metadata (ipairs (or scene.scene-terrains []))]
    (local record metadata.record)
    (local query-record (translated-query-record metadata))
    (local hit (and query-record (HeightfieldTerrainQuery.raycast-record-fast query-record ray)))
    (when (and hit (or (not best) (< hit.distance best.distance)))
      (set best {:terrain-record record
                 :terrain-id record.id
                 :terrain-kind record.kind
                 :distance hit.distance
                 :world-point hit.world-point
                 :local-point hit.local-point
                 :sample hit.sample
                 :target hit.target})))
  best)

(fn scene-hit-approx=? [left right]
  (if (or (not left) (not right))
      (= left right)
      (and (= left.terrain-id right.terrain-id)
           (approx left.distance right.distance {:epsilon 1e-3})
           (= left.sample.x right.sample.x)
           (= left.sample.z right.sample.z)
           (= left.target.x0 right.target.x0)
           (= left.target.z0 right.target.z0)
           (= left.target.x1 right.target.x1)
           (= left.target.z1 right.target.z1))))

(fn terrain-hit-approx=? [left right]
  (if (or (not left) (not right))
      (= left right)
      (and (approx left.distance right.distance {:epsilon 1e-3})
           (= left.sample.x right.sample.x)
           (= left.sample.z right.sample.z)
           (= left.target.x0 right.target.x0)
           (= left.target.z0 right.target.z0)
           (= left.target.x1 right.target.x1)
           (= left.target.z1 right.target.z1))))

(fn demo-browser-adds-dialogs-to-scene []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local movables setup.scene-result.movables)

  (let [(ok err)
        (pcall (fn []
                 (scene:add-demo-browser)
                 (assert (= (length scene.scene-children) 1)
                         "Browser should add itself to the scene container")
                 (local entry (DemoDialogs.find-entry :welcome-dialog))
                 (scene:add-demo-entry entry)
                 (assert (= (length scene.scene-children) 2)
                         "Scene should contain browser and the opened dialog")
                 (assert (>= (length scene.entity.__scene_movable_keys) 2)
                         "Movables should track added scene children")
                 (assert (>= (length movables.registered) 2)
                         "Movables register should record registrations for positioned children")))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn closing-demo-dialog-removes-positioned-child []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local movables setup.scene-result.movables)

  (let [(ok err)
        (pcall (fn []
                 (scene:add-demo-browser)
                 (local entry (DemoDialogs.find-entry :welcome-dialog))
                 (local element (scene:add-demo-entry entry))
                 (assert element "Expected demo entry to be created")
                 (local close-button (find-close-button element))
                 (assert (= close-button.icon "close"))
                 (close-button:on-click {:button 1})
                 (assert (= (length scene.scene-children) 1)
                         "Closing dialog should remove the positioned child")
                 (assert (>= (length scene.entity.__scene_movable_keys) 1)
                         "Movables should track remaining scene children after closing")
                 (assert (>= (length movables.unregistered) 1)
                         "Closing dialog should unregister removed movable entries")))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn demo-browser-capture-and-restore-roundtrip []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (let [(ok err)
        (pcall
          (fn []
            (local browser (scene:add-demo-browser))
            (assert browser "Expected demo browser element")
            (local captured (scene:capture-state))
            (local panels (or captured.panels []))
            (assert (= (length panels) 1)
                    "Expected one persisted scene panel for demo browser")
            (local panel (. panels 1))
            (assert (= panel.kind "demo-browser")
                    "Demo browser persistence kind should be demo-browser")

            (scene:remove-panel-child browser)
            (assert (= (length scene.scene-children) 0)
                    "Expected demo browser removal before restore")

            (scene:restore-state captured)
            (assert (= (length scene.scene-children) 1)
                    "Demo browser should restore from captured scene state")
            (assert scene.demo-browser
                    "Scene.demo-browser handle should be re-established after restore")))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn scene-capture-state-includes-default-terrain []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local (ok err)
    (pcall
      (fn []
        (local captured (scene:capture-state))
        (local terrains (or captured.terrains []))
        (assert (= (length terrains) 1)
                "Expected one default terrain in captured scene state")
        (local terrain (. terrains 1))
        (assert (= terrain.kind "heightfield-terrain")
                "Expected default terrain kind heightfield-terrain")
        (assert terrain.id "Expected captured terrain id"))))
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-build-default-preserves-explicit-empty-terrains []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local (ok err)
    (pcall
      (fn []
        (scene:build-default {:terrains []})
        (local captured (scene:capture-state))
        (local terrains (or captured.terrains []))
        (assert (= (length terrains) 0)
                "Explicit empty terrains should remain empty when building scene defaults"))))
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-screen-pos-terrain-domain-hit-respects-scene-root-transform []
  (local setup (setup-scene {:scene-position (glm.vec3 -5 0 0)
                             :scene-rotation (glm.quat 1 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 -3 10 2)
                                (glm.vec3 -3 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (scene.layout-root:update)
        (local hit (scene:screen-pos-terrain-domain-hit {:x 50 :y 50}
                                                        {:view view
                                                         :projection projection
                                                         :viewport viewport}))
        (assert hit "screen-pos terrain domain hit should resolve a translated scene-root terrain")
        (assert (= hit.terrain-id "terrain-a")
                "screen-pos terrain domain hit should report terrain id through scene-root transform")
        (assert (= hit.sample.x 2)
                "screen-pos terrain domain hit should preserve sample x under scene-root translation")
        (assert (= hit.sample.z 2)
                "screen-pos terrain domain hit should preserve sample z under scene-root translation"))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-screen-pos-terrain-hit-resolves-default-heightfield []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (local hit (scene:screen-pos-terrain-hit {:x 50 :y 50}
                                                 {:view view
                                                  :projection projection
                                                  :viewport viewport}))
        (assert hit "screen-pos terrain hit should resolve a heightfield terrain")
        (assert (= hit.terrain-id "terrain-a") "screen-pos terrain hit should report terrain id")
        (assert (= hit.target.mode :rect) "screen-pos terrain hit should return a single-sample target")
        (assert (= hit.sample.x 2) "screen-pos terrain hit should resolve the nearest sample x")
        (assert (= hit.sample.z 2) "screen-pos terrain hit should resolve the nearest sample z"))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-screen-drag-terrain-target-builds-rect []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (local target-result
          (scene:screen-drag-terrain-target {:x 40 :y 50}
                                            {:x 60 :y 50}
                                            {:view view
                                             :projection projection
                                             :viewport viewport}))
        (assert target-result "screen drag terrain target should resolve a rect target")
        (assert (= target-result.terrain-id "terrain-a") "screen drag target should report terrain id")
        (assert (= target-result.target.mode :rect) "screen drag target should resolve a rect target")
        (assert (= target-result.target.x0 1) "screen drag target should normalize the smaller sample x")
        (assert (= target-result.target.x1 3) "screen drag target should normalize the larger sample x")
        (assert (= target-result.target.z0 2) "screen drag target should keep the sampled z start")
        (assert (= target-result.target.z1 2) "screen drag target should keep the sampled z end when horizontal"))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-screen-drag-terrain-target-respects-scene-root-transform []
  (local setup (setup-scene {:scene-position (glm.vec3 -5 0 0)
                             :scene-rotation (glm.quat 1 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 -3 10 2)
                                (glm.vec3 -3 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (scene.layout-root:update)
        (local target-result
          (scene:screen-drag-terrain-target {:x 40 :y 50}
                                            {:x 60 :y 50}
                                            {:view view
                                             :projection projection
                                             :viewport viewport}))
        (assert target-result
                "screen drag terrain target should resolve through scene-root transformed terrain")
        (assert (= target-result.terrain-id "terrain-a"))
        (assert (= target-result.target.mode :rect))
        (assert (= target-result.target.x0 1))
        (assert (= target-result.target.x1 3))
        (assert (= target-result.target.z0 2))
        (assert (= target-result.target.z1 2)))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-screen-pos-terrain-domain-hit-matches-exact-oracle []
  (local setup (setup-scene {:scene-position (glm.vec3 -5 0 0)
                             :scene-rotation (glm.quat 1 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local original-camera app.camera)
  (fn run-case [case-seed]
    (local terrain (random-heightfield-record (+ 4000 case-seed)))
    (scene:build-default {:terrains [terrain]})
    (scene.layout-root:update)
    (local metadata (. scene.scene-terrains 1))
    (local layout metadata.element.layout)
    (local half-size (* layout.size (glm.vec3 0.5)))
    (local center (+ layout.position (layout.rotation:rotate half-size)))
    (local camera-pos (+ center (glm.vec3 0 40 0)))
    (local camera (Camera {:position camera-pos
                           :rotation (glm.quat (/ (- math.pi) 2) (glm.vec3 1 0 0))}))
    (set app.camera camera)
    (local view (camera:get-view-matrix))
    (local viewport {:x 0 :y 0 :width 400 :height 300})
    (local projection (glm.perspective (/ math.pi 3) (/ 4 3) 0.1 200.0))
    (for [point-seed 1 6]
      (math.randomseed (+ (* case-seed 100) point-seed))
      (local pos {:x (random-range 0 viewport.width)
                  :y (random-range 0 viewport.height)})
      (local actual (scene:screen-pos-terrain-domain-hit pos
                                                         {:view view
                                                          :projection projection
                                                          :viewport viewport}))
      (local expected (oracle-scene-domain-hit scene pos
                                               {:view view
                                                :projection projection
                                                :viewport viewport}))
      (assert (scene-hit-approx=? actual expected)
              (.. "scene domain hit mismatch case=" case-seed
                  " point=" point-seed
                  " actual=" (if actual "hit" "nil")
                  " expected=" (if expected "hit" "nil")))))
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 400 :height 300})
        (local projection (glm.perspective (/ math.pi 3) (/ 4 3) 0.1 200.0))
        (app.set-viewport viewport)
        (set app.projection projection)
        (for [case-seed 1 20]
          (run-case case-seed)))))
  (set app.camera original-camera)
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-screen-pos-terrain-domain-fast-matches-exact-oracle []
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local original-camera app.camera)

  (fn run-case [case-seed]
    (math.randomseed (+ 12000 case-seed))
    (local scene-yaw (random-range (- math.pi) math.pi))
    (local scene-half-angle (/ scene-yaw 2))
    (local setup
      (setup-scene {:scene-position (glm.vec3 (random-range -25 25) 0 (random-range -25 25))
                    :scene-rotation (glm.quat (math.cos scene-half-angle) 0 (math.sin scene-half-angle) 0)}))
    (local cleanup setup.cleanup)
    (local scene setup.scene-result.scene)
    (local (ok err)
      (pcall
        (fn []
          (local terrain (random-heightfield-record (+ 8000 case-seed)))
          (scene:build-default {:terrains [terrain]})
          (scene.layout-root:update)
          (local metadata (. scene.scene-terrains 1))
          (local layout metadata.element.layout)
          (local half-size (* layout.size (glm.vec3 0.5)))
          (local center (+ layout.position (layout.rotation:rotate half-size)))
          (local camera-pos (+ center
                               (glm.vec3 (random-range -60 60)
                                         (random-range 18 70)
                                         (random-range -60 60))))
          (local camera (camera-looking-at camera-pos center))
          (set app.camera camera)
          (local view (camera:get-view-matrix))
          (local viewport {:x 0 :y 0 :width 400 :height 300})
          (local projection (glm.perspective (/ math.pi 3) (/ 4 3) 0.1 200.0))
          (for [point-seed 1 120]
            (math.randomseed (+ (* case-seed 1000) point-seed))
            (local pos {:x (random-range 0 viewport.width)
                        :y (random-range 0 viewport.height)})
            (local fast (oracle-scene-domain-hit-fast scene pos
                                                      {:view view
                                                       :projection projection
                                                       :viewport viewport}))
            (local exact (oracle-scene-domain-hit scene pos
                                                  {:view view
                                                   :projection projection
                                                   :viewport viewport}))
            (assert (scene-hit-approx=? fast exact)
                    (.. "scene fast domain hit mismatch case=" case-seed
                        " point=" point-seed
                        " screen=[" pos.x "," pos.y "]"
                        " fast=" (if fast "hit" "nil")
                        " exact=" (if exact "hit" "nil")))))))
    (cleanup)
    (when (not ok)
      (error err)))

  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 400 :height 300})
        (local projection (glm.perspective (/ math.pi 3) (/ 4 3) 0.1 200.0))
        (app.set-viewport viewport)
        (set app.projection projection)
        (for [case-seed 1 20]
          (run-case case-seed)))))
  (set app.camera original-camera)
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (when (not ok)
    (error err)))

(fn scene-screen-pos-terrain-domain-hit-scales-logical-input-to-pixel-viewport []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local original-engine-width (and app.engine app.engine.width))
  (local original-engine-height (and app.engine app.engine.height))
  (local original-engine-pixel-width (and app.engine (. app.engine "pixel-width")))
  (local original-engine-pixel-height (and app.engine (. app.engine "pixel-height")))
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (when app.engine
          (set app.engine.width 50)
          (set app.engine.height 50)
          (set (. app.engine "pixel-width") 100)
          (set (. app.engine "pixel-height") 100))
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (local hit (scene:screen-pos-terrain-domain-hit {:x 20 :y 25}
                                                        {:view view
                                                         :projection projection
                                                         :viewport viewport}))
        (assert hit "scaled logical input should still hit the terrain")
        (assert (= hit.terrain-id "terrain-a") "scaled logical input should preserve terrain id")
        (assert (= hit.sample.x 1) "scaled logical input should map x through logical->pixel scaling")
        (assert (= hit.sample.z 2) "scaled logical input should map y through logical->pixel scaling"))))
  (when app.engine
    (set app.engine.width original-engine-width)
    (set app.engine.height original-engine-height)
    (set (. app.engine "pixel-width") original-engine-pixel-width)
    (set (. app.engine "pixel-height") original-engine-pixel-height))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-screen-pos-terrain-domain-hit-default-app-state-matches-exact-oracle []
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local original-camera app.camera)
  (local original-engine-width (and app.engine app.engine.width))
  (local original-engine-height (and app.engine app.engine.height))
  (local original-engine-pixel-width (and app.engine (. app.engine "pixel-width")))
  (local original-engine-pixel-height (and app.engine (. app.engine "pixel-height")))

  (fn run-case [case-seed]
    (math.randomseed (+ 16000 case-seed))
    (local scene-yaw (random-range (- math.pi) math.pi))
    (local scene-half-angle (/ scene-yaw 2))
    (local setup
      (setup-scene {:scene-position (glm.vec3 (random-range -25 25) 0 (random-range -25 25))
                    :scene-rotation (glm.quat (math.cos scene-half-angle) 0 (math.sin scene-half-angle) 0)}))
    (local cleanup setup.cleanup)
    (local scene setup.scene-result.scene)
    (local (ok err)
      (pcall
        (fn []
          (local terrain (random-heightfield-record (+ 17000 case-seed)))
          (scene:build-default {:terrains [terrain]})
          (scene.layout-root:update)
          (local metadata (. scene.scene-terrains 1))
          (local layout metadata.element.layout)
          (local half-size (* layout.size (glm.vec3 0.5)))
          (local center (+ layout.position (layout.rotation:rotate half-size)))
          (local camera-pos (+ center
                               (glm.vec3 (random-range -60 60)
                                         (random-range 18 70)
                                         (random-range -60 60))))
          (set app.camera (camera-looking-at camera-pos center))
          (local logical-width (math.random 320 1280))
          (local logical-height (math.random 240 960))
          (local pixel-scale (+ 1 (math.random 0 2)))
          (local viewport {:x 0
                           :y 0
                           :width (* logical-width pixel-scale)
                           :height (* logical-height pixel-scale)})
          (app.set-viewport viewport)
          (set app.projection (glm.perspective (/ math.pi 3)
                                               (/ viewport.width viewport.height)
                                               0.1
                                               400.0))
          (when app.engine
            (set app.engine.width logical-width)
            (set app.engine.height logical-height)
            (set (. app.engine "pixel-width") viewport.width)
            (set (. app.engine "pixel-height") viewport.height))
          (for [point-seed 1 120]
            (math.randomseed (+ (* case-seed 1000) point-seed))
            (local pos {:x (random-range 0 logical-width)
                        :y (random-range 0 logical-height)})
            (local actual (scene:screen-pos-terrain-domain-hit pos nil))
            (local expected (oracle-scene-domain-hit scene pos nil))
            (assert (scene-hit-approx=? actual expected)
                    (.. "default app-state domain hit mismatch case=" case-seed
                        " point=" point-seed
                        " screen=[" pos.x "," pos.y "]"
                        " actual=" (if actual "hit" "nil")
                        " expected=" (if expected "hit" "nil")))))))
    (cleanup)
    (when (not ok)
      (error err)))

  (local (ok err)
    (pcall
      (fn []
        (for [case-seed 1 20]
          (run-case case-seed)))))

  (when app.engine
    (set app.engine.width original-engine-width)
    (set app.engine.height original-engine-height)
    (set (. app.engine "pixel-width") original-engine-pixel-width)
    (set (. app.engine "pixel-height") original-engine-pixel-height))
  (set app.camera original-camera)
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (when (not ok)
    (error err)))

(fn target-approx=? [left right]
  (if (or (not left) (not right))
      (= left right)
      (and (= left.mode right.mode)
           (= left.x0 right.x0)
           (= left.z0 right.z0)
           (= left.x1 right.x1)
           (= left.z1 right.z1))))

(fn with-domain-hit-mode [mode f]
  (local original-domain-hit TerrainQuery.domain-hit-record)
  (set TerrainQuery.domain-hit-record
       (fn [record ray]
         (local kind (and record record.kind))
         (if (not (= kind "heightfield-terrain"))
             nil
             (if (= mode :exact)
                 (HeightfieldTerrainQuery.raycast-record-exact record ray)
                 (HeightfieldTerrainQuery.raycast-record-fast record ray)))))
  (local (ok result) (pcall f))
  (set TerrainQuery.domain-hit-record original-domain-hit)
  (if ok
      result
      (error result)))

(fn resolve-target-capture-drag [scene terrain-id start-pos move-pos end-pos]
  (var resolved nil)
  (local capture
    (HeightfieldTargetCapture {:scene scene
                               :terrain-id terrain-id
                               :on-target (fn [target _result]
                                            (set resolved target))}))
  (capture:begin)
  (capture:begin-drag start-pos)
  (capture:update-drag move-pos)
  (capture:end-drag end-pos)
  (capture:drop)
  resolved)

(fn heightfield-target-capture-fast-matches-exact-default-app-state []
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local original-camera app.camera)
  (local original-engine-width (and app.engine app.engine.width))
  (local original-engine-height (and app.engine app.engine.height))
  (local original-engine-pixel-width (and app.engine (. app.engine "pixel-width")))
  (local original-engine-pixel-height (and app.engine (. app.engine "pixel-height")))

  (fn run-case [case-seed]
    (math.randomseed (+ 19000 case-seed))
    (local scene-yaw (random-range (- math.pi) math.pi))
    (local scene-half-angle (/ scene-yaw 2))
    (local setup
      (setup-scene {:scene-position (glm.vec3 (random-range -25 25) 0 (random-range -25 25))
                    :scene-rotation (glm.quat (math.cos scene-half-angle) 0 (math.sin scene-half-angle) 0)}))
    (local cleanup setup.cleanup)
    (local scene setup.scene-result.scene)
    (local (ok err)
      (pcall
        (fn []
          (local terrain (random-heightfield-record (+ 20000 case-seed)))
          (scene:build-default {:terrains [terrain]})
          (scene.layout-root:update)
          (local metadata (. scene.scene-terrains 1))
          (local layout metadata.element.layout)
          (local half-size (* layout.size (glm.vec3 0.5)))
          (local center (+ layout.position (layout.rotation:rotate half-size)))
          (local camera-pos (+ center
                               (glm.vec3 (random-range -60 60)
                                         (random-range 18 70)
                                         (random-range -60 60))))
          (set app.camera (camera-looking-at camera-pos center))
          (local logical-width (math.random 320 1280))
          (local logical-height (math.random 240 960))
          (local pixel-scale (+ 1 (math.random 0 2)))
          (local viewport {:x 0
                           :y 0
                           :width (* logical-width pixel-scale)
                           :height (* logical-height pixel-scale)})
          (app.set-viewport viewport)
          (set app.projection (glm.perspective (/ math.pi 3)
                                               (/ viewport.width viewport.height)
                                               0.1
                                               400.0))
          (when app.engine
            (set app.engine.width logical-width)
            (set app.engine.height logical-height)
            (set (. app.engine "pixel-width") viewport.width)
            (set (. app.engine "pixel-height") viewport.height))
          (for [drag-seed 1 80]
            (math.randomseed (+ (* case-seed 2000) drag-seed))
            (local start-pos {:x (random-range 0 logical-width)
                              :y (random-range 0 logical-height)})
            (local move-pos {:x (random-range 0 logical-width)
                             :y (random-range 0 logical-height)})
            (local end-pos {:x (random-range 0 logical-width)
                            :y (random-range 0 logical-height)})
            (local exact
              (with-domain-hit-mode :exact
                (fn []
                  (resolve-target-capture-drag scene terrain.id start-pos move-pos end-pos))))
            (local fast
              (with-domain-hit-mode :fast
                (fn []
                  (resolve-target-capture-drag scene terrain.id start-pos move-pos end-pos))))
            (assert (target-approx=? fast exact)
                    (.. "target capture fast mismatch case=" case-seed
                        " drag=" drag-seed
                        " start=[" start-pos.x "," start-pos.y "]"
                        " move=[" move-pos.x "," move-pos.y "]"
                        " end=[" end-pos.x "," end-pos.y "]"
                        " fast=" (if fast "hit" "nil")
                        " exact=" (if exact "hit" "nil")))))))
    (cleanup)
    (when (not ok)
      (error err)))

  (local (ok err)
    (pcall
      (fn []
        (for [case-seed 1 20]
          (run-case case-seed)))))

  (when app.engine
    (set app.engine.width original-engine-width)
    (set app.engine.height original-engine-height)
    (set (. app.engine "pixel-width") original-engine-pixel-width)
    (set (. app.engine "pixel-height") original-engine-pixel-height))
  (set app.camera original-camera)
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (when (not ok)
    (error err)))

(fn heightfield-fast-raycast-matches-persisted-world-fixture []
  (local fixture (read-json "assets/lua/tests/data/heightfield-fast-mismatch.json"))
  (local terrain fixture.terrain)
  (local local-record {:id terrain.id
                       :kind terrain.kind
                       :options {:position [0 0 0]
                                 :rotation [1 0 0 0]
                                 :sample-spacing terrain.options.sample-spacing
                                 :chunk-samples terrain.options.chunk-samples
                                 :default-height terrain.options.default-height}
                       :chunks terrain.chunks})
  (local rays [{:origin [-189.27082824707 539.77001953125 -230.39498901367]
                :direction [0.64207345247269 -0.43977665901184 0.62796556949615]
                :sample [30 27]}
               {:origin [-189.27673339844 539.755859375 -230.40634155273]
                :direction [0.60223066806793 -0.59372818470001 0.53367334604263]
                :sample [18 13]}])
  (each [_ entry (ipairs rays)]
    (local ray {:origin (array->vec3 entry.origin)
                :direction (glm.normalize (array->vec3 entry.direction))})
    (local exact (HeightfieldTerrainQuery.raycast-record-exact local-record ray))
    (local fast (HeightfieldTerrainQuery.raycast-record-fast local-record ray))
    (assert exact
            (.. "persisted world fixture exact raycast should hit sample [" (. entry.sample 1) "," (. entry.sample 2) "]"))
    (assert (= exact.sample.x (. entry.sample 1)))
    (assert (= exact.sample.z (. entry.sample 2)))
    (assert (terrain-hit-approx=? fast exact)
            (.. "persisted world fixture fast raycast mismatch at sample [" (. entry.sample 1) "," (. entry.sample 2) "]"
                " fast=" (if fast "hit" "nil")
                " exact=" (if exact "hit" "nil")))))

(fn heightfield-target-capture-resolves-live-scene-drag []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var resolved-target nil)
        (local capture
          (HeightfieldTargetCapture {:scene scene
                                     :ctx scene.build-context
                                     :terrain-id "terrain-a"
                                     :ray-opts {:view view
                                                :projection projection
                                                :viewport viewport}
                                     :on-target (fn [target _result]
                                                  (set resolved-target target))}))
        (capture:begin)
        (capture:begin-drag {:x 40 :y 50})
        (capture:update-drag {:x 60 :y 50})
        (capture:end-drag {:x 60 :y 50})
        (assert resolved-target "target capture should resolve a terrain rectangle after drag")
        (assert (= resolved-target.x0 1) "target capture should resolve the smaller sample x")
        (assert (= resolved-target.x1 3) "target capture should resolve the larger sample x")
        (assert (= resolved-target.z0 2) "target capture should resolve z bounds")
        (assert (= resolved-target.z1 2) "target capture should keep horizontal z bounds")
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-target-capture-escape-cancels-selection []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var resolved-target nil)
        (local capture
          (HeightfieldTargetCapture {:scene scene
                                     :ctx scene.build-context
                                     :terrain-id "terrain-a"
                                     :ray-opts {:view view
                                                :projection projection
                                                :viewport viewport}
                                     :on-target (fn [target _result]
                                                  (set resolved-target target))}))
        (capture:begin)
        (capture:begin-drag {:x 40 :y 50})
        (capture:update-drag {:x 60 :y 50})
        (capture:on-key-down {:key 27})
        (assert (= resolved-target nil)
                "target capture should not resolve a rectangle when cancelled with escape")
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-target-capture-promotes-start-on-first-valid-drag-hit []
  (local camera (Camera))
  (camera:set-position (glm.vec3 2 10 2))
  (camera:look-at (glm.vec3 2 0 2))
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)
                             :camera camera}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var resolved-target nil)
        (local capture
          (HeightfieldTargetCapture {:scene scene
                                     :ctx scene.build-context
                                     :terrain-id "terrain-a"
                                     :on-target (fn [target _result]
                                                  (set resolved-target target))}))
        (local start-hit
          (scene:screen-pos-terrain-domain-hit {:x 40 :y 50}))
        (local end-hit
          (scene:screen-pos-terrain-domain-hit {:x 60 :y 50}))
        (local expected
          (and start-hit end-hit
               (TerrainQuery.target-between-hits start-hit.query-record
                                                 start-hit
                                                 end-hit)))
        (capture:begin)
        (capture:begin-drag {:x 95 :y 5})
        (capture:update-drag {:x 40 :y 50})
        (capture:end-drag {:x 60 :y 50})
        (assert resolved-target
                "target capture should recover when mouse-down misses but the first drag hit lands on terrain")
        (assert expected
                "promoted-start fixture should derive an expected terrain target from accepted hits")
        (assert (= resolved-target.x0 expected.x0))
        (assert (= resolved-target.z0 expected.z0))
        (assert (= resolved-target.x1 expected.x1))
        (assert (= resolved-target.z1 expected.z1))
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-target-capture-keeps-last-valid-hit-on-release []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var resolved-target nil)
        (local capture
          (HeightfieldTargetCapture {:scene scene
                                     :ctx scene.build-context
                                     :terrain-id "terrain-a"
                                     :ray-opts {:view view
                                                :projection projection
                                                :viewport viewport}
                                     :on-target (fn [target _result]
                                                  (set resolved-target target))}))
        (capture:begin)
        (capture:begin-drag {:x 40 :y 50})
        (capture:update-drag {:x 60 :y 50})
        (capture:end-drag {:x 95 :y 5})
        (assert resolved-target
                "target capture should still resolve a terrain rectangle when release leaves the terrain after a valid drag")
        (assert (= resolved-target.x0 1) "target capture should preserve the drag start sample x")
        (assert (= resolved-target.x1 3) "target capture should preserve the last valid dragged sample x")
        (assert (= resolved-target.z0 2) "target capture should preserve the drag start sample z")
        (assert (= resolved-target.z1 2) "target capture should preserve the last valid dragged sample z")
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-target-capture-does-not-raycast-before-drag []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local original-screen-pos-terrain-domain-hit scene.screen-pos-terrain-domain-hit)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var hit-count 0)
        (set scene.screen-pos-terrain-domain-hit
             (fn [self pos ray-opts]
               (set hit-count (+ hit-count 1))
               (original-screen-pos-terrain-domain-hit self pos ray-opts)))
        (local capture
          (HeightfieldTargetCapture {:scene scene
                                     :ctx scene.build-context
                                     :terrain-id "terrain-a"
                                     :ray-opts {:view view
                                                :projection projection
                                                :viewport viewport}}))
        (capture:begin)
        (capture:update-drag {:x 60 :y 50})
        (assert (= hit-count 0)
                "target capture should not raycast terrain before a drag has started")
        (capture:begin-drag {:x 40 :y 50})
        (assert (> hit-count 0)
                "target capture should raycast terrain when the drag starts on mouse down")
        (capture:drop))))
  (set scene.screen-pos-terrain-domain-hit original-screen-pos-terrain-domain-hit)
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-target-capture-resolves-live-scene-drag-with-default-ray-opts []
  (local camera (Camera))
  (camera:set-position (glm.vec3 2 10 2))
  (camera:look-at (glm.vec3 2 0 2))
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)
                             :camera camera}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var resolved-target nil)
        (local start-hit
          (scene:screen-pos-terrain-domain-hit {:x 40 :y 50}))
        (local end-hit
          (scene:screen-pos-terrain-domain-hit {:x 60 :y 50}))
        (local expected
          (and start-hit end-hit
               (TerrainQuery.target-between-hits start-hit.query-record
                                                 start-hit
                                                 end-hit)))
        (local original-screen-drag-terrain-target scene.screen-drag-terrain-target)
        (local capture
          (HeightfieldTargetCapture {:scene scene
                                     :ctx scene.build-context
                                     :terrain-id "terrain-a"
                                     :on-target (fn [target _result]
                                                  (set resolved-target target))}))
        (set scene.screen-drag-terrain-target
             (fn [_self _start-pos _end-pos _opts]
               (error "target capture should derive terrain targets from accepted hits")))
        (capture:begin)
        (capture:begin-drag {:x 40 :y 50})
        (capture:update-drag {:x 60 :y 50})
        (capture:end-drag {:x 60 :y 50})
        (assert resolved-target
                "default scene ray options should be enough for live terrain picking")
        (assert expected
                "default-ray-opts fixture should derive an expected terrain target from accepted hits")
        (assert (= resolved-target.x0 expected.x0))
        (assert (= resolved-target.z0 expected.z0))
        (assert (= resolved-target.x1 expected.x1))
        (assert (= resolved-target.z1 expected.z1))
        (set scene.screen-drag-terrain-target original-screen-drag-terrain-target)
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-paint-capture-stamps-live-scene-samples []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local original-clickables app.clickables)
  (local original-movables app.movables)
  (local original-resizables app.resizables)
  (local original-fpc app.first-person-controls)
  (local original-states app.states)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (local stamped-batches [])
        (local capture
          (HeightfieldPaintCapture {:scene scene
                                    :terrain-id "terrain-a"
                                    :ray-opts {:view view
                                               :projection projection
                                               :viewport viewport}
                                    :on-stamp-batch (fn [targets _hit]
                                                      (table.insert stamped-batches targets))}))
        (local states (States))
        (states.add-state :normal {})
        (states.add-state :terrain-paint (TerrainPaintState))
        (states.set-state :normal)
        (set app.states states)
        (set app.clickables {:on-mouse-button-down (fn [_self _payload] nil)
                             :on-mouse-button-up (fn [_self _payload] nil)
                             :active? false})
        (set app.movables {:on-mouse-button-down (fn [_self _payload] nil)
                           :on-mouse-button-up (fn [_self _payload] nil)
                           :on-mouse-motion (fn [_self _payload] nil)
                           :drag-active? (fn [_self] false)})
        (set app.resizables {:on-mouse-button-down (fn [_self _payload] false)
                             :on-mouse-button-up (fn [_self _payload] nil)
                             :on-mouse-motion (fn [_self _payload] nil)
                             :drag-active? (fn [_self] false)})
        (set app.first-person-controls {:on-mouse-button-down (fn [_self _payload] nil)
                                        :on-mouse-button-up (fn [_self _payload] nil)
                                        :on-mouse-motion (fn [_self _payload] nil)
                                        :drag-active? (fn [_self] false)})
        (TerrainPaintManager.begin capture)
        (app.engine.events.mouse-button-down.emit {:button 1 :x 40 :y 50})
        (app.engine.events.mouse-motion.emit {:x 60 :y 50})
        (app.engine.events.updated.emit 0.016)
        (app.engine.events.mouse-button-up.emit {:button 1 :x 60 :y 50})
        (assert (= (length stamped-batches) 2)
                "paint capture should emit continuous stroke batches")
        (assert (= (length (. stamped-batches 1)) 1)
                "paint capture should emit the first hovered sample immediately")
        (assert (= (. (. (. stamped-batches 1) 1) :x0) 1)
                "paint capture should stamp the first sample under the cursor")
        (assert (= (length (. stamped-batches 2)) 2)
                "paint capture should batch the newly crossed samples on motion")
        (assert (= (. (. (. stamped-batches 2) 1) :x0) 2)
                "paint capture should include intermediate samples along the stroke")
        (assert (= (. (. (. stamped-batches 2) 2) :x0) 3)
                "paint capture should include the moved-to sample under the cursor")
        (assert (= (states.active-name) :normal)
                "paint capture should restore the previous state after completion")
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (set app.clickables original-clickables)
  (set app.movables original-movables)
  (set app.resizables original-resizables)
  (set app.first-person-controls original-fpc)
  (set app.states original-states)
  (cleanup)
  (when (not ok)
    (error err)))

(fn heightfield-paint-capture-does-not-raycast-before-stroke []
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local original-clickables app.clickables)
  (local original-movables app.movables)
  (local original-resizables app.resizables)
  (local original-fpc app.first-person-controls)
  (local original-states app.states)
  (local original-screen-pos-terrain-domain-hit scene.screen-pos-terrain-domain-hit)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var hit-count 0)
        (set scene.screen-pos-terrain-domain-hit
             (fn [self pos ray-opts]
               (set hit-count (+ hit-count 1))
               (original-screen-pos-terrain-domain-hit self pos ray-opts)))
        (local capture
          (HeightfieldPaintCapture {:scene scene
                                    :terrain-id "terrain-a"
                                    :ray-opts {:view view
                                               :projection projection
                                               :viewport viewport}}))
        (local states (States))
        (states.add-state :normal {})
        (states.add-state :terrain-paint (TerrainPaintState))
        (states.set-state :normal)
        (set app.states states)
        (set app.clickables {:on-mouse-button-down (fn [_self _payload] nil)
                             :on-mouse-button-up (fn [_self _payload] nil)
                             :active? false})
        (set app.movables {:on-mouse-button-down (fn [_self _payload] nil)
                           :on-mouse-button-up (fn [_self _payload] nil)
                           :on-mouse-motion (fn [_self _payload] nil)
                           :drag-active? (fn [_self] false)})
        (set app.resizables {:on-mouse-button-down (fn [_self _payload] false)
                             :on-mouse-button-up (fn [_self _payload] nil)
                             :on-mouse-motion (fn [_self _payload] nil)
                             :drag-active? (fn [_self] false)})
        (set app.first-person-controls {:on-mouse-button-down (fn [_self _payload] nil)
                                        :on-mouse-button-up (fn [_self _payload] nil)
                                        :on-mouse-motion (fn [_self _payload] nil)
                                        :drag-active? (fn [_self] false)})
        (TerrainPaintManager.begin capture)
        (app.engine.events.mouse-motion.emit {:x 60 :y 50})
        (assert (= hit-count 0)
                "paint capture should not raycast terrain before a stroke has started")
        (app.engine.events.mouse-button-down.emit {:button 1 :x 40 :y 50})
        (assert (= hit-count 1)
                "paint capture should raycast once when the stroke starts on mouse down")
        (capture:drop))))
  (set scene.screen-pos-terrain-domain-hit original-screen-pos-terrain-domain-hit)
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (set app.clickables original-clickables)
  (set app.movables original-movables)
  (set app.resizables original-resizables)
  (set app.first-person-controls original-fpc)
  (set app.states original-states)
  (cleanup)
  (when (not ok)
    (error err)))

(fn terrain-rect-pick-state-routes-engine-events []
  (local TerrainRectPickManager (require :graph/view/terrain-rect-pick-manager))
  (local setup (setup-scene {:scene-position (glm.vec3 0 0 0)}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (local original-clickables app.clickables)
  (local original-movables app.movables)
  (local original-resizables app.resizables)
  (local original-fpc app.first-person-controls)
  (local original-states app.states)
  (local (ok err)
    (pcall
      (fn []
        (local viewport {:x 0 :y 0 :width 100 :height 100})
        (local projection (glm.perspective (/ math.pi 3) 1.0 0.1 100.0))
        (local view (glm.lookAt (glm.vec3 2 10 2)
                                (glm.vec3 2 0 2)
                                (glm.vec3 0 0 -1)))
        (app.set-viewport viewport)
        (set app.projection projection)
        (scene:build-default {:terrains [{:id "terrain-a"
                                          :kind "heightfield-terrain"
                                          :options {:position [0 0 0]
                                                    :rotation [1 0 0 0]
                                                    :sample-spacing [1 1]
                                                    :chunk-samples [5 5]
                                                    :default-height 0.0}
                                          :chunks [{:coord [0 0]
                                                    :size [5 5]
                                                    :heights [0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0
                                                              0 0 0 0 0]}]}]})
        (var clickable-down-count 0)
        (var clickable-up-count 0)
        (set app.clickables {:on-mouse-button-down (fn [_self _payload]
                                                     (set clickable-down-count (+ clickable-down-count 1))
                                                     nil)
                             :on-mouse-button-up (fn [_self _payload]
                                                   (set clickable-up-count (+ clickable-up-count 1))
                                                   nil)
                             :active? true})
        (set app.movables {:on-mouse-button-down (fn [_self _payload] nil)
                           :on-mouse-button-up (fn [_self _payload] nil)
                           :on-mouse-motion (fn [_self _payload] nil)
                           :drag-active? (fn [_self] false)})
        (set app.resizables {:on-mouse-button-down (fn [_self _payload] false)
                             :on-mouse-button-up (fn [_self _payload] nil)
                             :on-mouse-motion (fn [_self _payload] nil)
                             :drag-active? (fn [_self] false)})
        (set app.first-person-controls {:on-mouse-button-down (fn [_self _payload] nil)
                                        :on-mouse-button-up (fn [_self _payload] nil)
                                        :on-mouse-motion (fn [_self _payload] nil)
                                        :drag-active? (fn [_self] false)})
        (local states (States))
        (states.add-state :normal {})
        (states.add-state :terrain-rect-pick (TerrainRectPickState))
        (states.set-state :normal)
        (set app.states states)
        (var resolved-target nil)
        (local capture
          (HeightfieldTargetCapture {:scene scene
                                     :ctx scene.build-context
                                     :terrain-id "terrain-a"
                                     :ray-opts {:view view
                                                :projection projection
                                                :viewport viewport}
                                     :on-target (fn [target _result]
                                                  (set resolved-target target))}))
        (TerrainRectPickManager.begin capture)
        (assert (= (app.states.active-name) :terrain-rect-pick)
                "terrain rectangle picking should enter an explicit app state")
        (app.engine.events.mouse-button-down.emit {:button 1 :x 40 :y 50})
        (app.engine.events.mouse-motion.emit {:x 60 :y 50})
        (app.engine.events.mouse-button-up.emit {:button 1 :x 60 :y 50})
        (assert resolved-target
                "terrain rectangle pick state should route engine mouse events to the active session")
        (assert (= resolved-target.x0 1))
        (assert (= resolved-target.x1 3))
        (assert (= clickable-down-count 0)
                "terrain rectangle pick state should bypass clickables on mouse down")
        (assert (= clickable-up-count 0)
                "terrain rectangle pick state should bypass clickables on mouse up")
        (assert (= (app.states.active-name) :normal)
                "terrain rectangle pick state should restore the previous state after completion")
        (capture:drop))))
  (app.set-viewport original-viewport)
  (set app.projection original-projection)
  (set app.clickables original-clickables)
  (set app.movables original-movables)
  (set app.resizables original-resizables)
  (set app.first-person-controls original-fpc)
  (set app.states original-states)
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-terrain-selection-persists-across-runtime-replace []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-themes app.themes)
  (set app.themes
       {:get-active-theme (fn []
                            {:terrain-selection {:fill (glm.vec4 0.2 0.5 0.9 0.2)
                                                 :border (glm.vec4 0.2 0.5 0.9 0.95)}})})
  (local (ok err)
    (pcall
      (fn []
        (local terrain-record
          {:id "terrain-a"
           :kind "heightfield-terrain"
           :options {:position [0 0 0]
                     :rotation [1 0 0 0]
                     :sample-spacing [2 2]
                     :chunk-samples [5 5]
                     :default-height 0.0}
           :chunks [{:coord [0 0]
                     :size [5 5]
                     :heights [0 0 0 0 0
                               0 0 0 0 0
                               0 0 0 0 0
                               0 0 0 0 0
                               0 0 0 0 0]}]})
        (local updated-record
          {:id "terrain-a"
           :kind "heightfield-terrain"
           :options {:position [0 0 0]
                     :rotation [1 0 0 0]
                     :sample-spacing [2 2]
                     :chunk-samples [5 5]
                     :default-height 1.0}
           :chunks [{:coord [0 0]
                     :size [5 5]
                     :heights [1 1 1 1 1
                               1 1 1 1 1
                               1 1 1 1 1
                               1 1 1 1 1
                               1 1 1 1 1]}]})
        (scene:build-default {:terrains [terrain-record]})
        (scene:set-terrain-selection-target "terrain-a" {:mode :rect
                                                         :x0 1
                                                         :z0 1
                                                         :x1 3
                                                         :z1 3})
        (local before (scene:get-terrain-selection-target "terrain-a"))
        (assert before "scene should expose terrain selection after it is set")
        (scene:replace-terrain-record "terrain-a" updated-record)
        (local after (scene:get-terrain-selection-target "terrain-a"))
        (assert after "terrain selection should persist after runtime terrain replacement")
        (assert (= after.x0 1))
        (assert (= after.z0 1))
        (assert (= after.x1 3))
        (assert (= after.z1 3)))))
  (set app.themes original-themes)
  (cleanup)
  (when (not ok)
    (error err)))

(fn demo-entry-capture-state-persists-entry-persistence []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local (ok err)
    (pcall
      (fn []
        (local browser (scene:add-demo-browser))
        (local entry (DemoDialogs.find-entry :welcome-dialog))
        (assert entry "Expected Welcome Dialog demo entry")
        (local demo-element (scene:add-demo-entry entry))
        (local captured (scene:capture-state))
        (local panels (or captured.panels []))
        (assert (= (length panels) 2)
                "Expected demo browser + demo entry to be persisted")
        (var found-demo-entry false)
        (each [_ panel (ipairs panels)]
          (when (= panel.kind "demo-entry-welcome-dialog")
            (set found-demo-entry true)
            (assert (= panel.restorer-module "demo-dialogs")
                    "Demo entry should restore through demo-dialogs module")
            (assert (= panel.entry-key "welcome-dialog")
                    "Demo entry should persist its key for restore")))
        (assert found-demo-entry
                "Captured scene state should include welcome-dialog entry persistence")
        (scene:remove-panel-child browser)
        (scene:remove-panel-child demo-element)
        (assert (= (length scene.scene-children) 0)
                "Scene should be empty before restore")
        (scene:restore-state captured)
        (assert (= (length scene.scene-children) 2)
                "Scene.restore-state should recreate both browser and demo entry"))))
  (cleanup)
  (when (not ok)
    (error err)))

(fn scene-capture-state-requires-panel-persistence []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local (ok err)
    (pcall
      (fn []
        (scene:add-panel-child {:builder (fn [_ctx]
                                           {:layout (Layout {:name "scene-missing-persistence"
                                                             :measurer (fn [self]
                                                                         (set self.measure (glm.vec3 1 1 1)))
                                                             :layouter (fn [self]
                                                                         (set self.size self.measure))})
                                            :drop (fn [_self])})})
        (scene:capture-state))))
  (cleanup)
  (assert (not ok) "Scene.capture-state should fail when panel persistence is missing")
  (assert (string.find (tostring err) "without persistence")
          "Scene.capture-state should report missing persistence")
  true)

(fn scene-capture-state-requires-restore-strategy []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local (ok err)
    (pcall
      (fn []
        (scene:add-panel-child {:builder (fn [_ctx]
                                           {:layout (Layout {:name "scene-missing-restore"
                                                             :measurer (fn [self]
                                                                         (set self.measure (glm.vec3 1 1 1)))
                                                             :layouter (fn [self]
                                                                         (set self.size self.measure))})
                                            :drop (fn [_self])})
                               :persistence {:kind "scene-missing-restore"}})
        (scene:capture-state))))
  (cleanup)
  (assert (not ok) "Scene.capture-state should fail when restore strategy is missing")
  (assert (string.find (tostring err) "no restore strategy")
          "Scene.capture-state should report missing restore strategy")
  true)

(fn added-dialog-appears-in-front-of-camera []
  (local camera (Camera {:position (glm.vec3 2 3 4)}))
  (camera:yaw (math.rad 45))
  (local setup (setup-scene {:camera camera}))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (fn probe-builder [_ctx]
    (local layout
      (Layout {:name "position-probe"
               :measurer (fn [self]
                           (set self.measure (glm.vec3 1 1 1)))
               :layouter (fn [self]
                           (set self.size self.measure))}))
    {:layout layout
     :drop (fn [_self]
             (layout:drop))})

  (let [(ok err)
        (pcall
          (fn []
            (scene:add-panel-child {:builder probe-builder})
            (assert (= (length scene.scene-children) 1)
                    "Scene should contain the positioned probe")
            (local positioned-metadata (. scene.scene-children 1))
            (local wrapper positioned-metadata.element)
            (local layout wrapper.layout)
            (local expected-position
              (+ camera.position (* (camera:get-forward) (glm.vec3 100))))
            (local half-size (* 0.5 layout.size))
            (local center (+ layout.position (layout.rotation:rotate half-size)))
            (assert (vec3-approx= center expected-position)
                    "Positioned probe center should be placed in front of the camera")
            (local cam-forward (camera:get-forward))
            (local projected (glm.vec3 cam-forward.x 0 cam-forward.z))
            (local facing
              (if (> (glm.length projected) 1e-4)
                  (glm.normalize (* projected (glm.vec3 -1)))
                  (glm.vec3 0 0 1)))
            (local expected-forward (* facing (glm.vec3 -1)))
            (local actual-forward (layout.rotation:rotate (glm.vec3 0 0 -1)))
            (when (not (vec3-approx= actual-forward expected-forward))
              (error (string.format
                       "Positioned probe should face the camera (actual=%.4f,%.4f,%.4f expected=%.4f,%.4f,%.4f)"
                       actual-forward.x actual-forward.y actual-forward.z
                       expected-forward.x expected-forward.y expected-forward.z)))))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn scene-add-physics-body-falls []
  (assert bt "Physics body test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (let [(ok err)
        (pcall
          (fn []
            (local element (scene:add-physics-body {:position (glm.vec3 0 20 0)
                                                      :size (glm.vec3 4 4 4)}))
            (assert element "Expected add-physics-body to return an element")
            (assert scene.entity.physics-bodies "Scene should track runtime physics bodies")
            (local entry (. scene.entity.physics-bodies (length scene.entity.physics-bodies)))
            (assert (and entry entry.body) "Runtime physics body should create a rigid body")
            (local start-y element.layout.position.y)

            (for [i 1 120]
              (app.engine.physics:update 0)
              (scene:update))

            (local end-y element.layout.position.y)
            (local transform (entry.body:getCenterOfMassTransform))
            (local origin (transform:getOrigin))
            (assert (< end-y (- start-y 5))
                    (string.format
                      "Physics body should fall (start_y=%.3f end_y=%.3f body_center_y=%.3f)"
                      start-y
                      end-y
                      origin.y))))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn scene-physics-body-collides-with-flat-terrain []
  (assert bt "Physics body terrain test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (let [(ok err)
        (pcall
          (fn []
            (local element (scene:add-physics-body {:position (glm.vec3 0 -70 0)
                                                      :size (glm.vec3 4 4 4)}))
            (assert element "Expected add-physics-body to return an element")

            (for [i 1 360]
              (app.engine.physics:update 0)
              (scene:update))

            (local y element.layout.position.y)
            (assert (< (math.abs (+ y 100)) 6)
                    (string.format
                      "Physics body should settle near flat terrain y=-100 (actual_y=%.3f)"
                      y))))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn scene-runtime-body-falls-after-drag-release []
  (assert bt "Physics body drag-release test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)

  (let [(ok err)
        (pcall
          (fn []
            (local element (scene:add-physics-body {:position (glm.vec3 0 20 0)
                                                      :size (glm.vec3 4 4 4)}))
            (assert element "Expected add-physics-body to return an element")
            (local physics-entry (. scene.entity.physics-bodies (length scene.entity.physics-bodies)))
            (assert physics-entry "Expected runtime physics entry")

            (var movable-entry nil)
            (each [_ entry (ipairs (or scene.entity.movables []))]
              (when (and (not movable-entry)
                         (= entry.key physics-entry))
                (set movable-entry entry)))
            (assert movable-entry "Expected movable entry for runtime physics body")

            (movable-entry.on-drag-start movable-entry)
            (element.layout:set-position (glm.vec3 0 5 0))
            (movable-entry.on-drag-end movable-entry)

            (scene:update)
            (local start-y element.layout.position.y)
            (for [i 1 120]
              (app.engine.physics:update 0)
              (scene:update))
            (local end-y element.layout.position.y)
            (local transform (physics-entry.body:getCenterOfMassTransform))
            (local origin (transform:getOrigin))
            (assert (< end-y (- start-y 2))
                    (string.format
                      "Body should continue falling after drag release (start_y=%.3f end_y=%.3f body_center_y=%.3f body_active=%s dragging=%s)"
                      start-y
                      end-y
                      origin.y
                      (tostring physics-entry.body-active?)
                      (tostring physics-entry.dragging)))))]
    (cleanup)
    (when (not ok)
      (error err))))

(fn scene-restore-physics-cuboids-world-switch-drift-check []
  (assert bt "World-switch drift check requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")

  (fn sim [scene steps]
    (for [i 1 steps]
      (app.engine.physics:update 0)
      (scene:update)))

  (fn physics-layout-ys [scene]
    (local ys [])
    (each [_ entry (ipairs (or (and scene.entity scene.entity.physics-bodies) []))]
      (local y (and entry entry.positioned entry.positioned.layout entry.positioned.layout.position.y))
      (when y
        (table.insert ys y)))
    ys)

  (fn max-abs-drift [start-ys end-ys]
    (var drift 0.0)
    (var idx 1)
    (while (<= idx (math.min (length start-ys) (length end-ys)))
      (local delta (math.abs (- (. end-ys idx) (. start-ys idx))))
      (when (> delta drift)
        (set drift delta))
      (set idx (+ idx 1)))
    drift)

  (local setup0 (setup-scene))
  (local cleanup0 setup0.cleanup)
  (local scene0 setup0.scene-result.scene)
  (local (ok0 payload0)
    (pcall
      (fn []
        (scene0:add-physics-body {:position (glm.vec3 -6 0 0)
                                  :size (glm.vec3 4 4 4)})
        (scene0:add-physics-body {:position (glm.vec3 6 0 0)
                                  :size (glm.vec3 4 4 4)})
        (sim scene0 720)
        (scene0:capture-state))))
  (cleanup0)
  (when (not ok0)
    (error payload0))
  (local captured payload0)
  (var current-captured captured)

  (var worst-drift 0.0)
  (for [cycle 1 3]
    (local setup (setup-scene))
    (local cleanup setup.cleanup)
    (local scene setup.scene-result.scene)
    (local (ok payload)
      (pcall
        (fn []
          (scene:build-default {:terrains current-captured.terrains})
          (scene:restore-state current-captured)
          (local start-ys (physics-layout-ys scene))
          (assert (= (length start-ys) 2)
                  (string.format "Expected 2 restored physics cuboids, got %d" (length start-ys)))
          (sim scene 120)
          (local end-ys (physics-layout-ys scene))
          (local drift (max-abs-drift start-ys end-ys))
          (when (> drift worst-drift)
            (set worst-drift drift))
          (assert (< drift 0.05)
                  (string.format
                   "Expected restored physics cuboids to keep stable Y before/after ticks (cycle=%d drift=%.6f start=(%.6f,%.6f) end=(%.6f,%.6f))"
                   cycle
                   drift
                   (. start-ys 1)
                   (. start-ys 2)
                   (. end-ys 1)
                   (. end-ys 2)))
          (scene:capture-state))))
    (cleanup)
    (when (not ok)
      (error payload))
    (set current-captured payload))
  (assert (< worst-drift 0.05)
          (string.format "Expected worst restore drift < 0.05, got %.6f" worst-drift))
  true)

(fn scene-add-graph-node-cube-adds-physics-and-readds-node []
  (assert bt "Graph node cube test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-graph app.graph)
  (local graph (Graph {:with-start false}))
  (set app.graph graph)

  (let [(ok err)
        (pcall
          (fn []
            (local node (Graph.GraphNode {:key "cube-node"
                                          :label "Node cube label for lod checks and wrapping"}))
            (local element
              (scene:add-graph-node-cube {:node node
                                          :position (glm.vec3 0 16 0)}))
            (assert element "Expected add-graph-node-cube to return an element")
            (assert scene.entity.physics-bodies
                    "Scene should track runtime physics bodies for graph node cubes")
            (local entry (. scene.entity.physics-bodies (length scene.entity.physics-bodies)))
            (assert (and entry entry.body)
                    "Graph node cube should create a runtime rigid body")
            (assert (and element.child element.child.open-graph)
                    "Graph node cube should expose an open-graph action")
            (assert (not (graph:lookup "cube-node"))
                    "Node should not exist in graph before graph action")
            (element.child:open-graph nil nil)
            (assert (graph:lookup "cube-node")
                    "Graph action should add node to graph")
            (graph:remove-nodes [(graph:lookup "cube-node")])
            (assert (not (graph:lookup "cube-node"))
                    "Node should be removable from graph")
            (element.child:open-graph nil nil)
            (assert (graph:lookup "cube-node")
                    "Graph action should re-add node after removal")))]
    (set app.graph original-graph)
    (graph:drop)
    (cleanup)
    (when (not ok)
      (error err))))

(fn scene-restore-graph-node-cube-uses-scene-graph-before-app-binding []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-graph app.graph)
  (set app.graph nil)
  (local graph (Graph {:with-start false}))
  (scene:set-graph graph)
  (local node (Graph.GraphNode {:key "test-node"
                                :label "restore target"}))
  (graph:add-node node {})
  (local initial-count (length (or scene.entity.children [])))

  (local (ok err)
    (pcall
      (fn []
        (scene:restore-state {:panels [{:kind "graph-node-cube"
                                        :node-key "test-node"
                                        :label "restore target"
                                        :size [4 4 4]
                                        :position [0 16 0]
                                        :rotation [1 0 0 0]}]}))))
  (local final-count (length (or scene.entity.children [])))
  (set app.graph original-graph)
  (graph:drop)
  (cleanup)
  (assert ok
          (.. "Expected scene restore to use scene.graph before app binding, got: "
              (tostring err)))
  (assert (= final-count (+ initial-count 1))
          "Scene restore should add graph node cube using scene-owned graph")
  true)

(fn scene-restore-graph-node-cube-sanitizes-poisoned-position []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-graph app.graph)
  (set app.graph nil)
  (local graph (Graph {:with-start false}))
  (scene:set-graph graph)
  (local node (Graph.GraphNode {:key "poisoned-node"
                                :label "poisoned restore target"}))
  (graph:add-node node {})
  (local initial-count (length (or scene.entity.children [])))

  (local (ok err)
    (pcall
      (fn []
        (scene:restore-state {:panels [{:kind "graph-node-cube"
                                        :node-key "poisoned-node"
                                        :label "poisoned restore target"
                                        :size [4 4 4]
                                        :position [1001000 0 0]
                                        :rotation [1 0 0 0]}]}))))
  (local final-count (length (or scene.entity.children [])))
  (local restored-metadata (. (or scene.entity.children []) final-count))
  (local restored-element (and restored-metadata restored-metadata.element))
  (local restored-layout (and restored-element restored-element.layout))
  (set app.graph original-graph)
  (graph:drop)
  (cleanup)
  (assert ok
          (.. "Expected scene restore to sanitize poisoned positions, got: "
              (tostring err)))
  (assert (= final-count (+ initial-count 1))
          "Scene restore should still add graph node cube after position sanitization")
  (assert restored-layout "Restored graph node should have a layout")
  (assert (< (glm.length restored-layout.position) 1000000)
          "Restored graph node position should be kept within vec3 safety threshold")
  true)

(fn scene-restore-graph-node-cube-sanitizes-poisoned-size []
  (local setup (setup-scene))
  (local cleanup setup.cleanup)
  (local scene setup.scene-result.scene)
  (local original-graph app.graph)
  (set app.graph nil)
  (local graph (Graph {:with-start false}))
  (scene:set-graph graph)
  (local node (Graph.GraphNode {:key "poisoned-size-node"
                                :label "poisoned size restore target"}))
  (graph:add-node node {})
  (local initial-count (length (or scene.entity.children [])))

  (local (ok err)
    (pcall
      (fn []
        (scene:restore-state {:panels [{:kind "graph-node-cube"
                                        :node-key "poisoned-size-node"
                                        :label "poisoned size restore target"
                                        :size [1001000 4 4]
                                        :position [0 0 0]
                                        :rotation [1 0 0 0]}]}))))
  (local final-count (length (or scene.entity.children [])))
  (local restored-metadata (. (or scene.entity.children []) final-count))
  (local restored-element (and restored-metadata restored-metadata.element))
  (local restored-layout (and restored-element restored-element.layout))
  (set app.graph original-graph)
  (graph:drop)
  (cleanup)
  (assert ok
          (.. "Expected scene restore to sanitize poisoned sizes, got: "
              (tostring err)))
  (assert (= final-count (+ initial-count 1))
          "Scene restore should still add graph node cube after size sanitization")
  (assert restored-layout "Restored graph node should have a layout")
  (assert (< restored-layout.size.x 1000000)
          "Restored graph node size should be kept within vec3 safety threshold")
  true)

(table.insert tests {:name "Demo browser appends dialogs and movables" :fn demo-browser-adds-dialogs-to-scene})
(table.insert tests {:name "Closing demo dialog removes it from the scene" :fn closing-demo-dialog-removes-positioned-child})
(table.insert tests {:name "Demo browser capture/restore roundtrip" :fn demo-browser-capture-and-restore-roundtrip})
(table.insert tests {:name "Scene capture-state includes default terrain"
                     :fn scene-capture-state-includes-default-terrain})
(table.insert tests {:name "Scene build-default preserves explicit empty terrains"
                     :fn scene-build-default-preserves-explicit-empty-terrains})
(table.insert tests {:name "Scene screen-pos terrain domain hit respects scene root transform"
                     :fn scene-screen-pos-terrain-domain-hit-respects-scene-root-transform})
(table.insert tests {:name "Scene screen-pos terrain domain hit matches exact oracle"
                     :fn scene-screen-pos-terrain-domain-hit-matches-exact-oracle})
(table.insert tests {:name "Scene screen-pos terrain domain fast matches exact oracle"
                     :fn scene-screen-pos-terrain-domain-fast-matches-exact-oracle})
(table.insert tests {:name "Scene screen-pos terrain hit resolves default heightfield"
                     :fn scene-screen-pos-terrain-hit-resolves-default-heightfield})
(table.insert tests {:name "Scene screen-drag terrain target builds rect"
                     :fn scene-screen-drag-terrain-target-builds-rect})
(table.insert tests {:name "Scene screen-drag terrain target respects scene root transform"
                     :fn scene-screen-drag-terrain-target-respects-scene-root-transform})
(table.insert tests {:name "Scene screen-pos terrain domain hit scales logical input to pixel viewport"
                     :fn scene-screen-pos-terrain-domain-hit-scales-logical-input-to-pixel-viewport})
(table.insert tests {:name "Scene screen-pos terrain domain hit default app state matches exact oracle"
                     :fn scene-screen-pos-terrain-domain-hit-default-app-state-matches-exact-oracle})
(table.insert tests {:name "Heightfield target capture fast matches exact default app state"
                     :fn heightfield-target-capture-fast-matches-exact-default-app-state})
(table.insert tests {:name "Heightfield fast raycast matches persisted world fixture"
                     :fn heightfield-fast-raycast-matches-persisted-world-fixture})
(table.insert tests {:name "Heightfield target capture resolves live scene drag"
                     :fn heightfield-target-capture-resolves-live-scene-drag})
(table.insert tests {:name "Heightfield target capture escape cancels selection"
                     :fn heightfield-target-capture-escape-cancels-selection})
(table.insert tests {:name "Heightfield target capture promotes start on first valid drag hit"
                     :fn heightfield-target-capture-promotes-start-on-first-valid-drag-hit})
(table.insert tests {:name "Heightfield target capture keeps last valid hit on release"
                     :fn heightfield-target-capture-keeps-last-valid-hit-on-release})
(table.insert tests {:name "Heightfield target capture does not raycast before drag"
                     :fn heightfield-target-capture-does-not-raycast-before-drag})
(table.insert tests {:name "Heightfield target capture resolves live scene drag with default ray opts"
                     :fn heightfield-target-capture-resolves-live-scene-drag-with-default-ray-opts})
(table.insert tests {:name "Heightfield paint capture stamps live scene samples"
                     :fn heightfield-paint-capture-stamps-live-scene-samples})
(table.insert tests {:name "Heightfield paint capture does not raycast before stroke"
                     :fn heightfield-paint-capture-does-not-raycast-before-stroke})
(table.insert tests {:name "Terrain rect pick state routes engine events"
                     :fn terrain-rect-pick-state-routes-engine-events})
(table.insert tests {:name "Scene terrain selection persists across runtime replace"
                     :fn scene-terrain-selection-persists-across-runtime-replace})
(table.insert tests {:name "Demo entry capture-state persists entry metadata"
                     :fn demo-entry-capture-state-persists-entry-persistence})
(table.insert tests {:name "Scene capture-state requires panel persistence"
                     :fn scene-capture-state-requires-panel-persistence})
(table.insert tests {:name "Scene capture-state requires restore strategy"
                     :fn scene-capture-state-requires-restore-strategy})
(table.insert tests {:name "Scene additions appear in front of the camera" :fn added-dialog-appears-in-front-of-camera})
(table.insert tests {:name "Scene runtime physics body falls" :fn scene-add-physics-body-falls})
(table.insert tests {:name "Scene physics body collides with flat terrain"
                     :fn scene-physics-body-collides-with-flat-terrain})
(table.insert tests {:name "Scene runtime body falls after drag release"
                     :fn scene-runtime-body-falls-after-drag-release})
(table.insert tests {:name "Scene restore physics cuboids world-switch drift check"
                     :fn scene-restore-physics-cuboids-world-switch-drift-check})
(table.insert tests {:name "Scene graph node cube adds physics and graph action"
                     :fn scene-add-graph-node-cube-adds-physics-and-readds-node})
(table.insert tests {:name "Scene restore graph node cube uses scene graph before app binding"
                     :fn scene-restore-graph-node-cube-uses-scene-graph-before-app-binding})
(table.insert tests {:name "Scene restore graph node cube sanitizes poisoned position"
                     :fn scene-restore-graph-node-cube-sanitizes-poisoned-position})
(table.insert tests {:name "Scene restore graph node cube sanitizes poisoned size"
                     :fn scene-restore-graph-node-cube-sanitizes-poisoned-size})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "demo-browser"
                       :tests tests})))

{:name "demo-browser"
 :tests tests
 :main main}
