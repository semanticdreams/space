(local Main (require :main))
(local CanvasModes (require :canvas-modes))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local AppViewport (require :app-viewport))
(local AppProjection (require :app-projection))
(local reset-engine-events
  (fn []
    (when _G.reset-engine-events
      (_G.reset-engine-events))))

(local tests [])

(local ensure-renderers
  (fn []
    (set app.renderers {:update (fn [_] nil)
                          :on-viewport-changed (fn [_ _] nil)
                          :drop (fn [_] nil)})
    app.renderers))

(fn ensure-built-in-canvas-modes! []
  (local registry (CanvasModes.ensure-registry))
  (when (not (. registry.modes "graph"))
    (CanvasModes.register-mode {:id "graph"
                                :label "Graph"
                                :icon "account_tree"
                                :button-name "graph-canvas-mode"
                                :show-in-sidebar? true
                                :activate (fn [_ctx] nil)}))
  (when (not (. registry.modes "drawing"))
    (CanvasModes.register-mode {:id "drawing"
                                :label "Draw"
                                :icon "draw"
                                :button-name "drawing-canvas-mode"
                                :show-in-sidebar? true
                                :activate (fn [_ctx] nil)}))
  true)

(local bind-state-keys
  [:active-canvas-mode
   :active-interaction-surface
   :active-pointer-controls
   :active-world-entry
   :active-world-hud-contrib
   :active-world-hud-overlay
   :active-world-runtime
   :bind-active-world-runtime
   :board
   :board-registry
   :board-view
   :camera
   :canvas
   :canvas-controls
   :canvas-focus-scope
   :canvas-interactive?
   :canvas-mode-activate-focused
   :canvas-mode-command-hints-provider
   :canvas-mode-context-enricher
   :canvas-mode-delete-selection
   :canvas-mode-drawing-enabled?
   :canvas-mode-input-handlers
   :canvas-mode-left-dock-builder
   :canvas-mode-target-enabled?
   :canvas-mode-update
   :canvas-mode-units
   :canvas-mode-registry
   :canvas-mode-root-actions
   :canvas-mode-selection-actions
   :canvas-modes-changed
   :canvas-shell-changed
   :canvas-visible?
   :drawing-controller
   :drawing-render
   :first-person-controls
   :graph
   :graph-view
   :hud
   :install-app-shell!
   :layout-root
   :mark-active-world-hud-dirty
   :object-selector
   :pointer-target-enabled?
   :preferred-interaction-surface
   :projection
   :reset-projection
   :scene
   :scene-focus-scope
   :scene-interactive?
   :set-active-canvas-mode
   :set-active-interaction-surface
   :set-canvas-visible
   :terrain-paint-previous-state
   :terrain-paint-session
   :terrain-rect-pick-previous-state
   :terrain-rect-pick-session
   :toggle-active-interaction-surface
   :world-manager])

(fn capture-app-fields [keys]
  (local snapshot {})
  (each [_ key (ipairs keys)]
    (set (. snapshot key) (. app key)))
  snapshot)

(fn restore-app-fields [keys snapshot]
  (each [_ key (ipairs keys)]
    (set (. app key) (. snapshot key)))
  true)

(fn with-restored-app-fields [keys f]
  (local snapshot (capture-app-fields keys))
  (local (ok result) (pcall f))
  (restore-app-fields keys snapshot)
  (if ok
      result
      (error result)))

(local reset-state
  (fn []
    (reset-engine-events)
    (when (and app.window-resized-handler app.engine.events app.engine.events.window-resized)
      (app.engine.events.window-resized:disconnect app.window-resized-handler true)
      (set app.window-resized-handler nil))
    (when (and app.window-pixel-size-handler app.engine.events app.engine.events.window-pixel-size-changed)
      (app.engine.events.window-pixel-size-changed:disconnect app.window-pixel-size-handler true)
      (set app.window-pixel-size-handler nil))
    (when (and app.engine.events app.engine.events.window-resized)
      (set app.window-resized-handler
           (app.engine.events.window-resized:connect
             (fn [e]
               (local width (or (and app.engine (. app.engine "pixel-width")) e.width))
               (local height (or (and app.engine (. app.engine "pixel-height")) e.height))
               (app.set-viewport {:width width :height height})
               (app.reset-projection)))))
    (when (and app.engine.events app.engine.events.window-pixel-size-changed)
      (set app.window-pixel-size-handler
           (app.engine.events.window-pixel-size-changed:connect
             (fn [_e]
               (local width (or (and app.engine (. app.engine "pixel-width")) 0))
               (local height (or (and app.engine (. app.engine "pixel-height")) 0))
               (app.set-viewport {:width width :height height})
               (app.reset-projection)))))
    (when (not app.set-viewport)
      (set app.set-viewport AppViewport.set-viewport))
    (when (not app.create-default-projection)
      (set app.create-default-projection AppProjection.create-default-projection))
    (when (not app.reset-projection)
      (set app.reset-projection (fn [] (set app.projection (app.create-default-projection)))))
    (app.set-viewport {:width 0 :height 0})
    (set app.layout-root nil)))

