(local glm (require :glm))
(local PanelTransferModule (require :panel-transfer))
(local PanelTransfer PanelTransferModule.PanelTransfer)
(local DefaultDialog (require :default-dialog))
(local Launcher (require :launcher))
(local LauncherView (require :launcher-view))
(local Scene (require :scene))
(local Hud (require :hud))
(local AppProjection (require :app-projection))

(local tests [])

(fn make-default-camera []
  (local Camera (require :camera))
  (Camera))

(fn make-stub-movables []
  {:entries []
   :register (fn [self widget opts]
               (table.insert self.entries {:widget widget :opts opts}))
   :unregister (fn [self key]
                 (for [i (length (or self.entries [])) 1 -1]
                   (when (= (. self.entries i :key) key)
                     (table.remove self.entries i))))})

(fn make-stub-resizables []
  {:entries []
   :register (fn [self widget opts]
               (table.insert self.entries {:widget widget :key opts.key :opts opts}))
   :unregister (fn [self key]
                 (for [i (length (or self.entries [])) 1 -1]
                   (when (= (. self.entries i :key) key)
                     (table.remove self.entries i))))})

(fn make-stub-intersectables []
  {:insert (fn [_self] nil)
   :remove (fn [_self] nil)})

(fn make-empty-hud-builder []
  (fn [ctx]
    (local {: Layout} (require :layout))
    (local layout (Layout {:name "test-hud-entity"
                           :measurer (fn [self] (set self.measure (glm.vec3 1 1 1)))
                           :layouter (fn [_self] nil)}))
    {:layout layout
     :tiles-root {:children []
                  :attach-child (fn [self element _opts]
                                  (local metadata {:element element})
                                  (table.insert self.children metadata)
                                  metadata)
                  :remove-child (fn [self element]
                                  (for [i (length self.children) 1 -1]
                                    (when (= (. self.children i :element) element)
                                      (table.remove self.children i)
                                      (lua "return true"))))}
     :float-root {:children []
                  :layout (Layout {:name "test-hud-float"
                                   :measurer (fn [self] (set self.measure (glm.vec3 1 1 1)))
                                   :layouter (fn [_self] nil)})
                  :attach-child (fn [self element _opts]
                                  (local metadata {:element element})
                                  (table.insert self.children metadata)
                                  metadata)
                  :remove-child (fn [self element]
                                  (for [i (length self.children) 1 -1]
                                    (when (= (. self.children i :element) element)
                                      (table.remove self.children i)
                                      (lua "return true"))))}
     :overlay-root {:children []
                    :add-overlay-child true
                    :add-child true
                    :remove-child (fn [_self _element] true)
                    :remove-overlay-child true}
     :middle-overlay-root {:children []
                           :add-overlay-child true
                           :add-child true
                           :remove-child (fn [_self _element] true)
                           :remove-overlay-child true}
     :drop (fn [_self] nil)
     :update (fn [_self] nil)}))

(fn save-app-state []
  {:scene app.scene
   :hud app.hud
   :layout-root app.layout-root
   :clickables app.clickables
   :hoverables app.hoverables
   :movables app.movables
   :resizables app.resizables
   :intersectables app.intersectables
   :panel-transfer app.panel-transfer
   :launcher app.launcher
   :launcher-runtime-snap (when app.launcher (app.launcher:snapshot-runtime))
   :menu-manager app.menu-manager
   :camera app.camera
   :create-default-projection app.create-default-projection
   :viewport app.viewport})

(fn restore-app-state [saved]
  (set app.scene saved.scene)
  (set app.hud saved.hud)
  (set app.layout-root saved.layout-root)
  (set app.clickables saved.clickables)
  (set app.hoverables saved.hoverables)
  (set app.movables saved.movables)
  (set app.resizables saved.resizables)
  (set app.intersectables saved.intersectables)
  (set app.panel-transfer saved.panel-transfer)
  (set app.launcher saved.launcher)
  (when (and app.launcher saved.launcher-runtime-snap)
    (app.launcher:restore-runtime saved.launcher-runtime-snap))
  (set app.menu-manager saved.menu-manager)
  (set app.camera saved.camera)
  (set app.create-default-projection saved.create-default-projection)
  (set app.viewport saved.viewport))

(fn make-icons-stub []
  (local glyph {:advance 1
                :planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}
               :advance 1})
  (local stub {:font font
               :codepoints {:refresh 4242
                            :close 4242
                            :cancel 4242
                            :move_item 4242
                            :wallet 4242
                            :dashboard 4242
                            :view_in_ar 4242
                            :space_dashboard 4242
                            :open_with 4242
                            :star 4242}})
  (set stub.get
       (fn [self name]
         (local value (. self.codepoints name))
         (assert value (.. "Missing icon " name))
         value))
  (set stub.resolve
       (fn [self name]
         (local code (self:get name))
         {:type :font
          :codepoint code
          :font self.font}))
  stub)

