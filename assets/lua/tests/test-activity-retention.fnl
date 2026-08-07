(local glm (require :glm))
(local fs (require :fs))
(local Main (require :main))
(local Activities (require :activities))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local Scene (require :scene))
(local Canvas (require :canvas))
(local Camera (require :camera))
(local ObjectSelector (require :object-selector))
(local DrawingController (require :drawing/controller))
(local GraphActivityUnit (require :graph-activity-unit))
(local DrawingActivityUnit (require :drawing-activity-unit))
(local BoardActivityUnit (require :board-activity-unit))
(local HomeWorldCanvasRuntime (require :home-world-canvas-runtime))
(local {: FocusManager} (require :focus))

(local tests [])

(fn snapshot-app-fields [keys]
  (local snapshot {:keys keys
                   :values {}})
  (each [_ key (ipairs keys)]
    (set (. snapshot.values key) (. app key)))
  snapshot)

(fn restore-app-fields! [snapshot]
  (each [_ key (ipairs snapshot.keys)]
    (set (. app key) (. snapshot.values key)))
  true)

(fn activity-switching-retains-presentations []
  (local app-keys [:active-world-runtime
                    :canvas
                    :graph
                    :graph-map
                    :graph-map-manager
                    :graph-view
                   :drawing-controller
                   :drawing-render
                   :board
                   :board-view
                   :activity-registry
                   :activities-changed
                     :active-activity-id
                     :canvas-visible?
                     :active-interaction-surface
                     :active-pointer-controls
                     :preferred-interaction-surface
                     :scene-interactive?
                     :canvas-interactive?
                     :canvas-surface-interactive?
                     :canvas-controls
                     :first-person-controls
                     :set-canvas-visible
                    :set-active-interaction-surface
                    :viewport
                    :themes
                     :renderers
                     :lights
                     :engine
                     :create-default-projection
                     :background-state
                     :physics-containment-config
                     :physics-containment-scene
                     :__physics-global-containment
                     :__physics_containment_refresh_debouncer])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.canvas-visible? false)
  (set app.active-interaction-surface :scene)
  (set app.preferred-interaction-surface :scene)
  (set app.set-canvas-visible
       (fn [visible?]
         (set app.canvas-visible? (and app.canvas (not (= visible? false))))))
  (set app.set-active-interaction-surface
       (fn [surface _opts]
         (set app.preferred-interaction-surface surface)
         (set app.active-interaction-surface
              (if (and (= surface :canvas) app.canvas-visible?) :canvas :scene))))
  (set app.themes {:get-active-theme
                   (fn []
                     {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)
                              :label-color (glm.vec4 1 1 1 1)
                              :label-target-pixels 13.0
                              :label-min-scale 4.0
                              :edge-color (glm.vec4 0.6 0.6 0.6 1)}
                      :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}})})
  (local data-dir "/tmp/space/tests/activity-retention")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "activity-retention-test"}))
  (local canvas (Canvas {:camera camera
                         :focus-manager focus-manager}))
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local scene (Scene {:camera camera}))
  ;; Mock services needed by scene:activate-activity-slot and scene:capture-activity-slot-state
  (local SkyboxState (require :skybox-state))
  (local BackgroundState (require :background-state))
  (var skybox-state {:enabled? false :name "lake" :brightness 0.5 :tint-color [1.0 1.0 1.0]})
  (set app.renderers {:skybox {:get-state (fn [_] skybox-state)
                               :set-state (fn [_ state] (set skybox-state (SkyboxState.normalize-resolved-state state "skybox-mock")))}
                      :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
                      :set-background-state (fn [_ state] (set app.background-state (BackgroundState.normalize-complete-state state "bg-mock")))})
  (var mock-lights-state {:ambient {:enabled? false :color [0.1 0.1 0.1] :intensity 1.0} :directional [] :point [] :spot []})
  (set app.lights {:get-state (fn [_] mock-lights-state) :set-state (fn [_ state] (set mock-lights-state state))})
  (set app.engine {:physics {:addRigidBody (fn [_phys _body]) :removeRigidBody (fn [_phys _body])}})
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false}))
  (local graph-map (GraphMap.GraphMap {:graph graph :id "main"}))
  (local object-selector (ObjectSelector {:ctx-provider (fn []
                                                         (or (and canvas.active-activity-slot
                                                                  canvas.active-activity-slot.ctx)
                                                             canvas.build-context))
                                           :enabled? true}))
  (local controller (DrawingController {:data_dir data-dir}))
  (controller:add-layer "vector")
  (local runtime {:canvas canvas
                  :scene scene
                  :graph graph
                  :graph-map graph-map
                  :object-selector object-selector
                  :movables app.movables
                  :activity-cameras {:canvas {} :scene {}} :activity-controls {:canvas {} :scene {}}
                  :world-dir data-dir
                  :drawing-controller controller
                  :board-state {:items [] :connectors []}})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.graph graph)
  (set app.graph-map graph-map)
  (set app.drawing-controller controller)
  (local (ok result)
    (pcall
      (fn []
        (GraphActivityUnit.load-graph-activity!)
        (DrawingActivityUnit.load-drawing-activity!)
        (BoardActivityUnit.load-board-activity!)

        (Activities.activate-activity "graph")
        (local graph-view app.graph-view)
        (local graph-slot (canvas:activity-slot "graph"))
        (assert graph-view "Graph activity should create graph view")
        (assert graph-slot.visible? "Graph slot should be visible while graph is active")
        (assert (= app.canvas-visible? true)
                "Graph activity should request canvas visibility")
        (assert (= app.active-interaction-surface :canvas)
                "Graph activity should request canvas interaction")

        (Activities.activate-activity "drawing")
        (local drawing-render app.drawing-render)
        (local drawing-slot (canvas:activity-slot "drawing"))
        (assert drawing-render "Drawing activity should create drawing render")
        (assert drawing-slot.visible? "Drawing slot should be visible while drawing is active")
        (assert (not graph-slot.visible?) "Graph slot should hide when drawing becomes active")
        (assert (= runtime.graph-view graph-view)
                "Graph view should remain retained after switching away")
        (assert (= app.graph-view nil)
                "Inactive graph activity should not expose app.graph-view")

        (Activities.activate-activity "board")
        (local board app.board)
        (local board-view app.board-view)
        (local board-slot (canvas:activity-slot "board"))
        (assert board-view "Board activity should create board view")
        (assert board-slot.visible? "Board slot should be visible while board is active")
        (assert (not drawing-slot.visible?) "Drawing slot should hide when board becomes active")
        (assert (= runtime.drawing-render drawing-render)
                "Drawing render should remain retained after switching away")
        (assert (= app.drawing-render nil)
                "Inactive drawing activity should not expose app.drawing-render")

        (Activities.activate-activity "graph")
        (assert (= app.graph-view graph-view)
                "Switching back to graph should reuse the retained graph view")
        (assert graph-slot.visible? "Graph slot should reactivate")
        (assert (not board-slot.visible?) "Board slot should hide when graph becomes active")
        (assert (= runtime.board board)
                "Board state owner should remain retained after switching away")
        (assert (= runtime.board-view board-view)
                "Board view should remain retained after switching away")
        (assert (= app.board nil)
                "Inactive board activity should not expose app.board")
        (assert (= app.board-view nil)
                "Inactive board activity should not expose app.board-view")

        (Activities.activate-activity "drawing")
        (assert (= app.drawing-render drawing-render)
                "Switching back to drawing should reuse the retained drawing render")
        (assert drawing-slot.visible? "Drawing slot should reactivate")

        (Activities.activate-activity "board")
        (assert (= app.board board)
                "Switching back to board should reuse the retained board")
        (assert (= app.board-view board-view)
                "Switching back to board should reuse the retained board view")
        (assert board-slot.visible? "Board slot should reactivate")
        (local session-state (Activities.snapshot-activity-sessions))
        (assert session-state.graph
                "Retained graph activity session should be snapshotted")
        (assert session-state.drawing
                "Retained drawing activity session should be snapshotted")
        (assert session-state.board
                "Retained board activity session should be snapshotted")
        true)))
  (pcall GraphActivityUnit.unload-graph-activity!)
  (pcall DrawingActivityUnit.unload-drawing-activity!)
  (pcall BoardActivityUnit.unload-board-activity!)
  (object-selector:drop)
  (graph-map:drop)
  (graph:drop)
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Activity switching retains presentation sessions"
                      :fn activity-switching-retains-presentations})

