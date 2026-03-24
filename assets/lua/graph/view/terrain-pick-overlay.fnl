(local glm (require :glm))
(local RawRectangle (require :raw-rectangle))
(local viewport-utils (require :viewport-utils))

(fn TerrainPickOverlay [opts]
  (local options (or opts {}))
  (local hud (assert (or options.hud app.hud)
                     "TerrainPickOverlay requires a HUD target"))
  (local ctx (assert (and hud hud.build-context)
                     "TerrainPickOverlay requires hud.build-context"))
  (local color (or options.color (glm.vec4 0 0 0 0.3)))
  (local depth-offset-index
    (if (not (= options.depth-offset-index nil))
        options.depth-offset-index
        1000))
  (local rectangle
    ((RawRectangle {:color color
                    :position (glm.vec3 0 0 0)
                    :size (glm.vec2 0 0)})
     ctx))
  (var active? false)
  (var start-pos nil)
  (var end-pos nil)

  (set rectangle.depth-offset-index depth-offset-index)
  (rectangle:set-visible false)

  (fn to-hud-point [point]
    (local viewport (viewport-utils.to-table (or options.viewport app.viewport)))
    (local units (or hud.world-units-per-pixel 1))
    (local px (- (or point.x 0) viewport.x))
    (local py (- (or point.y 0) viewport.y))
    (local centered-x (- px (/ viewport.width 2)))
    (local centered-y (- (/ viewport.height 2) py))
    (glm.vec2 (* centered-x units)
              (* centered-y units)))

  (fn update-rectangle []
    (when (and active? start-pos end-pos)
      (local a (to-hud-point start-pos))
      (local b (to-hud-point end-pos))
      (local min-x (math.min a.x b.x))
      (local max-x (math.max a.x b.x))
      (local min-y (math.min a.y b.y))
      (local max-y (math.max a.y b.y))
      (set rectangle.rotation (glm.quat 1 0 0 0))
      (set rectangle.position (glm.vec3 min-x min-y 0))
      (set rectangle.size (glm.vec2 (- max-x min-x)
                                    (- max-y min-y)))
      (rectangle:set-visible true)
      (rectangle:update)))

  (local self
    {:active? (fn [_self] active?)
     :begin (fn [_self pos]
              (set start-pos {:x pos.x :y pos.y})
              (set end-pos start-pos)
              (set active? true)
              (update-rectangle)
              true)
     :update (fn [_self pos]
               (when active?
                 (set end-pos {:x pos.x :y pos.y})
                 (update-rectangle))
               true)
     :finish (fn [_self]
               (when active?
                 (set active? false)
                 (rectangle:set-visible false))
               true)
     :cancel (fn [self]
               (self:finish))
     :drop (fn [_self]
             (set active? false)
             (rectangle:drop))})
  self)

TerrainPickOverlay