(fn setup-app-stubs []
  (set app.clickables
       {:register (fn [_self] nil)
        :unregister (fn [_self] nil)
        :register-right-click (fn [_self] nil)
        :unregister-right-click (fn [_self] nil)
        :register-double-click (fn [_self] nil)
        :unregister-double-click (fn [_self] nil)})
  (set app.hoverables
       {:register (fn [_self] nil)
        :unregister (fn [_self] nil)})
  (set app.movables (make-stub-movables))
  (set app.resizables (make-stub-resizables))
  (set app.intersectables (make-stub-intersectables))
  (set app.launcher (Launcher {}))
  (app.launcher:clear-runtime)
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (set app.create-default-projection AppProjection.create-default-projection)
  (set app.panel-transfer (PanelTransfer)))

(fn with-scene-and-hud [f]
  (var scene nil)
  (var hud nil)
  (var camera nil)
  (local saved (save-app-state))
  (local icons (make-icons-stub))
  (fn setup-body []
    (setup-app-stubs)
    (set camera (make-default-camera))
    (set app.camera camera)
    (set scene (Scene {:icons icons
                       :camera camera}))
    (set scene.projection (glm.perspective 0.8 1.33 0.1 1000.0))
    (set app.scene scene)
    (set app.layout-root scene.layout-root)
    (local sandbox-slot (scene:activate-activity-slot "sandbox"))
    (assert sandbox-slot "panel-transfer with-scene-and-hud requires a valid sandbox slot")
    (scene:build-default)
    (set hud (Hud {:scene scene
                   :icons icons}))
    (set app.hud hud)
    (hud:build (make-empty-hud-builder))
    (hud:update-projection app.viewport)
    (hud:update)
    (f scene hud))
  (fn cleanup []
    (when scene (scene:drop) (set scene nil))
    (when hud (hud:drop) (set hud nil))
    (when camera (camera:drop) (set camera nil))
    (restore-app-state saved))
  (local (ok err) (pcall setup-body))
  (cleanup)
  (when (not ok)
    (error err)))

(fn find-move-action [dialog]
  (local target (or dialog.__front_widget dialog.front dialog))
  (local titlebar-meta (. target.children 1))
  (local titlebar titlebar-meta.element)
  (if (not titlebar)
      (do
        (var action nil)
        (fn scan [obj depth]
          (when (and (not action) obj depth (< depth 10))
            (when (= (type obj) :table)
              (when (and obj.icon (= obj.icon "move_item") obj.on-click)
                (set action obj))
              (each [_ v (pairs obj)]
                (when (not action)
                  (scan v (+ depth 1)))))))
        (scan dialog 0)
        action)
      (do
        (local title-flex (. titlebar.children 2))
        (var action-row-meta nil)
        (when title-flex
          (set action-row-meta (. title-flex.children (length title-flex.children))))
        (var button nil)
        (when (and action-row-meta action-row-meta.element)
          (fn find-button [obj depth]
            (when (and (not button) obj depth (< depth 5))
              (when (= (type obj) :table)
                (when (and obj.icon (= obj.icon "move_item") obj.on-click)
                  (set button obj))
                (each [_ v (pairs obj)]
                  (when (not button)
                    (find-button v (+ depth 1)))))))
          (find-button action-row-meta.element 0))
        button)))

(fn register-receiver-and-list-available []
  (local pt (PanelTransfer))
  (assert (= (length (pt:available-receivers)) 0)
          "Empty registry should have no receivers")

  (local called? {:count 0})
  (pt:register-receiver
    {:id :test-a
     :label "Test A"
     :icon "star"
     :target-fn (fn []
                  (set called?.count (+ called?.count 1))
                  {:id :target-a})})
  (local available (pt:available-receivers))
  (assert (= (length available) 1))
  (assert (= (. available 1 :id) "test-a"))
  (assert (= (. available 1 :label) "Test A"))
  (assert (= (. available 1 :icon) "star"))
  (assert called?.count "target-fn should have been called"))

(fn receiver-with-nil-target-is-excluded []
  (local pt (PanelTransfer))
  (pt:register-receiver
    {:id :present
     :label "Present"
     :target-fn (fn [] {:id :t})})
  (pt:register-receiver
    {:id :absent
     :label "Absent"
     :target-fn (fn [] nil)})
  (local available (pt:available-receivers))
  (assert (= (length available) 1))
  (assert (= (. available 1 :id) "present")))

(fn unregister-removes-receiver []
  (local pt (PanelTransfer))
  (pt:register-receiver
    {:id :a :label "A" :target-fn (fn [] {:id :t-a})})
  (pt:register-receiver
    {:id :b :label "B" :target-fn (fn [] {:id :t-b})})
  (pt:unregister-receiver "a")
  (local available (pt:available-receivers))
  (assert (= (length available) 1))
  (assert (= (. available 1 :id) "b")))

(fn find-receiver-matches-target []
  (local pt (PanelTransfer))
  (local target {:id :t})
  (pt:register-receiver
    {:id :a :label "A" :target-fn (fn [] target)})
  (pt:register-receiver
    {:id :b :label "B" :target-fn (fn [] {:id :other})})
  (local found (pt:find-receiver-for-target target))
  (assert found "Should find matching receiver")
  (assert (= found.id "a")))