(fn activity-sessions-are-runtime-scoped []
  (local app-keys [:active-world-runtime
                   :activity-registry
                   :activities-changed
                   :active-activity-id])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (local runtime-a {})
  (local runtime-b {})
  (var activation-count 0)
  (local (ok result)
    (pcall
      (fn []
        (Activities.register-activity
          {:id "test"
           :label "Test"
           :activate (fn [_ctx retained]
                       (if retained
                           retained
                           (do
                             (set activation-count (+ activation-count 1))
                             {:runtime app.active-world-runtime
                              :activation activation-count})))})
        (set app.active-world-runtime runtime-a)
        (local session-a (Activities.activate-activity "test"))
        (Activities.deactivate-active-activity)
        (set app.active-world-runtime runtime-b)
        (local session-b (Activities.activate-activity "test"))
        (assert (not (= session-a session-b))
                "Activity sessions should not be shared across world runtimes")
        (assert (= session-a.runtime runtime-a)
                "First activity session should belong to runtime A")
        (assert (= session-b.runtime runtime-b)
                "Second activity session should belong to runtime B")
        true)))
  (pcall (fn [] (Activities.unregister-activity "test")))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Activity sessions are runtime scoped"
                      :fn activity-sessions-are-runtime-scoped})

(fn retained-activity-reactivation-preserves-cleanup-stack []
  (local app-keys [:active-world-runtime
                   :activity-registry
                   :activities-changed
                   :active-activity-id])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.active-world-runtime {})
  (local cleanup-order [])
  (local session {:id :retained})
  (local (ok result)
    (pcall
      (fn []
        (Activities.register-activity
          {:id "test"
           :label "Test"
           :activate (fn [ctx retained]
                       (ctx:defer-cleanup! (fn []
                                             (table.insert cleanup-order
                                                           (if retained :second :first))))
                       (or retained session))})
        (Activities.register-activity
          {:id "other"
           :label "Other"
           :activate (fn [_ctx] {})})
        (assert (= (Activities.activate-activity "test") session)
                "Initial activation should create the retained session")
        (Activities.activate-activity "other")
        (assert (= (Activities.activate-activity "test") session)
                "Reactivation should reuse the retained session")
        (Activities.drop-activity-session! "test")
        (assert (= (length cleanup-order) 2)
                "Dropping a reactivated retained session should run both cleanup closures")
        (assert (= (. cleanup-order 1) :second)
                "Cleanup stack should remain LIFO after retained reactivation")
        (assert (= (. cleanup-order 2) :first)
                "Original cleanup closure should not be overwritten on retained reactivation")
        true)))
  (pcall (fn [] (Activities.unregister-activity "test")))
  (pcall (fn [] (Activities.unregister-activity "other")))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Retained activity reactivation preserves cleanup stack"
                     :fn retained-activity-reactivation-preserves-cleanup-stack})