(fn window-resize-updates-viewport-and-layout-root []
  (reset-state)
  (ensure-renderers)
  (set (. app.engine "pixel-width") 960)
  (set (. app.engine "pixel-height") 540)
  (app.engine.events.window-resized.emit {:width 640 :height 360})
  (assert (= app.viewport.width 960))
  (assert (= app.viewport.height 540)))

(fn drop-keeps-engine-events-and-clears-layout-root []
  (reset-state)
  (ensure-renderers)
  (local original-intersectables app.intersectables)
  (local original-clickables app.clickables)
  (local original-hoverables app.hoverables)
  (var fired false)
  (app.engine.events.key-down.connect (fn [_] (set fired true)))
  (set app.layout-root {:mark-measure-dirty (fn [_])})
  (Main.drop)
  (when (not app.intersectables)
    (set app.intersectables (or original-intersectables (Intersectables))))
  (when (not app.clickables)
    (set app.clickables (or original-clickables (Clickables {:intersectables app.intersectables}))))
  (when (not app.hoverables)
    (set app.hoverables (or original-hoverables (Hoverables {:intersectables app.intersectables}))))
  (assert (= app.layout-root nil))
  (app.engine.events.key-down.emit {:key 10})
  (assert fired))

(fn other-events-leave-viewport-untouched []
  (reset-state)
  (ensure-renderers)
  (app.set-viewport {:width 111 :height 222})
  (app.engine.events.key-down.emit {:key 97})
  (assert (= app.viewport.width 111))
  (assert (= app.viewport.height 222)))

(fn window-pixel-size-change-updates-viewport []
  (reset-state)
  (ensure-renderers)
  (set (. app.engine "pixel-width") 2560)
  (set (. app.engine "pixel-height") 1440)
  (app.engine.events.window-pixel-size-changed.emit {:width 2560 :height 1440})
  (assert (= app.viewport.width 2560))
  (assert (= app.viewport.height 1440)))

(fn bind-active-world-runtime-restores-runtime-interaction-surface []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (ensure-built-in-canvas-modes!)
      (var restored false)
      (var active-canvas-mode nil)
      (var preferred-surface nil)
      (var active-surface nil)
      (var canvas-visible? nil)
      (var canvas-interactive? nil)
        (set app.preferred-interaction-surface :scene)
        (set app.active-interaction-surface :scene)
        (set app.canvas-visible? false)
        (set app.scene-interactive? true)
        (set app.canvas-interactive? false)
        (set app.world-manager {:active-world (fn [_self]
                                                {:world {:get-hud-contrib (fn [_world] {})}})})
        (set app.hud {:build-context {}
                      :build-default (fn [_self _opts] true)
                      :add-overlay-child (fn [_self _opts] :overlay)
                      :remove-overlay-child (fn [_self _overlay] true)
                      :on-viewport-changed (fn [_self _viewport] true)})
        (local canvas-controls {:id :canvas-controls})
        (local first-person-controls {:id :scene-controls})
        (set app.reset-projection (fn [] true))
        (Main.bind-active-world-runtime
          {:id "world-a"}
          {:active-canvas-mode "drawing"
           :preferred-interaction-surface :canvas
           :restore-surface-state (fn [_self _canvas _hud]
                                    (set restored true))
           :first-person-controls first-person-controls
           :canvas-controls canvas-controls
           :scene nil
           :canvas {:build-context {}
                    :restore-state (fn [_self _state] true)}})
        (set active-canvas-mode app.active-canvas-mode)
        (set preferred-surface app.preferred-interaction-surface)
        (set active-surface app.active-interaction-surface)
        (set canvas-visible? app.canvas-visible?)
        (set canvas-interactive? app.canvas-interactive?)
      (assert restored "bind-active-world-runtime should restore target surface state before shell sync")
      (assert (= active-canvas-mode "drawing")
              "bind-active-world-runtime should restore active canvas mode from runtime")
      (assert (= preferred-surface :canvas)
              "bind-active-world-runtime should adopt runtime interaction surface preference")
      (assert (= active-surface :canvas)
              "bind-active-world-runtime should restore canvas as the active interaction surface")
      (assert (= canvas-visible? true)
              "bind-active-world-runtime should restore canvas visibility when canvas mode was persisted")
      (assert (= canvas-interactive? true)
              "bind-active-world-runtime should re-enable canvas interaction when canvas mode was persisted")
      true)))