(fn find-receiver-returns-nil-for-unknown-target []
  (local pt (PanelTransfer))
  (pt:register-receiver
    {:id :a :label "A" :target-fn (fn [] {:id :t})})
  (assert (= (pt:find-receiver-for-target {:id :unknown}) nil)))

(fn find-receiver-by-id-looks-up-by-string-id []
  (local pt (PanelTransfer))
  (pt:register-receiver
    {:id :first :label "First" :target-fn (fn [] {:id :t-a})})
  (pt:register-receiver
    {:id :second :label "Second" :target-fn (fn [] {:id :t-b})})
  (local found (pt:find-receiver-by-id "second"))
  (assert found "Should find receiver by string id")
  (assert (= found.id "second") "Should match on the correct receiver id")
  (assert (= found.label "Second") "Should return the complete receiver record"))

(fn find-receiver-by-id-returns-nil-for-unknown-id []
  (local pt (PanelTransfer))
  (pt:register-receiver
    {:id :only :label "Only" :target-fn (fn [] {:id :t})})
  (assert (= (pt:find-receiver-by-id "nonexistent") nil)
          "Should return nil for unknown id"))

(fn receiver-target-fn-error-is-not-silent []
  (local pt (PanelTransfer))
  (pt:register-receiver
    {:id :broken
     :label "Broken"
     :target-fn (fn [] (error "broken"))})
  (pt:register-receiver
    {:id :ok
     :label "OK"
     :target-fn (fn [] {:id :t})})
  (var reached? false)
  (pcall (fn []
            (pt:available-receivers)
            (set reached? true)))
  (assert (not reached?)
          "target-fn errors should propagate, not be silently excluded"))

(fn requires-string-id []
  (var caught? false)
  (pcall (fn []
            (var pt (PanelTransfer))
            (pt:register-receiver {:label "Missing ID" :target-fn (fn [] {:id :t})})
            (set caught? true)))
  (assert (not caught?)
          "register-receiver should error when id is missing"))

(fn register-receiver-rejects-duplicate-id []
  (local pt (PanelTransfer))
  (pt:register-receiver {:id "dup" :label "First" :target-fn (fn [] {:id :t})})
  (var caught? false)
  (pcall (fn []
            (pt:register-receiver {:id "dup" :label "Second" :target-fn (fn [] {:id :other})})
            (set caught? true)))
  (assert (not caught?)
          "register-receiver should error on duplicate id"))

(fn requires-string-label []
  (var caught? false)
  (pcall (fn []
            (var pt (PanelTransfer))
            (pt:register-receiver {:id "no-label" :target-fn (fn [] {:id :t})})
            (set caught? true)))
  (assert (not caught?)
          "register-receiver should error when label is missing"))

(fn requires-function-target-fn []
  (var caught? false)
  (pcall (fn []
            (var pt (PanelTransfer))
            (pt:register-receiver {:id "bad" :label "Bad" :target-fn "not-a-fn"})
            (set caught? true)))
  (assert (not caught?)
          "register-receiver should error when target-fn is not a function"))

(fn requires-rollback-when-receive-provided []
  (var caught? false)
  (pcall (fn []
            (var pt (PanelTransfer))
            (pt:register-receiver {:id "no-rollback"
                                   :label "No Rollback"
                                   :target-fn (fn [] {:id :t})
                                   :receive (fn [] nil)})
            (set caught? true)))
  (assert (not caught?) "register-receiver should error when :receive is provided without :rollback"))

(fn requires-receive-to-be-function []
  (var caught? false)
  (pcall (fn []
            (var pt (PanelTransfer))
            (pt:register-receiver {:id "bad-receive"
                                   :label "Bad Receive"
                                   :target-fn (fn [] {:id :t})
                                   :receive "not-a-fn"
                                   :rollback (fn [] nil)})
            (set caught? true)))
  (assert (not caught?) "register-receiver should error when :receive is not a function"))

(fn requires-rollback-to-be-function []
  (var caught? false)
  (pcall (fn []
            (var pt (PanelTransfer))
            (pt:register-receiver {:id "bad-rollback"
                                   :label "Bad Rollback"
                                   :target-fn (fn [] {:id :t})
                                   :rollback "not-a-fn"})
            (set caught? true)))
  (assert (not caught?) "register-receiver should error when :rollback is not a function"))

(fn default-dialog-move-item-opens-menu-when-panel-transfer-present []
  (with-scene-and-hud
    (fn [scene hud]
      (app.panel-transfer:register-receiver
        {:id :hud
         :label "HUD"
         :icon "dashboard"
         :target-fn (fn [] app.hud)})
      (app.panel-transfer:register-receiver
        {:id :scene
         :label "Scene"
         :icon "view_in_ar"
         :target-fn (fn [] app.scene)})

      (local menu-opened {:events []})
      (set app.menu-manager
           {:open (fn [_self opts]
                    (table.insert menu-opened.events opts))})

      (local child-builder
        (fn [_ctx]
          (local {: Layout} (require :layout))
          {:layout (Layout {:name "test-child"})
           :drop (fn [_self] nil)}))
      (local dialog-builder
        (DefaultDialog {:title "Test Dialog"
                        :child child-builder}))
      (local element (app.scene:add-panel-child
                       {:builder dialog-builder
                        :position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)}))
      (assert element "dialog should be created")

      (local move-action (find-move-action element))
      (assert move-action "should find move_item action")
      (move-action:on-click {:screen {:x 100 :y 200}})

      (assert (= (length menu-opened.events) 1)
              "move_item should open menu when panel-transfer present")
      (local actions (. menu-opened.events 1 :actions))
      (assert actions "menu should have actions")
      (assert (>= (length actions) 1) "menu should list at least one receiver")
      (var has-hud false)
      (each [_ action (ipairs actions)]
        (when (string.find (or action.name "") "HUD")
          (set has-hud true)))
      (assert has-hud "menu should include HUD receiver"))))