(fn pending-activity-session-state-restores-on-first-activation []
  (local app-keys [:active-world-runtime
                   :activity-registry
                   :activities-changed
                   :active-activity-id])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (local runtime {:activity-session-state {:test {:value 7}}})
  (set app.active-world-runtime runtime)
  (local (ok result)
    (pcall
      (fn []
        (Activities.register-activity
          {:id "test"
           :label "Test"
           :activate (fn [_ctx retained]
                       (assert (= retained nil)
                               "Pending snapshot state should not be passed as the live retained session")
                       {:value 0})
           :restore (fn [_ctx session state]
                      (set session.value state.value))
           :snapshot (fn [_ctx session]
                       {:value session.value})})
        (local session (Activities.activate-activity "test"))
        (assert (= session.value 7)
                "First activation should restore pending persisted session state")
        (assert (= runtime.activity-session-state.test nil)
                "Restored pending session state should be consumed after activation")
        (assert (= (Activities.activate-activity "test") session)
                "Reactivating the active activity should return the user session, not the wrapper")
        (local snapshot (Activities.snapshot-activity-sessions))
        (assert (= snapshot.test.value 7)
                "Live restored activity session should snapshot restored state")
        true)))
  (pcall (fn [] (Activities.unregister-activity "test")))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(fn inactive-pending-activity-session-state-is-preserved []
  (local app-keys [:active-world-runtime
                   :activity-registry
                   :activities-changed
                   :active-activity-id])
  (local app-snapshot (snapshot-app-fields app-keys))
  (tset _G.app :activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (local runtime {:activity-session-state {:test {:value 9}}})
  (set app.active-world-runtime runtime)
  (local (ok result)
    (pcall
      (fn []
        (Activities.register-activity
          {:id "test"
           :label "Test"
           :activate (fn [_ctx] {:value 0})
           :snapshot (fn [_ctx session]
                       {:value session.value})})
        (local snapshot (Activities.snapshot-activity-sessions))
        (assert (= snapshot.test.value 9)
                "Inactive pending persisted activity session state should survive snapshots")
        true)))
  (pcall (fn [] (Activities.unregister-activity "test")))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(fn deactivation-clears-activity-surface-policy []
  (local app-keys [:active-world-runtime
                   :activity-registry
                   :activities-changed
                   :active-activity-id
                   :active-interaction-surface
                   :preferred-interaction-surface
                   :canvas
                   :canvas-visible?
                   :canvas-surface-interactive?
                   :canvas-interactive?
                   :set-active-interaction-surface
                   :sync-interaction-surface-state])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.active-world-runtime {})
  (set app.canvas {})
  (set app.canvas-visible? true)
  (set app.canvas-surface-interactive? true)
  (set app.canvas-interactive? true)
  (set app.preferred-interaction-surface :canvas)
  (set app.active-interaction-surface :canvas)
  (set app.set-active-interaction-surface
       (fn [surface _opts]
         (set app.preferred-interaction-surface surface)
         (set app.canvas-interactive?
              (and (= app.canvas-visible? true)
                   (not (= app.canvas-surface-interactive? false))
                   (= surface :canvas)))
         (set app.active-interaction-surface
              (if app.canvas-interactive? :canvas :scene))))
  (set app.sync-interaction-surface-state
       (fn [_reason _previous]
         (set app.canvas-interactive?
              (and (= app.canvas-visible? true)
                   (not (= app.canvas-surface-interactive? false))
                   (= app.preferred-interaction-surface :canvas)))
         (set app.active-interaction-surface
              (if app.canvas-interactive? :canvas :scene))))
  (local (ok result)
    (pcall
      (fn []
        (Activities.register-activity
          {:id "test"
           :label "Test"
           :activate (fn [ctx]
                       (ctx:set-surface-state! {:canvas {:visible? true
                                                         :interactive? false}})
                       (ctx:set-preferred-interaction-surface! :canvas)
                       {})})
        (Activities.activate-activity "test")
        (assert (= app.canvas-surface-interactive? false)
                "Activity policy should be able to disable canvas interaction")
        (Activities.deactivate-active-activity)
        (assert (= app.canvas-surface-interactive? true)
                "Activity deactivation should clear activity surface interactivity policy")
        (assert (= app.canvas-interactive? true)
                "Clearing activity surface policy should resync canvas interaction")
        true)))
  (pcall (fn [] (Activities.unregister-activity "test")))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Pending activity session state restores on first activation"
                     :fn pending-activity-session-state-restores-on-first-activation})
(table.insert tests {:name "Inactive pending activity session state is preserved"
                     :fn inactive-pending-activity-session-state-is-preserved})
(table.insert tests {:name "Activity deactivation clears surface policy"
                      :fn deactivation-clears-activity-surface-policy})

(fn activity-surface-policy-rejects-underscore-alias []
  (local app-keys [:active-world-runtime
                   :activity-registry
                   :activities-changed
                   :active-activity-id
                   :activity-preferred-interaction-surface
                   :preferred-interaction-surface
                   :set-active-interaction-surface])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.active-world-runtime {})
  (set app.activity-preferred-interaction-surface nil)
  (set app.preferred-interaction-surface :scene)
  (set app.set-active-interaction-surface
       (fn [surface _opts]
         (set app.preferred-interaction-surface surface)))
  (local (ok result)
    (pcall
      (fn []
        (Activities.register-activity
          {:id "test"
           :label "Test"
           :activate (fn [ctx]
                       (ctx:set-surface-state! {:preferred_interaction_surface :canvas})
                       {})})
        (Activities.activate-activity "test")
        (assert (= app.activity-preferred-interaction-surface nil)
                "Activity surface policy should ignore underscored preferred_interaction_surface")
        (assert (= app.preferred-interaction-surface :scene)
                "Underscored surface policy alias should not switch the app surface")
        true)))
  (pcall (fn [] (Activities.unregister-activity "test")))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Activity surface policy rejects underscore alias"
                     :fn activity-surface-policy-rejects-underscore-alias})

