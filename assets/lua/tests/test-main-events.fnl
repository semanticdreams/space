(local _ (require :main))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))

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
    (when (and app.engine.events app.engine.events.window-resized)
      (set app.window-resized-handler
           (app.engine.events.window-resized:connect
             (fn [e]
               (app.set-viewport {:width e.width :height e.height})
               (app.reset-projection)))))
    (app.set-viewport {:width 0 :height 0})
    (set app.layout-root nil)))

(fn window-resize-updates-viewport-and-layout-root []
  (reset-state)
  (ensure-renderers)
  (app.engine.events.window-resized.emit {:width 640 :height 360})
  (assert (= app.viewport.width 640))
  (assert (= app.viewport.height 360)))

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

(table.insert tests {:name "Window resize updates viewport and layout root" :fn window-resize-updates-viewport-and-layout-root})
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