(fn default-dialog-move-item-falls-back-without-panel-transfer []
  (with-scene-and-hud
    (fn [scene hud]
      (set app.panel-transfer nil)

      (local child-builder
        (fn [_ctx]
          (local {: Layout} (require :layout))
          {:layout (Layout {:name "test-child"})
           :drop (fn [_self] nil)}))
      (local dialog-builder
        (DefaultDialog {:title "Legacy Toggle"
                        :child child-builder}))
      (local element (app.scene:add-panel-child
                       {:builder dialog-builder
                        :position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)}))
      (assert element "dialog should be created")
      (assert (= (length scene.scene-children) 1)
              "scene should contain dialog before toggle")

      (local move-action (find-move-action element))
      (move-action:on-click {:button 1})

      (assert (= (length scene.scene-children) 0)
              "dialog should detach from scene after toggle")
      (assert (= (length hud.tiles.children) 1)
              "dialog should appear in HUD tiles after toggle"))))

(fn default-dialog-menu-transfer-moves-between-targets []
  (with-scene-and-hud
    (fn [scene hud]
      (local menu-captured {:last-action nil})
      (set app.menu-manager
           {:open (fn [_self opts]
                    (when (and opts.actions (> (length opts.actions) 0))
                      (set menu-captured.last-action (. opts.actions 1))))})

      (app.panel-transfer:register-receiver
        {:id :hud
         :label "HUD"
         :icon "dashboard"
         :target-fn (fn [] app.hud)})
      (app.panel-transfer:register-receiver
        {:id :scene
         :label "Scene"
         :icon "view_in_ar"
         :target-fn (fn [] app.scene)})

      (local child-builder
        (fn [_ctx]
          (local {: Layout} (require :layout))
          {:layout (Layout {:name "transfer-child"})
           :drop (fn [_self] nil)}))

      (local dialog-builder
        (DefaultDialog {:title "Transfer Dialog"
                        :child child-builder}))
      (local element (app.scene:add-panel-child
                       {:builder dialog-builder
                        :position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)}))
      (assert element)

      (local move-action (find-move-action element))
      (move-action:on-click {:screen {:x 100 :y 200}})

      (assert (not (= menu-captured.last-action nil))
              "menu should be shown")
      (assert menu-captured.last-action.fn "action should have fn")

      (assert (= (length scene.scene-children) 1)
              "scene should still have dialog before transfer")
      (menu-captured.last-action.fn nil nil)

      (assert (= (length scene.scene-children) 0)
              "dialog should detach from scene after transfer")
      (assert (= (length hud.tiles.children) 1)
              "dialog should appear in HUD after transfer"))))

(fn custom-receiver-receive-is-called []
  (with-scene-and-hud
    (fn [scene hud]
      (local captured {:called false :payload nil})
      (local stub-target {:id :stub
                          :add-panel-child (fn [_self _opts] {:layout {:name "stub-layout"} :drop (fn [_] nil)})})
       (app.panel-transfer:register-receiver
         {:id :custom
          :label "Custom"
          :icon "build"
          :target-fn (fn [] stub-target)
          :receive (fn [recv payload]
                     (set captured.called true)
                     (set captured.payload payload)
                     (stub-target:add-panel-child payload))
          :rollback (fn [_r el]
                      (when (and el el.drop)
                        (el:drop))
                      true)})
      (app.panel-transfer:register-receiver
        {:id :hud
         :label "HUD"
         :icon "dashboard"
         :target-fn (fn [] app.hud)})

      (local menu-opened {:events []})
      (set app.menu-manager
           {:open (fn [_self opts]
                    (table.insert menu-opened.events opts))})

      (local child-builder
        (fn [_ctx]
          (local {: Layout} (require :layout))
          {:layout (Layout {:name "test-child"})
           :drop (fn [_self] nil)}))
      (local dialog-builder
        (DefaultDialog {:title "Custom Receive Test"
                        :child child-builder}))
      (local element (app.scene:add-panel-child
                       {:builder dialog-builder
                        :position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)}))
      (assert element)

      (local move-action (find-move-action element))
      (move-action:on-click {:screen {:x 100 :y 200}})

      (assert (= (length menu-opened.events) 1))
      (local actions (. menu-opened.events 1 :actions))
      (var custom-action nil)
      (each [_ action (ipairs actions)]
        (when (string.find (or action.name "") "Custom")
          (set custom-action action)))
      (assert custom-action "menu should include Custom receiver")
      (assert (not captured.called) "receive should not be called before transfer")

      (custom-action.fn nil nil)
      (assert captured.called "receive should be called on transfer")
      (assert captured.payload.builder "receive payload should include builder")
      (assert captured.payload.builder-options "receive payload should include builder-options"))))