(fn canvas-unit-state-keeps-activity-shell-separate []
  (local app-keys [:active-world-runtime
                   :activity-registry
                   :activities-changed
                   :active-activity-id])
  (local app-snapshot (snapshot-app-fields app-keys))
  (tset _G.app :activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (local runtime {:requested-activity-id "test"
                  :requested-activity-known? true
                  :preferred-interaction-surface :canvas
                  :canvas {:capture-state (fn [_self]
                                           {:panels []})}})
  (local world {:state {:activity {:sessions {}}
                        :canvas {:panels []}}})
  (set app.active-world-runtime runtime)
  (local (ok result)
    (pcall
      (fn []
        (Activities.register-activity
          {:id "test"
           :label "Test"
           :activate (fn [_ctx] {:value 3})
           :snapshot (fn [_ctx session]
                       {:value session.value})})
        (Activities.activate-activity "test")
        (local unit-state (HomeWorldCanvasRuntime.capture-runtime-canvas-unit-state world runtime))
        (assert unit-state.canvas
                "Canvas unit snapshot should include a canvas payload")
        (assert unit-state.activity
                "Canvas unit snapshot should include a separate activity shell payload")
        (assert (= unit-state.canvas.active_id nil)
                "Canvas unit snapshot should not write activity id into canvas payload")
        (assert (= unit-state.activity.active_id "test")
                "Canvas unit snapshot should write active activity id into activity payload")
        (HomeWorldCanvasRuntime.restore-runtime-canvas-unit-state! runtime unit-state)
        (assert (= runtime.requested-activity-id "test")
                "Canvas unit restore should recover requested activity from activity payload")
        (assert (= runtime.pending-canvas-state.active_id nil)
                "Canvas unit restore should keep pending canvas state free of activity id")
        true)))
  (pcall (fn [] (Activities.unregister-activity "test")))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Canvas unit state keeps activity shell separate"
                      :fn canvas-unit-state-keeps-activity-shell-separate})

(fn flat-canvas-unit-state-is-not-restored-as-activity-shell []
  (local runtime {})
  (HomeWorldCanvasRuntime.restore-runtime-canvas-unit-state!
    runtime
    {:active_mode "drawing"
     :preferred_interaction_surface "canvas"
     :scale_factor 2
     :panels [{:id "left"}]})
  (assert (= runtime.requested-activity-id nil)
          "Flat canvas unit state should not migrate active_mode into requested activity")
  (assert (= runtime.preferred-interaction-surface :scene)
          "Flat canvas unit state should not migrate preferred_interaction_surface")
  (assert (= runtime.pending-canvas-state.scale_factor nil)
          "Flat canvas unit state should not be treated as canonical canvas payload")
  true)

(table.insert tests {:name "Flat canvas unit state is not restored as activity shell"
                     :fn flat-canvas-unit-state-is-not-restored-as-activity-shell})

(fn inactive-runtime-canvas-surface-drops-board-resources []
  (local app-snapshot (snapshot-app-fields [:active-world-runtime]))
  (set app.active-world-runtime {:id :other-runtime})
  (var dropped? false)
  (local runtime {:board {:id :board}
                  :board-view {:drop (fn [_self]
                                       (set dropped? true))}})
  (local (ok result)
    (pcall
      (fn []
        (HomeWorldCanvasRuntime.drop-runtime-canvas-surface! runtime)
        (assert dropped?
                "Dropping an inactive runtime canvas surface should drop retained board view")
        (assert (= runtime.board nil)
                "Dropping an inactive runtime canvas surface should clear retained board")
        (assert (= runtime.board-view nil)
                "Dropping an inactive runtime canvas surface should clear retained board view")
        true)))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Inactive runtime canvas surface drops board resources"
                     :fn inactive-runtime-canvas-surface-drops-board-resources})

(fn snapshot-activity-sessions-preserves-unregistered-pending-state []
  (local app-snapshot (snapshot-app-fields [:active-world-runtime :activity-registry]))
  (set app.activity-registry nil)
  (set app.active-world-runtime {:activity-sessions {}
                                 :activity-session-state {:user-activity {:value 7}}})
  (local (ok result)
    (pcall
      (fn []
        (local snapshot (Activities.snapshot-activity-sessions))
        (assert (= snapshot.user-activity.value 7)
                "Pending session state for an unregistered activity should survive snapshot capture")
        true)))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Snapshot activity sessions preserves unregistered pending state"
                     :fn snapshot-activity-sessions-preserves-unregistered-pending-state})

(fn inactive-runtime-canvas-surface-clears-activity-sessions-without-active-cleanup []
  (local app-snapshot (snapshot-app-fields [:active-world-runtime :activity-registry :graph-view]))
  (local active-view {:id :active-view})
  (local active-runtime {:id :active-runtime
                         :graph-view active-view})
  (set app.active-world-runtime active-runtime)
  (set app.graph-view active-view)
  (set app.activity-registry nil)
  (var cleanup-ran? false)
  (local runtime {:activity-sessions {:retained {:user-session {:id :retained}
                                                  :cleanup [(fn []
                                                              (set cleanup-ran? true)
                                                              (set app.active-world-runtime.graph-view nil)
                                                              (set app.graph-view nil))]}}})
  (local (ok result)
    (pcall
      (fn []
        (HomeWorldCanvasRuntime.drop-runtime-canvas-surface! runtime)
        (assert (not cleanup-ran?)
                "Dropping an inactive runtime canvas surface should not run active-runtime cleanup closures")
        (assert (= active-runtime.graph-view active-view)
                "Inactive runtime activity cleanup should not corrupt the active runtime")
        (assert (= app.graph-view active-view)
                "Inactive runtime activity cleanup should not clear active app graph view")
        (assert (= runtime.activity-sessions nil)
                "Dropping an inactive runtime canvas surface should clear retained activity session table")
        true)))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Inactive runtime canvas surface clears activity sessions without active cleanup"
                     :fn inactive-runtime-canvas-surface-clears-activity-sessions-without-active-cleanup})

