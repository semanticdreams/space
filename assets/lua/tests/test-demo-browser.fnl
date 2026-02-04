(local glm (require :glm))
(local Scene (require :scene))
(local Camera (require :camera))
(local DemoDialogs (require :demo-dialogs))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))

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
                                           :descender -0.5}}}})
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

(fn setup-scene [opts]
  (local options (or opts {}))
  (local original-scene app.scene)
  (local original-layout-root app.layout-root)
  (local original-movables app.movables)
  (local original-camera app.camera)
  (var scene nil)
  (var movables nil)
  (local icons (make-icons-stub))

  (fn cleanup []
    (when scene
      (scene:drop)
      (set scene nil))
    (set app.scene original-scene)
    (set app.layout-root original-layout-root)
    (set app.movables original-movables)
    (set app.camera original-camera))

  (let [(ok payload)
        (pcall (fn []
                 (set movables (make-stub-movables))
                 (set scene (Scene {:icons icons}))
                 (set app.scene scene)
                 (set app.layout-root scene.layout-root)
                 (set app.movables movables)
                 (when options.camera
                   (set app.camera options.camera))
                 (scene:build-default)
                 {:scene scene :movables movables :icons icons}))]
    (if ok
        {:cleanup cleanup :scene-result payload}
        (do
          (cleanup)
          (error payload)))))

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
                 (assert (= (length scene.entity.__scene_movable_keys) 2)
                         "Movables should track each flex child")
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
                 (assert (= (length scene.entity.__scene_movable_keys) 1)
                         "Movables should track remaining flex children after closing")
                 (assert (>= (length movables.unregistered) 2)
                         "Closing dialog should unregister previous movable entries")))]
    (cleanup)
    (when (not ok)
      (error err))))

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

(table.insert tests {:name "Demo browser appends dialogs and movables" :fn demo-browser-adds-dialogs-to-scene})
(table.insert tests {:name "Closing demo dialog removes it from the scene" :fn closing-demo-dialog-removes-positioned-child})
(table.insert tests {:name "Scene additions appear in front of the camera" :fn added-dialog-appears-in-front-of-camera})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "demo-browser"
                       :tests tests})))

{:name "demo-browser"
 :tests tests
 :main main}
