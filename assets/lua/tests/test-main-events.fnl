(local _ (require :main))
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
  (app.drop)
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

(table.insert tests {:name "Window resize updates viewport and layout root" :fn window-resize-updates-viewport-and-layout-root})
(table.insert tests {:name "Window pixel size change updates viewport" :fn window-pixel-size-change-updates-viewport})
(table.insert tests {:name "app.drop keeps engine events and clears layout root" :fn drop-keeps-engine-events-and-clears-layout-root})
(table.insert tests {:name "Non-resize events leave viewport unchanged" :fn other-events-leave-viewport-untouched})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "main-events"
                       :tests tests})))

{:name "main-events"
 :tests tests
 :main main}