(fn bind-active-world-runtime-preserves-explicit-nil-canvas-mode []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (ensure-built-in-canvas-modes!)
      (CanvasModes.activate-mode "drawing")
      (local runtime
        {:requested-canvas-mode-id nil
         :requested-canvas-mode-known? true
         :active-canvas-mode "drawing"
         :preferred-interaction-surface :canvas
         :restore-surface-state (fn [_self _canvas _hud] true)})
      (app.bind-active-world-runtime {:id "test-world"} runtime)
      (assert (= app.active-canvas-mode nil)
              "bind-active-world-runtime should preserve an explicit nil requested canvas mode")
      (assert (= runtime.active-canvas-mode nil)
              "bind-active-world-runtime should clear stale runtime active mode when requested mode is nil")
      true)))

(fn bind-active-world-runtime-defers-canvas-mode-without-canvas []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.canvas-mode-registry nil)
      (CanvasModes.clear-mode-runtime-hooks!)
      (var activated? false)
      (CanvasModes.register-mode
        {:id "graph"
         :label "Graph"
         :icon "account_tree"
         :button-name "graph-canvas-mode"
         :show-in-sidebar? true
         :activate (fn [_ctx]
                     (set activated? true)
                     (assert (and app.active-world-runtime app.active-world-runtime.canvas)
                             "test graph mode requires runtime.canvas"))})
      (local runtime {:requested-canvas-mode-id "graph"
                      :requested-canvas-mode-known? true
                      :active-canvas-mode "graph"
                      :preferred-interaction-surface :canvas
                      :restore-surface-state (fn [_self _canvas _hud] true)})
      (app.bind-active-world-runtime {:id "test-world"} runtime)
      (assert (not activated?)
              "bind-active-world-runtime should not activate canvas modes without runtime.canvas")
      (assert (= app.active-canvas-mode nil)
              "bind-active-world-runtime should clear active mode while canvas is absent")
      (assert (= runtime.active-canvas-mode nil)
              "bind-active-world-runtime should clear stale runtime active mode while canvas is absent")
      (assert (= runtime.requested-canvas-mode-id "graph")
               "bind-active-world-runtime should preserve requested mode for later canvas reload")
      true)))

(fn bind-active-world-runtime-preserves-active-canvas-mode-as-requested []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.canvas-mode-registry nil)
      (CanvasModes.clear-mode-runtime-hooks!)
      (var activated? false)
      (CanvasModes.register-mode
        {:id "graph"
         :label "Graph"
         :icon "account_tree"
         :button-name "graph-canvas-mode"
         :show-in-sidebar? true
         :activate (fn [_ctx]
                     (set activated? true)
                     (assert (and app.active-world-runtime app.active-world-runtime.canvas)
                             "test graph mode requires runtime.canvas"))})
      (local runtime {:active-canvas-mode "graph"
                      :preferred-interaction-surface :canvas
                      :restore-surface-state (fn [_self _canvas _hud] true)})
      (app.bind-active-world-runtime {:id "test-world"} runtime)
      (assert (not activated?)
              "bind-active-world-runtime should not activate canvas modes without runtime.canvas")
      (assert (= app.active-canvas-mode nil)
              "bind-active-world-runtime should clear active mode while canvas is absent")
      (assert (= runtime.active-canvas-mode nil)
              "bind-active-world-runtime should clear stale runtime active mode while canvas is absent")
      (assert (= runtime.requested-canvas-mode-id "graph")
              "bind-active-world-runtime should promote active-canvas-mode to requested-mode-id")
      (assert (= runtime.requested-canvas-mode-known? true)
              "bind-active-world-runtime should mark requested mode as known when preserving it")
      true)))

(fn set-active-canvas-mode-rejects-unknown-mode []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (local (ok err)
        (pcall
          (fn []
            (app.set-active-canvas-mode "bogus"))))
      (assert (not ok)
              "set-active-canvas-mode should reject unknown canvas modes")
      (assert (and err (string.find err "Unknown canvas mode"))
              "set-active-canvas-mode should report the invalid mode id clearly")
      true)))

(fn canvas-modes-ordered-specs-preserve-registration-order []
  (local original-registry app.canvas-mode-registry)
  (set app.canvas-mode-registry nil)
  (CanvasModes.register-mode {:id "graph"
                              :label "Graph"
                              :icon "account_tree"
                              :button-name "graph-canvas-mode"
                              :show-in-sidebar? true
                              :activate (fn [_ctx] nil)})
  (CanvasModes.register-mode {:id "drawing"
                              :label "Draw"
                              :icon "draw"
                              :button-name "drawing-canvas-mode"
                              :show-in-sidebar? true
                              :activate (fn [_ctx] nil)})
  (local specs (CanvasModes.mode-specs-in-order))
  (assert (= (length specs) 2)
          "Canvas mode registry should preserve both registered mode specs")
  (assert (= (. (. specs 1) :id) "graph")
          "Canvas mode registry should preserve registration order for the first mode")
  (assert (= (. (. specs 2) :id) "drawing")
          "Canvas mode registry should preserve registration order for the second mode")
  (set app.canvas-mode-registry original-registry)
  true)