(fn inactive-runtime-canvas-surface-does-not-double-drop-slot-root []
  (local app-snapshot (snapshot-app-fields [:active-world-runtime]))
  (set app.active-world-runtime {:id :other-runtime})
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local canvas (Canvas {:camera camera}))
  (local slot (canvas:activate-activity-slot "graph"))
  (var drop-count 0)
  (local view {:drop (fn [_self]
                       (set drop-count (+ drop-count 1))
                       (assert (= drop-count 1)
                               "Inactive runtime graph view should only be dropped once"))})
  (set slot.root view)
  (local runtime {:canvas canvas
                  :graph-view view})
  (local (ok result)
    (pcall
      (fn []
        (HomeWorldCanvasRuntime.drop-runtime-canvas-surface! runtime)
        (assert (= drop-count 1)
                "Dropping inactive runtime canvas surface should not double-drop slot root")
        (assert (= runtime.canvas nil)
                "Dropping inactive runtime canvas surface should clear runtime canvas")
        true)))
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Inactive runtime canvas surface does not double-drop slot root"
                      :fn inactive-runtime-canvas-surface-does-not-double-drop-slot-root})

(fn built-in-activity-scene-slots-are-isolated-from-sandbox []
  ;; Every built-in activity (Graph, Drawing, Board) owns an empty Scene slot
  ;; and must not inherit Sandbox content/environment/interaction.
  (local ActivitySceneState (require :activity-scene-state))
  (local SkyboxState (require :skybox-state))
  (local BackgroundState (require :background-state))
  (local Scene (require :scene))
  (local SandboxActivityUnit (require :sandbox-activity-unit))
  (local app-keys [:active-world-runtime
                   :canvas
                   :graph
                   :graph-map
                   :graph-map-manager
                   :graph-view
                   :drawing-controller
                   :drawing-render
                   :board
                   :board-view
                   :activity-registry
                   :activities-changed
                   :active-activity-id
                   :canvas-visible?
                   :active-interaction-surface
                   :active-pointer-controls
                   :preferred-interaction-surface
                   :scene-interactive?
                   :canvas-interactive?
                   :canvas-surface-interactive?
                   :canvas-controls
                   :first-person-controls
                   :set-canvas-visible
                   :set-active-interaction-surface
                   :viewport
                   :themes
                   :lights
                   :renderers
                   :background-state
                   :skybox-state
                    :physics-containment-config
                    :physics-containment-scene
                    :__physics-global-containment
                    :__physics_containment_refresh_debouncer
                    :engine
                    :pointer-target-enabled?
                    :scene
                    :create-default-projection])
  (local app-snapshot (snapshot-app-fields app-keys))
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.canvas-visible? false)
  (set app.canvas-interactive? false)
  (set app.canvas-surface-interactive? true)
  (set app.scene-interactive? true)
  (set app.active-interaction-surface :scene)
  (set app.preferred-interaction-surface :scene)
  (Main.install-app-shell!)
  (set app.set-canvas-visible
       (fn [visible?]
         (set app.canvas-visible? (and app.canvas (not (= visible? false))))))
  (set app.set-active-interaction-surface
       (fn [surface _opts]
         (set app.preferred-interaction-surface surface)
         (set app.active-interaction-surface
              (if (and (= surface :canvas) app.canvas-visible?) :canvas :scene))))

  ;; Mock services
  (var skybox-state {:enabled? false :name "lake" :brightness 0.5 :tint-color [1.0 1.0 1.0]})
  (set app.renderers {:skybox {:get-state (fn [_] skybox-state)
                               :set-state (fn [_ state] (set skybox-state (SkyboxState.normalize-resolved-state state "skybox-mock")))}
                      :get-background-state (fn [_] (or app.background-state BackgroundState.default-state))
                      :set-background-state (fn [_ state] (set app.background-state (BackgroundState.normalize-complete-state state "bg-mock")))})
  (var mock-lights-state {:ambient {:enabled? false :color [0.1 0.1 0.1] :intensity 1.0} :directional [] :point [] :spot []})
  (set app.lights {:get-state (fn [_] mock-lights-state) :set-state (fn [_ state] (set mock-lights-state state))})
  (set app.engine {:physics {:addRigidBody (fn [_phys _body]) :removeRigidBody (fn [_phys _body])}})
  (set app.themes {:get-active-theme
                   (fn []
                     {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)
                              :label-color (glm.vec4 1 1 1 1)
                              :label-target-pixels 13.0
                              :label-min-scale 4.0
                              :edge-color (glm.vec4 0.6 0.6 0.6 1)}
                      :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}})})

  (local data-dir "/tmp/space/tests/builtin-activity-scene-isolation")
  (when (fs.exists data-dir) (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "builtin-activity-scene-isolation"}))
  (local scene (Scene {:camera camera}))
  (local canvas (Canvas {:camera camera :focus-manager focus-manager}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (canvas:on-viewport-changed app.viewport)
  (scene:on-viewport-changed app.viewport)
  (local graph (Graph {:with-start false}))
  (local graph-map (GraphMap.GraphMap {:graph graph :id "main"}))
  (local object-selector (ObjectSelector {:ctx-provider (fn [] (or (and canvas.active-activity-slot canvas.active-activity-slot.ctx) canvas.build-context)) :enabled? true}))
  (local controller (DrawingController {:data_dir data-dir}))
  (controller:add-layer "vector")
  (local runtime {:canvas canvas
                  :scene scene
                  :graph graph
                  :graph-map graph-map
                  :object-selector object-selector
                  :movables app.movables
                  :activity-cameras {:canvas {} :scene {}} :activity-controls {:canvas {} :scene {}}
                  :world-dir data-dir
                  :drawing-controller controller
                  :board-state {:items [] :connectors []}})
  (set app.active-world-runtime runtime)
  (set app.canvas canvas)
  (set app.scene scene)
  (set app.graph graph)
  (set app.graph-map graph-map)
  (set app.drawing-controller controller)
  (local (ok result)
    (pcall
      (fn []
        (SandboxActivityUnit.load-sandbox-activity!)
        (GraphActivityUnit.load-graph-activity!)
        (DrawingActivityUnit.load-drawing-activity!)
        (BoardActivityUnit.load-board-activity!)

        ;; Give sandbox non-default scene state
        (local sandbox-state
          {:panels []
           :terrains [{:kind "heightfield-terrain"}]
           :lights {:ambient {:enabled? true :color [1.0 1.0 1.0] :intensity 1.0} :directional [] :point [] :spot []}
           :skybox {:enabled? true :name "lake" :brightness 0.5 :tint-color [1.0 1.0 1.0]}
           :background {:color [0.2 0.3 0.4]}
           :containment {:enabled? true}})
        (scene:restore-activity-slot-state "sandbox" sandbox-state)

        ;; Activate Sandbox — verify services reflect sandbox state
        (Activities.activate-activity "sandbox")
        (assert (= scene.active-activity-slot-id "sandbox") "Scene should report sandbox as active")
        (assert (. mock-lights-state :ambient :enabled?) "Sandbox activation should enable ambient")
        ;; Background and containment should reflect sandbox state
        (assert (and app.background-state
                     (= (. app.background-state.color 1) 0.2)
                     (= (. app.background-state.color 2) 0.3)
                     (= (. app.background-state.color 3) 0.4))
                "Sandbox activation should apply custom background color")
        (let [sb-slot (scene:activity-slot "sandbox")
              sb-manager (and sb-slot sb-slot.physics-containment-manager)]
          (assert (and sb-manager sb-manager.config sb-manager.config.enabled?)
                  "Sandbox containment should be enabled"))
        (let [sb-slot (scene:activity-slot "sandbox")]
          (assert (app.pointer-target-enabled? (. sb-slot :pointer-target))
                  "Sandbox pointer target should be enabled while sandbox is active"))

        ;; Verify all three activities get their own empty Scene slots
        (each [_ activity-id (ipairs ["graph" "drawing" "board"])]
          (Activities.activate-activity activity-id)
          (assert (= scene.active-activity-slot-id activity-id)
                  (.. activity-id " should be the active scene slot"))
          (local slot (scene:activity-slot activity-id))
          (assert slot (.. activity-id " should own a scene slot"))
          (local sandbox-slot (scene:activity-slot "sandbox"))
          (assert (not (= slot sandbox-slot))
                  (.. activity-id " scene slot must not be Sandbox scene slot"))
          ;; Services should be empty/disabled for non-Sandbox activities
          (assert (not (. mock-lights-state :ambient :enabled?))
                  (.. activity-id " activation should disable ambient light"))
          (assert (not skybox-state.enabled?)
                  (.. activity-id " activation should disable skybox"))
          (local captured (scene:capture-activity-slot-state activity-id))
          (assert (= (length captured.terrains) 0)
                  (.. activity-id " scene slot should have no terrains"))
          (assert (= (length captured.panels) 0)
                  (.. activity-id " scene slot should have no panels"))
          (assert (not captured.lights.ambient.enabled?)
                  (.. "Captured " activity-id " state should have disabled ambient light"))
          (assert (not captured.skybox.enabled?)
                  (.. "Captured " activity-id " state should have disabled skybox"))
          ;; Graph intentionally applies its graph-background fallback; other
          ;; built-ins should reset the sandbox background to the neutral default.
          (local expected-background (if (= activity-id "graph") [0.094999998807907 0.10499999672174 0.12999999523163] [0.0 0.0 0.0]))
          (local actual-background (or (and app.background-state app.background-state.color) [999 999 999]))
          (local background-delta-1 (_G.math.abs (- (. actual-background 1) (. expected-background 1))))
          (local background-delta-2 (_G.math.abs (- (. actual-background 2) (. expected-background 2))))
          (local background-delta-3 (_G.math.abs (- (. actual-background 3) (. expected-background 3))))
          (assert (and app.background-state
                       (< background-delta-1 0.00001)
                       (< background-delta-2 0.00001)
                       (< background-delta-3 0.00001))
                  (.. activity-id " activation should apply isolated background"))
          ;; Containment should be disabled
          (let [act-slot (scene:activity-slot activity-id)
                act-manager (and act-slot act-slot.physics-containment-manager)]
            (assert (and act-manager act-manager.config
                         (not act-manager.config.enabled?))
                    (.. activity-id " activation should disable containment")))
          ;; Sandbox pointer target should be rejected
          (let [sb-slot (scene:activity-slot "sandbox")]
            (assert (not (app.pointer-target-enabled? (. sb-slot :pointer-target)))
                    (.. "Sandbox pointer target should be rejected while " activity-id " is active"))))

        ;; Switch back to Sandbox — identity preserved
        (Activities.activate-activity "sandbox")
        (assert (= scene.active-activity-slot-id "sandbox") "Switching back should restore sandbox as active")
        (assert (. mock-lights-state :ambient :enabled?) "Sandbox reactivation should re-enable ambient")
        (assert skybox-state.enabled? "Sandbox reactivation should re-enable skybox")
        ;; Background and containment should be restored
        (assert (and app.background-state
                     (= (. app.background-state.color 1) 0.2)
                     (= (. app.background-state.color 2) 0.3)
                     (= (. app.background-state.color 3) 0.4))
                "Sandbox reactivation should restore custom background color")
        (let [sb-slot2 (scene:activity-slot "sandbox")
              sb-manager2 (and sb-slot2 sb-slot2.physics-containment-manager)]
          (assert (and sb-manager2 sb-manager2.config sb-manager2.config.enabled?)
                  "Sandbox reactivation should restore containment"))
        true)))
  (pcall SandboxActivityUnit.unload-sandbox-activity!)
  (pcall GraphActivityUnit.unload-graph-activity!)
  (pcall DrawingActivityUnit.unload-drawing-activity!)
  (pcall BoardActivityUnit.unload-board-activity!)
  (object-selector:drop)
  (graph-map:drop)
  (graph:drop)
  (scene:drop)
  (canvas:drop)
  (focus-manager:drop)
  (camera:drop)
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Built-in activity scene slots are isolated from Sandbox"
                      :fn built-in-activity-scene-slots-are-isolated-from-sandbox})

