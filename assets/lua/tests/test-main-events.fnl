(local Main (require :main))
(local CanvasFeatures (require :canvas-features))
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

(local bind-state-keys
  [:active-canvas-feature
   :active-interaction-surface
   :active-pointer-controls
   :active-world-entry
   :active-world-hud-contrib
   :active-world-hud-overlay
   :active-world-runtime
   :bind-active-world-runtime
   :camera
   :canvas
   :canvas-controls
   :canvas-focus-scope
   :canvas-interactive?
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
   :set-active-canvas-feature
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
  (Main.drop-app!)
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
      (var restored false)
      (var active-canvas-feature nil)
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
          {:active-canvas-feature "drawing"
           :preferred-interaction-surface :canvas
           :restore-surface-state (fn [_self _canvas _hud]
                                    (set restored true))
           :first-person-controls first-person-controls
           :canvas-controls canvas-controls
           :scene nil
           :canvas {:build-context {}
                    :restore-state (fn [_self _state] true)}})
        (set active-canvas-feature app.active-canvas-feature)
        (set preferred-surface app.preferred-interaction-surface)
        (set active-surface app.active-interaction-surface)
        (set canvas-visible? app.canvas-visible?)
        (set canvas-interactive? app.canvas-interactive?)
      (assert restored "bind-active-world-runtime should restore target surface state before shell sync")
      (assert (= active-canvas-feature "drawing")
              "bind-active-world-runtime should restore active canvas feature from runtime")
      (assert (= preferred-surface :canvas)
              "bind-active-world-runtime should adopt runtime interaction surface preference")
      (assert (= active-surface :canvas)
              "bind-active-world-runtime should restore canvas as the active interaction surface")
      (assert (= canvas-visible? true)
              "bind-active-world-runtime should restore canvas visibility when canvas mode was persisted")
      (assert (= canvas-interactive? true)
              "bind-active-world-runtime should re-enable canvas interaction when canvas mode was persisted")
      true)))

(fn set-active-canvas-feature-rejects-unknown-feature []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (local (ok err)
        (pcall
          (fn []
            (app.set-active-canvas-feature "bogus"))))
      (assert (not ok)
              "set-active-canvas-feature should reject unknown canvas features")
      (assert (and err (string.find err "Unknown canvas feature"))
              "set-active-canvas-feature should report the invalid feature id clearly")
      true)))

(fn canvas-features-ordered-specs-include-default-once []
  (local specs (CanvasFeatures.feature-specs-in-order))
  (assert (> (length specs) 0)
          "Canvas feature registry should expose at least one ordered feature spec")
  (local seen {})
  (var default-count 0)
  (each [_ feature-spec (ipairs specs)]
    (local feature-id (. feature-spec :id))
    (assert feature-id "Canvas feature registry entries should expose :id")
    (assert (not (. seen feature-id))
            (.. "Canvas feature registry should not duplicate ordered id " feature-id))
    (set (. seen feature-id) true)
    (when (= feature-id (. CanvasFeatures :default-feature-id))
      (set default-count (+ default-count 1))))
  (assert (= default-count 1)
          "Canvas feature registry should expose the default feature exactly once in order")
  true)

(table.insert tests {:name "Window resize updates viewport and layout root" :fn window-resize-updates-viewport-and-layout-root})
(table.insert tests {:name "Window pixel size change updates viewport" :fn window-pixel-size-change-updates-viewport})
(table.insert tests {:name "app.drop keeps engine events and clears layout root" :fn drop-keeps-engine-events-and-clears-layout-root})
(table.insert tests {:name "Non-resize events leave viewport unchanged" :fn other-events-leave-viewport-untouched})
(table.insert tests {:name "bind-active-world-runtime restores runtime interaction surface"
                     :fn bind-active-world-runtime-restores-runtime-interaction-surface})
(table.insert tests {:name "set-active-canvas-feature rejects unknown features"
                     :fn set-active-canvas-feature-rejects-unknown-feature})
(table.insert tests {:name "Canvas features ordered specs include default once"
                     :fn canvas-features-ordered-specs-include-default-once})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "main-events"
                       :tests tests})))

{:name "main-events"
 :tests tests
 :main main}