(fn transfer-rolls-back-on-detach-failure []
  (local pt (PanelTransfer))
  (local received-dropped? {:dropped false})
  (local source-dropped? {:dropped false})
  (local received-element {:layout {:name "received"}
                           :drop (fn [_self] (set received-dropped?.dropped true))})
  (local source-element {:layout {:name "source-panel"}
                         :drop (fn [_self] (set source-dropped?.dropped true))})

  (local stub-dest {:id :dest
                    :add-panel-child (fn [_self _opts] received-element)})
  (local stub-source {:remove-panel-child (fn [_self _el] false)})

  (local recv {:target stub-dest
               :id :dest
               :label "Dest"
               :receive (fn [_r payload] (stub-dest:add-panel-child payload))})

  (local payload {:builder (fn [_ctx] source-element)
                  :persistence {:kind :test}})

  (local (ok err) (pcall (fn [] (pt:transfer-panel recv stub-source source-element payload))))
  (assert (not ok) "transfer-panel should throw on detach failure")
  (assert (not source-dropped?.dropped) "source element should not be dropped on failed detach")
  (assert received-dropped?.dropped "destination element should be dropped on rollback"))

(fn transfer-rolls-back-when-detach-throws []
  (local pt (PanelTransfer))
  (local received-dropped? {:dropped false})
  (local received-element {:layout {:name "received"}
                           :drop (fn [_self] (set received-dropped?.dropped true))})
  (local source-element {:layout {:name "source-panel"}
                         :drop (fn [_self] nil)})
  (local stub-dest {:id :dest
                    :add-panel-child (fn [_self _opts] received-element)})
  (local stub-source {:remove-panel-child (fn [_self _el]
                                            (error "source detach exploded"))})
  (local recv {:target stub-dest
               :id :dest
               :label "Dest"
               :receive (fn [_r payload] (stub-dest:add-panel-child payload))})
  (local payload {:builder (fn [_ctx] source-element)
                  :persistence {:kind :test}})
  (local (ok err) (pcall (fn [] (pt:transfer-panel recv stub-source source-element payload))))
  (assert (not ok) "transfer-panel should throw when source detach throws")
  (assert (string.find (tostring err) "source detach exploded" 1 true)
          "transfer-panel should preserve detach error context")
  (assert received-dropped?.dropped "destination element should be dropped on thrown detach rollback"))

(fn transfer-rollback-drops-after-dest-remove-panel-child []
  (local pt (PanelTransfer))
  (local received-dropped? {:dropped false})
  (local dest-removed-child? {:removed false})
  (local source-dropped? {:dropped false})
  (local received-element {:layout {:name "received"}
                           :drop (fn [_self] (set received-dropped?.dropped true))})
  (local source-element {:layout {:name "source-panel"}
                         :drop (fn [_self] (set source-dropped?.dropped true))})

  (local stub-dest {:id :hud-like
                    :add-panel-child (fn [_self _opts] received-element)
                    :remove-panel-child (fn [_self el]
                                          (set dest-removed-child?.removed true)
                                          true)})
  (local stub-source {:remove-panel-child (fn [_self _el] false)})

  (local recv {:target stub-dest
               :id :hud-like
               :label "HudLike"
               :receive (fn [_r payload] (stub-dest:add-panel-child payload))
                :rollback (fn [_r el]
                            (var removed false)
                            (when (and stub-dest stub-dest.remove-panel-child)
                              (set removed (stub-dest:remove-panel-child el)))
                            (when (and removed el el.drop)
                              (el:drop))
                            removed)})

  (local payload {:builder (fn [_ctx] source-element)
                  :persistence {:kind :test}})

  (local (ok err) (pcall (fn [] (pt:transfer-panel recv stub-source source-element payload))))
  (assert (not ok) "transfer-panel should throw on detach failure")
  (assert (not source-dropped?.dropped) "source element should not be dropped on failed detach")
  (assert dest-removed-child?.removed "destination element should be removed from target tree")
  (assert received-dropped?.dropped "destination element should be dropped on rollback even when target has remove-panel-child"))

(fn transfer-rollback-calls-custom-rollback-hook []
  (local pt (PanelTransfer))
  (local rollback-called? {:called false})
  (local received-element {:layout {:name "received"}
                           :drop (fn [_self] nil)})
  (local source-element {:layout {:name "source-panel"}
                         :drop (fn [_self] nil)})

  (local stub-dest {:id :custom
                    :add-panel-child (fn [_self _opts] received-element)})
  (local stub-source {:remove-panel-child (fn [_self _el] false)})

  (local recv {:target stub-dest
               :id :custom
               :label "Custom"
               :receive (fn [_r payload] (stub-dest:add-panel-child payload))
                :rollback (fn [_r el]
                            (set rollback-called?.called true)
                            (when (and el el.drop)
                              (el:drop))
                            true)})

  (local payload {:builder (fn [_ctx] source-element)
                  :persistence {:kind :test}})

  (local (ok err) (pcall (fn [] (pt:transfer-panel recv stub-source source-element payload))))
  (assert (not ok) "transfer-panel should throw on detach failure")
  (assert rollback-called?.called "custom rollback hook should be called on failed transfer"))

