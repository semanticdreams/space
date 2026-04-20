(local glm (require :glm))
(local Signal (require :signal))
(local RawRectangle (require :raw-rectangle))

(fn BoxSelector [opts]
    (local options (or opts {}))
    (local ctx options.ctx)
    (local rectangle-builder
      (or options.rectangle-builder
          (and ctx
               (RawRectangle {:color (or options.color (glm.vec4 0 0 0 0.3))
                              :position (glm.vec3 0 0 0)
                              :size (glm.vec2 0 0)}))))
    (local hud (or options.hud (and ctx ctx.pointer-target)))
    (local changed (Signal))
    (local exited (Signal))
    (var rectangle nil)
    (var active? false)
    (var start-pos nil)
    (var end-pos nil)

    (fn resolve-pointer-target []
        (local pointer-target (or hud (and ctx ctx.pointer-target)))
        (assert pointer-target "BoxSelector requires a pointer target")
        (assert pointer-target.screen-pos-ray
                "BoxSelector requires pointer target with screen-pos-ray")
        pointer-target)

    (fn world-point-from-ray [point]
        (local pointer-target (resolve-pointer-target))
        (local ray-opts {})
        (when options.viewport
            (set ray-opts.viewport options.viewport))
        (when options.view
            (set ray-opts.view options.view))
        (when options.projection
            (set ray-opts.projection options.projection))
        (local ray (pointer-target:screen-pos-ray point ray-opts))
        (assert (and ray ray.origin ray.direction)
                "BoxSelector pointer target returned invalid ray")
        (local dz (or ray.direction.z 0))
        (assert (not (= dz 0))
                "BoxSelector pointer target ray is parallel to selection plane")
        (let [plane-z (or options.plane-z 0)
              t (/ (- plane-z ray.origin.z) dz)]
            (+ ray.origin (* ray.direction t))))

    (fn create-rectangle []
        (when (and (not rectangle) rectangle-builder ctx)
            (set rectangle (if (= (type rectangle-builder) :function)
                               (rectangle-builder ctx)
                               rectangle-builder))
            (when (not (= options.depth-offset-index nil))
                (set rectangle.depth-offset-index options.depth-offset-index))
            (rectangle:set-visible false)))

    (fn drop-rectangle []
        (when rectangle
            (rectangle:drop)
            (set rectangle nil)))

    (fn update-rectangle []
        (when (and rectangle start-pos end-pos)
            (local a (world-point-from-ray start-pos))
            (local b (world-point-from-ray end-pos))
            (let [min-x (math.min a.x b.x)
                  max-x (math.max a.x b.x)
                  min-y (math.min a.y b.y)
                  max-y (math.max a.y b.y)
                  width (- max-x min-x)
                  height (- max-y min-y)]
                (set rectangle.rotation (glm.quat 1 0 0 0))
                (set rectangle.position (glm.vec3 min-x min-y (or a.z 0)))
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
            (if payload.state
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