(fn activity-snapshot-fails-loudly-without-runtime-scene []
  ;; R1-2: snapshot must assert runtime.scene, not silently return nil.
  (local app-keys [:active-world-runtime :activity-registry :activities-changed :active-activity-id
                   :graph-view :graph-view-states])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  ;; Runtime without scene
  (set app.active-world-runtime {:canvas {} :world-dir "/tmp/space/tests/snapshot-no-scene"})
  (GraphActivityUnit.load-graph-activity!)
  (local (ok err) (pcall GraphActivityUnit.snapshot-graph-activity!))
  (assert (not ok)
          "Graph snapshot should fail loudly when runtime.scene is missing")
  (assert (or (string.find (tostring err) "requires runtime.scene")
              (string.find (tostring err) "requires app.active-world-runtime"))
          (.. "Snapshot error should mention missing runtime/scene, got: " (tostring err)))
  (pcall GraphActivityUnit.unload-graph-activity!)
  (restore-app-fields! app-snapshot)
  true)

(table.insert tests {:name "Activity snapshot fails loudly without runtime.scene"
                      :fn activity-snapshot-fails-loudly-without-runtime-scene})

(fn activity-restore-fails-loudly-without-runtime-scene []
  ;; R1-2: restore must assert runtime.scene when state.scene is present,
  ;; not silently skip.
  (local app-keys [:active-world-runtime :activity-registry :activities-changed :active-activity-id
                   :graph-view :graph-view-states])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  ;; Runtime without scene but with pending state containing scene
  (set app.active-world-runtime {:canvas {} :world-dir "/tmp/space/tests/restore-no-scene"})
  (GraphActivityUnit.load-graph-activity!)
  ;; restore-state-arg: when first arg lacks :activity key, it is treated as state
  (local pending-state {:scene {:panels [] :terrains [] :lights {} :skybox {} :background {} :containment {:enabled? false}}})
  (local (ok err) (pcall GraphActivityUnit.restore-graph-activity! pending-state))
  (assert (not ok)
          "Graph restore should fail loudly when runtime.scene is missing but state.scene is present")
  (assert (or (string.find (tostring err) "requires runtime.scene")
              (string.find (tostring err) "requires app.active-world-runtime"))
          (.. "Restore error should mention missing runtime/scene, got: " (tostring err)))
  (pcall GraphActivityUnit.unload-graph-activity!)
  (restore-app-fields! app-snapshot)
  true)

