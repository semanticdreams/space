(local glm (require :glm))
(local Signal (require :signal))
(local RawRectangle (require :raw-rectangle))
(local viewport-utils (require :viewport-utils))

(fn default-unproject [point depth opts]
    (local options (or opts {}))
    (local viewport (viewport-utils.to-table (or options.viewport app.viewport)))
    (local view (or options.view
                    (and app.scene app.scene.get-view-matrix
                         (app.scene:get-view-matrix))
                    (and app.camera app.camera.get-view-matrix
                         (app.camera:get-view-matrix))))
    (local projection (or options.projection app.projection))
    (when (and glm glm.unproject view projection)
        (local inverted-y (- (+ viewport.height viewport.y) point.y))
        (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
        (glm.unproject (glm.vec3 point.x inverted-y depth) view projection viewport-vec)))

(fn clamp-rectangle [a b]
    (local min-x (math.min a.x b.x))
    (local max-x (math.max a.x b.x))
    (local min-y (math.min a.y b.y))
    (local max-y (math.max a.y b.y))
    [{:x min-x :y min-y} {:x max-x :y max-y}])

(fn BoxSelector [opts]
    (local options (or opts {}))
    (local ctx options.ctx)
    (local unproject (or options.unproject default-unproject))
    (local rectangle-builder
      (or options.rectangle-builder
          (and ctx
               (RawRectangle {:color (or options.color (glm.vec4 0 0 0 0.3))
                              :position (glm.vec3 0 0 0)
                              :size (glm.vec2 0 0)}))))
    (local hud (or options.hud (and ctx ctx.pointer-target)))
    (local rectangle-depth-offset-index
      (if (not (= options.depth-offset-index nil))
          options.depth-offset-index
          1000))
    (local changed (Signal))
    (local exited (Signal))
    (var rectangle nil)
    (var active? false)
    (var start-pos nil)
    (var end-pos nil)

    (fn create-rectangle []
        (when (and (not rectangle) rectangle-builder ctx)
            (set rectangle (if (= (type rectangle-builder) :function)
                               (rectangle-builder ctx)
                               rectangle-builder))
            (when (not (= rectangle.depth-offset-index nil))
                (set rectangle.depth-offset-index rectangle-depth-offset-index))
            (rectangle:set-visible false)))

    (fn drop-rectangle []
        (when rectangle
            (rectangle:drop)
            (set rectangle nil)))

    (fn update-rectangle []
        (when (and rectangle start-pos end-pos)
            (local viewport (viewport-utils.to-table (or options.viewport app.viewport)))
            (local units (and hud hud.world-units-per-pixel))
            (fn to-hud [point]
              (if (and units viewport)
                  (let [px (- (or point.x 0) viewport.x)
                        py (- (or point.y 0) viewport.y)
                        centered-x (- px (/ viewport.width 2))
                        centered-y (- (/ viewport.height 2) py)]
                    (glm.vec2 (* centered-x units) (* centered-y units)))
                  (glm.vec2 (or point.x 0) (or point.y 0))))
            (local a (to-hud start-pos))
            (local b (to-hud end-pos))
            (let [min-x (math.min a.x b.x)
                  max-x (math.max a.x b.x)
                  min-y (math.min a.y b.y)
                  max-y (math.max a.y b.y)
                  width (- max-x min-x)
                  height (- max-y min-y)]
                (set rectangle.rotation (glm.quat 1 0 0 0))
                (set rectangle.position (glm.vec3 min-x min-y 0))
                (set rectangle.size (glm.vec2 width height)))
            (rectangle:set-visible true)
            (rectangle:update)))

    (fn start-selection [self payload]
        (when (not active?)
            (create-rectangle)
            (set start-pos {:x payload.x :y payload.y})
            (set end-pos start-pos)
            (set active? true)
            (update-rectangle self)))

    (fn stop-selection [self opts]
        (when active?
            (local emit? (if (= (type opts) :table)
                              (if (not (= opts.emit? nil)) opts.emit? true)
                              (if (= opts nil) true opts)))
            (set active? false)
            (when rectangle
                (rectangle:set-visible false)
                (drop-rectangle))
            (when emit?
                (changed:emit {:p1 start-pos :p2 end-pos}))))

    (fn cancel [self]
        (stop-selection self {:emit? false}))

    (fn on-mouse-button [self payload]
        (when (= payload.button 1)
            (if (= payload.state 1)
                (start-selection self payload)
                (stop-selection self))))

    (fn on-mouse-motion [self payload]
        (when active?
            (set end-pos {:x payload.x :y payload.y})
            (update-rectangle self)))

    (fn on-key-down [self payload]
        (when (and (= payload.key 27) active?)
            (stop-selection self))
        (when (= payload.key 27)
            (exited:emit)))

    (fn drop [self]
        (cancel self)
        (changed:clear)
        (exited:clear))

    {:changed changed
     :exited exited
     :active? (fn [_self] active?)
     :start-selection start-selection
     :stop-selection stop-selection
     :cancel cancel
     :on-mouse-button on-mouse-button
     :on-mouse-motion on-mouse-motion
     :on-key-down on-key-down
     :drop drop})

BoxSelector