(fn dialog-move-passes-custom-rollback-to-transfer-panel []
  (with-scene-and-hud
    (fn [scene hud]
      (local rollback-called? {:called false})
      (local stub-target {:id :custom-dest
                          :add-panel-child (fn [_self _opts]
                                             {:layout {:name "received"}
                                              :drop (fn [_self] nil)})})
      (app.panel-transfer:register-receiver
        {:id :custom
         :label "Custom"
         :icon "build"
         :target-fn (fn [] stub-target)
          :rollback (fn [_r el]
                      (set rollback-called?.called true)
                      (when (and el el.drop)
                        (el:drop))
                      true)})
      (app.panel-transfer:register-receiver
        {:id :hud
         :label "HUD"
         :icon "dashboard"
         :target-fn (fn [] app.hud)})

      (local menu-opened {:events []})
      (set app.menu-manager
           {:open (fn [_self opts]
                    (table.insert menu-opened.events opts))})

      (local child-builder
        (fn [_ctx]
          (local {: Layout} (require :layout))
          {:layout (Layout {:name "test-child"})
           :drop (fn [_self] nil)}))
      (local dialog-builder
        (DefaultDialog {:title "Rollback Pass-Through"
                        :child child-builder}))
      (local element (app.scene:add-panel-child
                       {:builder dialog-builder
                        :position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)}))
      (assert element)

      (local scene-remove scene.remove-panel-child)
      (set scene.remove-panel-child (fn [_self _el] false))

      (local move-action (find-move-action element))
      (move-action:on-click {:screen {:x 100 :y 200}})

      (assert (= (length menu-opened.events) 1))
      (local actions (. menu-opened.events 1 :actions))
      (var custom-action nil)
      (each [_ action (ipairs actions)]
        (when (string.find (or action.name "") "Custom")
          (set custom-action action)))
      (assert custom-action "menu should include Custom receiver")

      (local (ok err) (pcall (fn [] (custom-action.fn nil nil))))
      (assert (not ok) "transfer should throw on detach failure")
      (assert rollback-called?.called "custom rollback should be called through dialog move path")

      (set scene.remove-panel-child scene-remove))))

(fn transfer-rollback-scene-like-dest-no-double-drop []
  (local pt (PanelTransfer))
  (local drop-count {:count 0})
  (local received-element {:layout {:name "received"}
                           :drop (fn [_self] (set drop-count.count (+ drop-count.count 1)))})
  (local source-element {:layout {:name "source-panel"}
                         :drop (fn [_self] nil)})

  (local stub-dest {:id :scene-like
                    :add-panel-child (fn [_self _opts] received-element)
                    :remove-panel-child (fn [_self el]
                                          (when (and el el.drop)
                                            (el:drop))
                                          true)})
  (local stub-source {:remove-panel-child (fn [_self _el] false)})

  (local recv {:target stub-dest
               :id :scene-like
               :label "SceneLike"
               :receive (fn [_r payload] (stub-dest:add-panel-child payload))})

  (local payload {:builder (fn [_ctx] source-element)
                  :persistence {:kind :test}})

  (local (ok err) (pcall (fn [] (pt:transfer-panel recv stub-source source-element payload))))
  (assert (not ok) "transfer-panel should throw on detach failure")
  (assert (= drop-count.count 1)
          (.. "destination element should be dropped exactly once during rollback, got "
              (tostring drop-count.count))))

(fn transfer-rollback-no-drop-when-removal-fails []
  (local pt (PanelTransfer))
  (local dropped? {:dropped false})
  (local removed-called? {:called false})
  (local received-element {:layout {:name "received"}
                           :drop (fn [_self] (set dropped?.dropped true))})
  (local source-element {:layout {:name "source-panel"}
                         :drop (fn [_self] nil)})

  (local stub-dest {:id :stubborn
                    :add-panel-child (fn [_self _opts] received-element)
                    :remove-panel-child (fn [_self el]
                                          (set removed-called?.called true)
                                          false)})
  (local stub-source {:remove-panel-child (fn [_self _el] false)})

  (local recv {:target stub-dest
               :id :stubborn
               :label "Stubborn"
               :receive (fn [_r payload] (stub-dest:add-panel-child payload))
                :rollback (fn [_r el]
                            (var removed false)
                            (when (and stub-dest stub-dest.remove-panel-child)
                              (set removed (stub-dest:remove-panel-child el)))
                            (when (and removed el el.drop)
                              (el:drop))
                            removed)})

  (local payload {:builder (fn [_ctx] source-element)
                  :persistence {:kind :test}})

  (local (ok err) (pcall (fn [] (pt:transfer-panel recv stub-source source-element payload))))
  (assert (not ok) "transfer-panel should throw on detach failure")
  (assert removed-called?.called "remove-panel-child should be called on destination")
  (assert (not dropped?.dropped) "element should not be dropped when removal fails"))