(table.insert tests {:name "Activity restore fails loudly without runtime.scene"
                      :fn activity-restore-fails-loudly-without-runtime-scene})

(fn graph-restore-tolerates-nil-state []
  ;; restore-state-arg returns nil when the first argument lacks :activity,
  ;; so restore must tolerate a nil state without crashing on state.scene.
  (local app-keys [:active-world-runtime :activity-registry :activities-changed :active-activity-id
                   :graph-view :graph-view-states :canvas])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.canvas {})
  (set app.active-world-runtime {:canvas app.canvas
                                  :world-dir "/tmp/space/tests/graph-restore-nil-state"})
  (GraphActivityUnit.load-graph-activity!)
  ;; Call restore with nil — this simulates restore-state-arg returning nil.
  ;; Must not crash, must return true (matching Drawing / Board tolerance).
  (local (ok result) (pcall GraphActivityUnit.restore-graph-activity! nil))
  (assert ok (.. "Graph restore with nil state should not crash, got: " (tostring result)))
  (assert result "Graph restore with nil state should return true")
  (pcall GraphActivityUnit.unload-graph-activity!)
  (restore-app-fields! app-snapshot)
  true)

(table.insert tests {:name "Graph restore tolerates nil state"
                      :fn graph-restore-tolerates-nil-state})

(fn drawing-snapshot-fails-loudly-without-runtime-scene []
  ;; R1-2: Drawing snapshot must assert runtime.scene.
  (local app-keys [:active-world-runtime :activity-registry :activities-changed :active-activity-id
                   :drawing-render])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.active-world-runtime {:canvas {} :world-dir "/tmp/space/tests/drawing-snapshot-no-scene"})
  (DrawingActivityUnit.load-drawing-activity!)
  (local (ok err) (pcall DrawingActivityUnit.snapshot-drawing-activity!))
  (assert (not ok)
          "Drawing snapshot should fail loudly when runtime.scene is missing")
  (assert (or (string.find (tostring err) "requires runtime.scene")
              (string.find (tostring err) "requires app.active-world-runtime"))
          (.. "Snapshot error should mention missing runtime/scene, got: " (tostring err)))
  (pcall DrawingActivityUnit.unload-drawing-activity!)
  (restore-app-fields! app-snapshot)
  true)

