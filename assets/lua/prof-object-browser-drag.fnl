(global app {})
(local EngineModule (require :engine))
(local glm (require :glm))
(local os os)
(local math math)
(local string string)
(local package package)
(local debug debug)
(local logging (require :logging))

(fn install-fake-renderers []
  (fn FakeRenderers []
    (fn consume-vector [vector]
      (when (and vector vector.length)
        (vector:length)))

    (fn draw-target [_self target]
      (when (and target target.get-triangle-vector)
        (consume-vector (target:get-triangle-vector))
        (each [_ vector (pairs (target:get-text-vectors))]
          (consume-vector vector))))

    (fn update [self]
      (when app.scene
        (self:draw-target app.scene))
      (when app.hud
        (self:draw-target app.hud)))

    {:update update
     :draw-target draw-target
     :on-viewport-changed (fn [_ _] nil)
     :drop (fn [_] nil)})

  (set (. package.preload "renderers") (fn [] FakeRenderers)))

(install-fake-renderers)

(set app.disable_font_textures true)

(local FlamegraphProfiler (require :flamegraph-profiler))

(set app.engine (EngineModule.Engine {:headless true}))

(local _ (require :main))
(local Padding (require :padding))
(local Dialog (require :dialog))
(local ObjectBrowser (require :object-browser))

(local default-output-path "prof/object-browser-drag.folded")
(local viewport {:width 640 :height 480})
(local frame-delta (/ 1.0 60.0))
(local drag-frame-count 20)

(app.engine:start)

(fn to-lower [value]
  (and value (string.lower value)))

(fn use-default-output? [value]
  (local lower (to-lower value))
  (or (= value nil)
      (= value "")
      (= value "1")
      (= lower "true")
      (= lower "on")))

(fn flamegraph-disabled? [value]
  (local lower (to-lower value))
  (and value (or (= value "0")
                 (= lower "false")
                 (= lower "off"))))

(fn resolve-output-path []
  (local env (os.getenv "SPACE_FENNEL_FLAMEGRAPH"))
  (if (flamegraph-disabled? env)
      nil
      (if (use-default-output? env)
          default-output-path
          env)))

(local output-path (resolve-output-path))

(when (not output-path)
  (logging.info "SPACE_FENNEL_FLAMEGRAPH disabled; not recording object-browser drag profile.")
  (os.exit 0))

(local profiler (FlamegraphProfiler {:output-path output-path}))

(fn emit-initial-viewport []
  (local payload {:width viewport.width :height viewport.height :timestamp 0})
  (if (and app.engine.events app.engine.events.window-resized)
      (app.engine.events.window-resized.emit payload)
      (do
        (app.set-viewport {:width viewport.width :height viewport.height})
        (app.reset-projection))))

(fn make-object-browser-builder []
  (local browser
    (ObjectBrowser {:target (or app.engine {})
                    :name "space-browser"
                    :items-per-page 8
                    :item-padding [0.5 0.45]
                    :root-label "space"}))
  (local dialog
    (Dialog {:title "Object Browser"
             :child (Padding {:edge-insets [0.6 0.6]
                              :child browser})}))
  (local framed
    (Padding {:edge-insets [0.5 0.5]
              :child dialog}))
  (fn build [ctx]
    (local entity (framed ctx))
    (when entity.child
      (set entity.movables [entity.child])
      (set entity.object_browser_widget entity.child))
    entity))

(fn drop-hud []
  (when app.hud
    (app.hud:drop)
    (set app.hud nil)))

(fn set-simple-screen-ray []
  (set app.scene.screen-pos-ray
       (fn [_self pointer _opts]
         (local px (or pointer.x 0))
         (local py (or pointer.y 0))
         {:origin (glm.vec3 px py 10.0)
          :direction (glm.vec3 0 0 -1)})))

(fn rebuild-scene []
  (set app.scene.default-position (glm.vec3 0 0 0))
  (set app.scene.default-rotation (glm.quat 1 0 0 0))
  (local builder (make-object-browser-builder))
  (app.scene:build builder)
  (app.scene:update)
  (set app.layout-root app.scene.layout-root)
  (set-simple-screen-ray))

(fn size-root-to-measure []
  (local entity app.scene.entity)
  (local layout (and entity entity.layout))
  (when layout
    (layout:measurer)
    (set layout.size layout.measure)
    (layout:layouter)))

(fn warmup-frames [count]
  (var i 1)
  (while (<= i count)
    (app.update frame-delta)
    (set i (+ i 1))))

(fn layout-center [layout]
  (local position (or layout.position (glm.vec3 0 0 0)))
  (local half
    (glm.vec3 (/ (or layout.size.x 0) 2)
          (/ (or layout.size.y 0) 2)
          (/ (or layout.size.z 0) 2)))
  (+ position half))

(fn pointer-for-step [layout step total]
  (local center (layout-center layout))
  (local angle (* 2 math.pi (/ step total)))
  (local width (or layout.size.x 0))
  (local height (or layout.size.y 0))
  (local radius-x (math.max 0.5 (* (math.max width 1) 0.45)))
  (local radius-y (math.max 0.5 (* (math.max height 1) 0.35)))
  {:x (+ center.x (* (math.cos angle) radius-x))
   :y (+ center.y (* (math.sin angle) radius-y))})

(fn find-object-browser-entry []
  (local entity app.scene.entity)
  (local target-widget (and entity entity.object_browser_widget))
  (var found nil)
  (each [_ entry (ipairs (or app.movables.entries []))]
    (local source entry.source)
    (when (and (not found) entry
               (= source (or target-widget entity)))
      (set found entry)))
  found)

(fn run-drag-loop [layout]
  (local start (pointer-for-step layout 0 drag-frame-count))
  (set start.button 1)
  (app.engine.events.mouse-button-down.emit start)
  (app.update frame-delta)
  (assert (app.movables:drag-active?) "Failed to start drag on object browser")
  (var step 1)
  (while (<= step drag-frame-count)
    (local pointer (pointer-for-step layout step drag-frame-count))
    (app.engine.events.mouse-motion.emit pointer)
    (app.update frame-delta)
    (set step (+ step 1)))
  (local finish (pointer-for-step layout 0 drag-frame-count))
  (set finish.button 1)
  (app.engine.events.mouse-button-up.emit finish)
  (app.update frame-delta))

(fn profile-object-browser-drag []
  (app.init)
  (emit-initial-viewport)
  (drop-hud)
  (rebuild-scene)
  (size-root-to-measure)
  (warmup-frames 30)
  (local entry (find-object-browser-entry))
  (assert entry "Object browser entry not registered in Movables")
  (local target entry.target)
  (assert target "Object browser movable entry missing target layout")
  (profiler.start)
  (run-drag-loop target))

(local call-result (table.pack (xpcall profile-object-browser-drag debug.traceback)))
(local ok (. call-result 1))
(local err (. call-result 2))
(profiler.stop_and_flush)
(app.drop)

(app.engine:shutdown)

(if ok
    (logging.info (.. "Object browser drag profile written to " output-path))
    (error err))

true