(table.insert tests {:name "register receiver and list available" :fn register-receiver-and-list-available})
(table.insert tests {:name "receiver with nil target is excluded" :fn receiver-with-nil-target-is-excluded})
(table.insert tests {:name "unregister removes receiver" :fn unregister-removes-receiver})
(table.insert tests {:name "find receiver matches target" :fn find-receiver-matches-target})
(table.insert tests {:name "find receiver returns nil for unknown target" :fn find-receiver-returns-nil-for-unknown-target})
(table.insert tests {:name "find receiver by id looks up by string id" :fn find-receiver-by-id-looks-up-by-string-id})
(table.insert tests {:name "find receiver by id returns nil for unknown id" :fn find-receiver-by-id-returns-nil-for-unknown-id})
(table.insert tests {:name "receiver target-fn error is not silent" :fn receiver-target-fn-error-is-not-silent})
(table.insert tests {:name "requires string id" :fn requires-string-id})
(table.insert tests {:name "register receiver rejects duplicate id" :fn register-receiver-rejects-duplicate-id})
(table.insert tests {:name "requires string label" :fn requires-string-label})
(table.insert tests {:name "requires function target-fn" :fn requires-function-target-fn})
(table.insert tests {:name "requires rollback when receive provided" :fn requires-rollback-when-receive-provided})
(table.insert tests {:name "requires receive to be function" :fn requires-receive-to-be-function})
(table.insert tests {:name "requires rollback to be function" :fn requires-rollback-to-be-function})
(table.insert tests {:name "default dialog move item opens menu when panel transfer present" :fn default-dialog-move-item-opens-menu-when-panel-transfer-present})
(table.insert tests {:name "default dialog move item falls back without panel transfer" :fn default-dialog-move-item-falls-back-without-panel-transfer})
(table.insert tests {:name "default dialog menu transfer moves between targets" :fn default-dialog-menu-transfer-moves-between-targets})
(table.insert tests {:name "custom receiver receive is called on transfer" :fn custom-receiver-receive-is-called})
(table.insert tests {:name "transfer rolls back on detach failure" :fn transfer-rolls-back-on-detach-failure})
(table.insert tests {:name "transfer rolls back when detach throws" :fn transfer-rolls-back-when-detach-throws})
(table.insert tests {:name "transfer rollback drops after dest remove-panel-child" :fn transfer-rollback-drops-after-dest-remove-panel-child})
(table.insert tests {:name "transfer rollback calls custom rollback hook" :fn transfer-rollback-calls-custom-rollback-hook})
(table.insert tests {:name "dialog move passes custom rollback to transfer panel" :fn dialog-move-passes-custom-rollback-to-transfer-panel})
(table.insert tests {:name "transfer rollback scene-like dest no double drop" :fn transfer-rollback-scene-like-dest-no-double-drop})
(table.insert tests {:name "transfer rollback no drop when removal fails" :fn transfer-rollback-no-drop-when-removal-fails})

(fn default-dialog-transfer-builder-uses-provided-builder []
  (with-scene-and-hud
    (fn [scene hud]
      (local transfer-called? {:value false})
      (local child-builder
        (fn [_ctx]
          (local {: Layout} (require :layout))
          {:layout (Layout {:name "transfer-child"})
           :drop (fn [_self] nil)}))
      (local tracking-builder
        (fn [ctx runtime-opts]
          (set transfer-called?.value true)
          ((DefaultDialog {:title "Tracked Transferable"
                           :child child-builder})
           ctx runtime-opts)))
      (local dialog-builder
        (DefaultDialog {:title "Tracked Transferable"
                        :child child-builder
                        :transfer-builder tracking-builder}))
      (local element (app.scene:add-panel-child
                       {:builder dialog-builder
                        :position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)}))
      (assert element)
      (local menu-captured {:last-action nil})
      (set app.menu-manager
           {:open (fn [_self opts]
                    (when (and opts.actions (> (length opts.actions) 0))
                      (set menu-captured.last-action (. opts.actions 1))))})
      (app.panel-transfer:register-receiver
        {:id :scene :label "Scene" :icon "view_in_ar"
         :target-fn (fn [] app.scene)})
      (app.panel-transfer:register-receiver
        {:id :hud :label "HUD" :icon "dashboard"
         :target-fn (fn [] app.hud)})
      (local move-action (find-move-action element))
      (move-action:on-click {:screen {:x 100 :y 200}})
      (assert (not (= menu-captured.last-action nil)) "menu should be shown")
      (set transfer-called?.value false)
      (menu-captured.last-action.fn nil nil)
      (assert transfer-called?.value
              "transfer-builder should be used when transferring")
      (assert (= (length scene.scene-children) 0)
              "dialog should detach from scene")
      (assert (= (length hud.tiles.children) 1)
              "dialog should appear in HUD"))))
(table.insert tests {:name "default dialog transfer-builder uses provided builder on transfer" :fn default-dialog-transfer-builder-uses-provided-builder})