(table.insert tests {:name "Drawing activity snapshot fails loudly without runtime.scene"
                      :fn drawing-snapshot-fails-loudly-without-runtime-scene})

(fn drawing-restore-fails-loudly-without-runtime-scene []
  ;; R1-2: Drawing restore must assert runtime.scene when state.scene is present.
  (local app-keys [:active-world-runtime :activity-registry :activities-changed :active-activity-id
                   :drawing-render])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.active-world-runtime {:canvas {} :world-dir "/tmp/space/tests/drawing-restore-no-scene"})
  (DrawingActivityUnit.load-drawing-activity!)
  (local pending-state {:scene {:panels [] :terrains [] :lights {} :skybox {} :background {} :containment {:enabled? false}}})
  (local (ok err) (pcall DrawingActivityUnit.restore-drawing-activity! pending-state))
  (assert (not ok)
          "Drawing restore should fail loudly when runtime.scene is missing but state.scene is present")
  (assert (or (string.find (tostring err) "requires runtime.scene")
              (string.find (tostring err) "requires app.active-world-runtime"))
          (.. "Restore error should mention missing runtime/scene, got: " (tostring err)))
  (pcall DrawingActivityUnit.unload-drawing-activity!)
  (restore-app-fields! app-snapshot)
  true)

(table.insert tests {:name "Drawing activity restore fails loudly without runtime.scene"
                      :fn drawing-restore-fails-loudly-without-runtime-scene})

(fn board-snapshot-fails-loudly-without-runtime-scene []
  ;; R1-2: Board snapshot must assert runtime.scene.
  (local app-keys [:active-world-runtime :activity-registry :activities-changed :active-activity-id
                   :board :board-view])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.active-world-runtime {:canvas {} :world-dir "/tmp/space/tests/board-snapshot-no-scene"})
  (BoardActivityUnit.load-board-activity!)
  (local (ok err) (pcall BoardActivityUnit.snapshot-board-activity!))
  (assert (not ok)
          "Board snapshot should fail loudly when runtime.scene is missing")
  (assert (or (string.find (tostring err) "requires runtime.scene")
              (string.find (tostring err) "requires app.active-world-runtime"))
          (.. "Snapshot error should mention missing runtime/scene, got: " (tostring err)))
  (pcall BoardActivityUnit.unload-board-activity!)
  (restore-app-fields! app-snapshot)
  true)

(table.insert tests {:name "Board activity snapshot fails loudly without runtime.scene"
                      :fn board-snapshot-fails-loudly-without-runtime-scene})

(fn board-restore-fails-loudly-without-runtime-scene []
  ;; R1-2: Board restore must assert runtime.scene when state.scene is present.
  (local app-keys [:active-world-runtime :activity-registry :activities-changed :active-activity-id
                   :board :board-view])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.active-world-runtime {:canvas {} :world-dir "/tmp/space/tests/board-restore-no-scene"})
  (BoardActivityUnit.load-board-activity!)
  (local pending-state {:scene {:panels [] :terrains [] :lights {} :skybox {} :background {} :containment {:enabled? false}}})
  (local (ok err) (pcall BoardActivityUnit.restore-board-activity! pending-state))
  (assert (not ok)
          "Board restore should fail loudly when runtime.scene is missing but state.scene is present")
  (assert (or (string.find (tostring err) "requires runtime.scene")
              (string.find (tostring err) "requires app.active-world-runtime"))
          (.. "Restore error should mention missing runtime/scene, got: " (tostring err)))
  (pcall BoardActivityUnit.unload-board-activity!)
  (restore-app-fields! app-snapshot)
  true)

(table.insert tests {:name "Board activity restore fails loudly without runtime.scene"
                      :fn board-restore-fails-loudly-without-runtime-scene})

(fn activity-hooks-include-toolbar-and-sandbox-interaction-providers []
  (local app-keys [:active-world-runtime
                   :activity-registry
                   :activities-changed
                   :active-activity-id])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.active-world-runtime {})
  (set app.activity-top-toolbar-builder nil)
  (set app.activity-object-drag-mode-provider nil)
  (local toolbar-builder (fn [] :toolbar-builder))
  (local object-drag-provider (fn [] :grab))
  (local (ok result)
    (pcall
      (fn []
        (Activities.register-activity
          {:id "toolbar-test"
           :label "Toolbar Test"
            :activate (fn [ctx]
                        (ctx:set-top-toolbar-builder! toolbar-builder)
                        (ctx:set-object-drag-mode-provider! object-drag-provider)
                        {})})
        (Activities.activate-activity "toolbar-test")
        (assert (= app.activity-top-toolbar-builder toolbar-builder)
                "app.activity-top-toolbar-builder should be set after activation")
        (assert (= app.activity-object-drag-mode-provider object-drag-provider)
                "app.activity-object-drag-mode-provider should be set after activation")
        (Activities.deactivate-active-activity)
        (assert (= app.activity-top-toolbar-builder nil)
                "app.activity-top-toolbar-builder should be nil after deactivation")
        (assert (= app.activity-object-drag-mode-provider nil)
                "app.activity-object-drag-mode-provider should be nil after deactivation")
        true)))
  (pcall (fn [] (Activities.unregister-activity "toolbar-test")))
  (restore-app-fields! app-snapshot)
  (if ok result (error result)))

(table.insert tests {:name "Activity hooks include toolbar and sandbox interaction providers"
                     :fn activity-hooks-include-toolbar-and-sandbox-interaction-providers})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "activity-retention"
                       :tests tests})))

{:name "activity-retention"
 :tests tests
 :main main}