(fn invalid-persisted-canvas-mode-clears-to-nil []
  (local (normalized repaired? reason)
    (CanvasModes.normalize-persisted 42))
  (assert (= normalized nil)
          "CanvasModes.normalize-persisted should clear invalid persisted mode values to nil")
  (assert repaired?
          "CanvasModes.normalize-persisted should report repaired invalid persisted mode values")
  (assert (and reason (string.find reason "clearing to nil"))
          "CanvasModes.normalize-persisted should report that invalid persisted mode values were cleared")
  true)

(fn canvas-mode-activation-failure-restores-previous-mode []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (set app.canvas-mode-registry nil)
      (CanvasModes.clear-mode-runtime-hooks!)
      (CanvasModes.register-mode
        {:id "graph"
         :label "Graph"
         :icon "account_tree"
         :button-name "graph-canvas-mode"
         :show-in-sidebar? true
         :activate (fn [ctx]
                     (ctx:set-root-actions! (fn [_context] []))
                     {:mode-id "graph"})})
      (CanvasModes.register-mode
        {:id "broken"
         :label "Broken"
         :icon "draw"
         :button-name "broken-canvas-mode"
         :show-in-sidebar? true
         :activate (fn [ctx]
                     (set app.__broken-mode-side-effect "armed")
                     (ctx:defer-cleanup! (fn []
                                           (set app.__broken-mode-side-effect nil)))
                     (ctx:set-root-actions! (fn [_context]
                                              [{:name "broken"}]))
                     (error "boom"))})
      (CanvasModes.activate-mode "graph")
      (local previous-root-actions app.canvas-mode-root-actions)
      (local (ok err)
        (pcall
          (fn []
            (CanvasModes.activate-mode "broken"))))
      (assert (not ok)
              "CanvasModes.activate-mode should fail loudly when the new mode activation throws")
      (assert (and err (string.find err "Canvas mode activation failed for broken"))
              "CanvasModes.activate-mode should report the failing mode id")
      (assert (= (CanvasModes.active-mode-id) "graph")
              "CanvasModes.activate-mode should restore the previous active mode on failure")
      (assert (= app.active-canvas-mode "graph")
              "Canvas mode activation rollback should restore app.active-canvas-mode")
      (assert (= (type app.canvas-mode-root-actions) :function)
              "Canvas mode activation rollback should restore a root action hook")
      (assert (not (= app.canvas-mode-root-actions previous-root-actions nil))
              "Canvas mode activation rollback should not leave the root action hook cleared")
      (assert (= (length (app.canvas-mode-root-actions {})) 0)
              "Canvas mode activation rollback should restore the previous root action behavior")
      (assert (= app.__broken-mode-side-effect nil)
              "Canvas mode activation rollback should run deferred cleanup for failed activation side effects")
      true)))

(table.insert tests {:name "Window resize updates viewport and layout root" :fn window-resize-updates-viewport-and-layout-root})
(table.insert tests {:name "Window pixel size change updates viewport" :fn window-pixel-size-change-updates-viewport})
(table.insert tests {:name "app.drop keeps engine events and clears layout root" :fn drop-keeps-engine-events-and-clears-layout-root})
(table.insert tests {:name "Non-resize events leave viewport unchanged" :fn other-events-leave-viewport-untouched})
(table.insert tests {:name "bind-active-world-runtime restores runtime interaction surface"
                     :fn bind-active-world-runtime-restores-runtime-interaction-surface})
(table.insert tests {:name "bind-active-world-runtime preserves explicit nil canvas mode"
                     :fn bind-active-world-runtime-preserves-explicit-nil-canvas-mode})
(table.insert tests {:name "bind-active-world-runtime defers canvas mode without canvas"
                      :fn bind-active-world-runtime-defers-canvas-mode-without-canvas})
(table.insert tests {:name "bind-active-world-runtime promotes active-canvas-mode to requested"
                      :fn bind-active-world-runtime-preserves-active-canvas-mode-as-requested})
(table.insert tests {:name "set-active-canvas-mode rejects unknown modes"
                     :fn set-active-canvas-mode-rejects-unknown-mode})
(table.insert tests {:name "Canvas modes ordered specs preserve registration order"
                     :fn canvas-modes-ordered-specs-preserve-registration-order})
(table.insert tests {:name "Invalid persisted canvas mode clears to nil"
                     :fn invalid-persisted-canvas-mode-clears-to-nil})
(table.insert tests {:name "Canvas mode activation failure restores previous mode"
                     :fn canvas-mode-activation-failure-restores-previous-mode})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "main-events"
                       :tests tests})))

{:name "main-events"
 :tests tests
 :main main}