(fn launcher-view-transfer-preserves-search-and-set-items []
  (with-scene-and-hud
    (fn [scene hud]
      (local menu-captured {:last-action nil})
      (set app.menu-manager
           {:open (fn [_self opts]
                    (when (and opts.actions (> (length opts.actions) 0))
                      (set menu-captured.last-action (. opts.actions 1))))})
      (app.panel-transfer:register-receiver
        {:id :scene :label "Scene" :icon "view_in_ar"
         :target-fn (fn [] app.scene)})
      (app.panel-transfer:register-receiver
        {:id :hud :label "HUD" :icon "dashboard"
         :target-fn (fn [] app.hud)})
      (app.launcher:register {:name "Runtime Game" :run (fn [] nil)})

      (local dialog-builder (LauncherView {:title "Test Launcher"}))
      (local element (app.scene:add-panel-child
                       {:builder dialog-builder
                        :position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)}))
      (assert element)
      (local launcher (or element.front element))
      (assert launcher.search "LauncherView should have search")
      (assert launcher.set-items "LauncherView should have set-items")
      (assert launcher.set-query "LauncherView should have set-query")
      (var found-runtime? false)
      (each [_ pair (ipairs launcher.search.items)]
        (when (= (. pair 2) "Runtime Game")
          (set found-runtime? true)))
      (assert found-runtime? "LauncherView should include app.launcher runtime entries")

      (local move-action (find-move-action element))
      (assert move-action "should have move action")
      (move-action:on-click {:screen {:x 100 :y 200}})
      (assert (not (= menu-captured.last-action nil)) "menu should appear")
      (menu-captured.last-action.fn nil nil)

      (assert (= (length scene.scene-children) 0) "dialog should detach from scene")
      (assert (= (length hud.tiles.children) 1) "dialog should appear in HUD tiles")

      (local hud-wrapper (. hud.tiles.children 1 :element))
      (local hud-element (or hud-wrapper.__hud_inner hud-wrapper))
      (assert hud-element "transferred element should exist")
      (local transferred (or hud-element.front hud-element))
      (assert transferred.search
              "transferred LauncherView should have search")
      (assert transferred.set-items
              "transferred LauncherView should have set-items")
      (assert transferred.set-query
              "transferred LauncherView should have set-query"))))
(table.insert tests {:name "launcher view transfer preserves search and set-items on transfer" :fn launcher-view-transfer-preserves-search-and-set-items})

(fn scene-transfer-goes-to-active-slot-not-global-root []
  (with-scene-and-hud
    (fn [scene hud]
      (local sandbox-slot (. scene.activity-slots "sandbox"))
      (assert sandbox-slot "panel-transfer regression requires a sandbox slot")
      (assert sandbox-slot.visible? "Sandbox slot must be visible while active")
      (assert (= scene.active-activity-slot-id "sandbox")
              "Sandbox must be the active scene slot")
      (local child-builder
        (fn [_ctx]
          (local {: Layout} (require :layout))
          {:layout (Layout {:name "slot-test-child"})
           :drop (fn [_self] nil)}))
      (local dialog-builder
        (DefaultDialog {:title "Slot Transfer Test"
                        :child child-builder}))
      (local element (app.scene:add-panel-child
                       {:builder dialog-builder
                        :position (glm.vec3 0 0 0)
                        :rotation (glm.quat 1 0 0 0)
                        :persistence {:kind "test-dialog"}}))
      (assert element "dialog should be created in the active slot")
      ;; Content must land in the active scene-children (aliased from the slot)
      (assert (= (length scene.scene-children) 1)
              "Transferred content must be in the active slot's scene-children")
      ;; The panel must be in the sandbox slot's scene-children (not a global list).
      ;; The slot aliases scene.scene-children while active, so any addition
      ;; lands in the active slot. After HUD transfer, the slot list is cleared.
      (app.panel-transfer:register-receiver
        {:id :hud
         :label "HUD"
         :icon "dashboard"
         :target-fn (fn [] app.hud)})
      (app.panel-transfer:register-receiver
        {:id :scene
         :label "Scene"
         :icon "view_in_ar"
         :target-fn (fn [] app.scene)})
      (local menu-captured {:last-action nil})
      (set app.menu-manager
           {:open (fn [_self opts]
                    (when (and opts.actions (> (length opts.actions) 0))
                      (set menu-captured.last-action (. opts.actions 1))))})
      (local move-action (find-move-action element))
      (move-action:on-click {:screen {:x 100 :y 200}})
      (assert (not (= menu-captured.last-action nil)) "menu should be shown")
      (menu-captured.last-action.fn nil nil)
      (assert (= (length scene.scene-children) 0)
              "Dialog should leave the active slot after HUD transfer")
      (assert (= (length hud.tiles.children) 1)
              "Dialog should appear in HUD after transfer"))))
(table.insert tests {:name "scene transfer goes to active slot not global root" :fn scene-transfer-goes-to-active-slot-not-global-root})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "panel-transfer"
                       :tests tests})))

{:name "panel-transfer"
 :tests tests
 :main main}
