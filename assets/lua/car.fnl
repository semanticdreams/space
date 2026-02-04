(local glm (require :glm))
(local MathUtils (require :math-utils))
(local {: Layout : resolve-mark-flag} (require :layout))

(fn clamp [value min-value max-value]
  (math.min (math.max value min-value) max-value))

(local approx (. MathUtils :approx))

(fn vec3-equal? [a b]
  (and a b
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn quat-equal? [a b]
  (and a b
       (approx a.w b.w)
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn resolve-number [value fallback]
  (if (= value nil) fallback value))

(fn resolve-angle [value fallback]
  (if (= value nil) fallback value))

(fn resolve-color [value fallback]
  (if (= value nil) fallback value))

(local add-quad
  (fn [positions colors a b c d color]
    (table.insert positions a)
    (table.insert positions b)
    (table.insert positions c)
    (table.insert positions a)
    (table.insert positions c)
    (table.insert positions d)
    (table.insert colors color)
    (table.insert colors color)
    (table.insert colors color)
    (table.insert colors color)
    (table.insert colors color)
    (table.insert colors color)))

(local add-tri
  (fn [positions colors a b c color]
    (table.insert positions a)
    (table.insert positions b)
    (table.insert positions c)
    (table.insert colors color)
    (table.insert colors color)
    (table.insert colors color)))

(local add-rect-prism
  (fn [positions colors min-point max-point color]
    (local x1 min-point.x)
    (local y1 min-point.y)
    (local z1 min-point.z)
    (local x2 max-point.x)
    (local y2 max-point.y)
    (local z2 max-point.z)
    (local p000 (glm.vec3 x1 y1 z1))
    (local p001 (glm.vec3 x1 y1 z2))
    (local p010 (glm.vec3 x1 y2 z1))
    (local p011 (glm.vec3 x1 y2 z2))
    (local p100 (glm.vec3 x2 y1 z1))
    (local p101 (glm.vec3 x2 y1 z2))
    (local p110 (glm.vec3 x2 y2 z1))
    (local p111 (glm.vec3 x2 y2 z2))
    ; bottom, top, front, back, left, right
    (add-quad positions colors p000 p100 p101 p001 color)
    (add-quad positions colors p010 p011 p111 p110 color)
    (add-quad positions colors p000 p001 p011 p010 color)
    (add-quad positions colors p100 p110 p111 p101 color)
    (add-quad positions colors p001 p101 p111 p011 color)
    (add-quad positions colors p000 p010 p110 p100 color)))

(local add-slope
  (fn [positions colors x1 x2 base-height front-height back-height width inset color]
    (local z1 inset)
    (local z2 (- width inset))
    (local front-left (glm.vec3 x1 front-height z1))
    (local front-right (glm.vec3 x1 front-height z2))
    (local back-left (glm.vec3 x2 back-height z1))
    (local back-right (glm.vec3 x2 back-height z2))
    (local base-front-left (glm.vec3 x1 base-height z1))
    (local base-front-right (glm.vec3 x1 base-height z2))
    (local base-back-left (glm.vec3 x2 base-height z1))
    (local base-back-right (glm.vec3 x2 base-height z2))
    (add-quad positions colors front-left back-left back-right front-right color)
    (add-quad positions colors base-front-left front-left front-right base-front-right color)
    (add-quad positions colors base-back-left base-back-right back-right back-left color)))

(local add-window-strip
  (fn [positions colors x1 x2 y1 y2 z color]
    (local a (glm.vec3 x1 y1 z))
    (local b (glm.vec3 x2 y1 z))
    (local c (glm.vec3 x2 y2 z))
    (local d (glm.vec3 x1 y2 z))
    (add-quad positions colors a b c d color)))

(local add-arch-strip
  (fn [positions colors opts]
    (local center-x opts.center-x)
    (local radius opts.radius)
    (local segments (math.max 3 opts.segments))
    (local color opts.color)
    (local z opts.z)
    (for [i 0 (- segments 1)]
      (local t1 (/ i segments))
      (local t2 (/ (+ i 1) segments))
      (local angle1 (* math.pi t1))
      (local angle2 (* math.pi t2))
      (local x1 (+ center-x (* radius (math.cos angle1))))
      (local x2 (+ center-x (* radius (math.cos angle2))))
      (local y1 (math.max 0 (* radius (math.sin angle1))))
      (local y2 (math.max 0 (* radius (math.sin angle2))))
      (local base1 (glm.vec3 x1 0 z))
      (local base2 (glm.vec3 x2 0 z))
      (local arch1 (glm.vec3 x1 y1 z))
      (local arch2 (glm.vec3 x2 y2 z))
      (add-quad positions colors base1 base2 arch2 arch1 color))))

(local add-wheel
  (fn [positions colors opts]
    (local center opts.center)
    (local radius opts.radius)
    (local width opts.width)
    (local segments (math.max 6 opts.segments))
    (local color opts.color)
    (local half-width (* 0.5 width))
    (local center-left (+ center (glm.vec3 0 0 (- half-width))))
    (local center-right (+ center (glm.vec3 0 0 half-width)))
    (for [i 0 (- segments 1)]
      (local t1 (/ i segments))
      (local t2 (/ (+ i 1) segments))
      (local angle1 (* math.pi 2 t1))
      (local angle2 (* math.pi 2 t2))
      (local x1 (* radius (math.cos angle1)))
      (local y1 (* radius (math.sin angle1)))
      (local x2 (* radius (math.cos angle2)))
      (local y2 (* radius (math.sin angle2)))
      (local rim1-left (+ center (glm.vec3 x1 y1 (- half-width))))
      (local rim2-left (+ center (glm.vec3 x2 y2 (- half-width))))
      (local rim1-right (+ center (glm.vec3 x1 y1 half-width)))
      (local rim2-right (+ center (glm.vec3 x2 y2 half-width)))
      (add-quad positions colors rim1-left rim2-left rim2-right rim1-right color)
      (add-tri positions colors center-left rim1-left rim2-left color)
      (add-tri positions colors center-right rim2-right rim1-right color))))

(local MeshBuilder {})

(set MeshBuilder.build
     (fn [opts]
       (local options (or opts {}))
       (local body-length (math.max 6 (resolve-number options.body-length 24)))
       (local body-width (math.max 3 (resolve-number options.body-width 10)))
       (local body-height (math.max 2 (resolve-number options.body-height 6)))
       (local roof-height (math.max 0 (resolve-number options.roof-height 3)))
       (local wheel-arch-radius
         (clamp (resolve-number options.wheel-arch-radius 1.8) 0.25 (- body-height 0.25)))
       (local wheel-width (math.max 0.6 (resolve-number options.wheel-width 1.2)))
       (local wheel-segments (math.max 10 (resolve-number options.wheel-segments 16)))
       (local hood-angle (resolve-angle options.hood-angle (math.rad 14)))
       (local rear-slope (resolve-angle options.rear-slope (math.rad 12)))
       (local window-height (math.max 0.5 (resolve-number options.window-height 1.6)))
       (local chamfer (clamp (resolve-number options.chamfer 0.6) 0  (* 0.45 body-width)))
       (local base-color (resolve-color options.body-color (glm.vec4 0.18 0.35 0.72 1.0)))
       (local roof-color (resolve-color options.roof-color (glm.vec4 0.2 0.4 0.78 1.0)))
       (local glass-color (resolve-color options.window-color (glm.vec4 0.2 0.65 0.95 0.55)))
       (local trim-color (resolve-color options.trim-color (glm.vec4 0.08 0.1 0.12 1.0)))
       (local tire-color (resolve-color options.tire-color (glm.vec4 0.05 0.05 0.05 1.0)))
       (local positions [])
       (local colors [])

       (local total-height (+ body-height roof-height))
       (local hood-length (* body-length 0.26))
       (local cabin-length (* body-length 0.42))
       (local tail-length (math.max 1 (- body-length (+ hood-length cabin-length))))
       (local hood-end hood-length)
       (local cabin-end (+ hood-end cabin-length))

       (local hood-peak (+ body-height (* 0.6 roof-height)))
       (local hood-drop (* (math.tan hood-angle) hood-length))
       (local front-top (math.max body-height (- hood-peak hood-drop)))
       (local rear-peak (+ body-height (* 0.55 roof-height)))
       (local rear-drop (* (math.tan rear-slope) tail-length))
       (local rear-height (math.max body-height (- rear-peak rear-drop)))

       (add-rect-prism positions colors
                       (glm.vec3 0 0 0)
                       (glm.vec3 body-length body-height body-width)
                       base-color)

       (add-slope positions colors
                  0 hood-end body-height front-top hood-peak body-width chamfer base-color)

       (add-rect-prism positions colors
                       (glm.vec3 hood-end body-height chamfer)
                       (glm.vec3 cabin-end total-height (- body-width chamfer))
                       roof-color)

       (add-slope positions colors
                  cabin-end body-length body-height rear-peak rear-height body-width chamfer base-color)

       (local window-bottom (+ body-height 0.2))
       (local window-top (math.min total-height (+ window-bottom window-height)))
       (local window-inset (+ chamfer (* 0.15 body-width)))
       (add-window-strip positions colors
                         (+ hood-end (* 0.05 cabin-length))
                         (- cabin-end (* 0.05 cabin-length))
                         window-bottom window-top
                         window-inset
                         glass-color)
       (add-window-strip positions colors
                         (+ hood-end (* 0.05 cabin-length))
                         (- cabin-end (* 0.05 cabin-length))
                         window-bottom window-top
                         (- body-width window-inset)
                         glass-color)

       (local front-axle (* 0.25 body-length))
       (local rear-axle (* 0.72 body-length))
       (local arch-segments 8)
       (add-arch-strip positions colors {:center-x front-axle
                                         :width body-width
                                         :radius wheel-arch-radius
                                         :segments arch-segments
                                         :color trim-color
                                         :z chamfer})
       (add-arch-strip positions colors {:center-x rear-axle
                                         :width body-width
                                         :radius wheel-arch-radius
                                         :segments arch-segments
                                         :color trim-color
                                         :z chamfer})
       (add-arch-strip positions colors {:center-x front-axle
                                         :width body-width
                                         :radius wheel-arch-radius
                                         :segments arch-segments
                                         :color trim-color
                                         :z (- body-width chamfer)})
       (add-arch-strip positions colors {:center-x rear-axle
                                         :width body-width
                                         :radius wheel-arch-radius
                                         :segments arch-segments
                                         :color trim-color
                                         :z (- body-width chamfer)})

       (local wheel-height wheel-arch-radius)
       (local left-z (- (* 0.5 wheel-width)))
       (local right-z (+ body-width (* 0.5 wheel-width)))
       (add-wheel positions colors {:center (glm.vec3 front-axle wheel-height left-z)
                                    :radius wheel-arch-radius
                                    :width wheel-width
                                    :segments wheel-segments
                                    :color tire-color})
       (add-wheel positions colors {:center (glm.vec3 rear-axle wheel-height left-z)
                                    :radius wheel-arch-radius
                                    :width wheel-width
                                    :segments wheel-segments
                                    :color tire-color})
       (add-wheel positions colors {:center (glm.vec3 front-axle wheel-height right-z)
                                    :radius wheel-arch-radius
                                    :width wheel-width
                                    :segments wheel-segments
                                    :color tire-color})
       (add-wheel positions colors {:center (glm.vec3 rear-axle wheel-height right-z)
                                    :radius wheel-arch-radius
                                    :width wheel-width
                                    :segments wheel-segments
                                    :color tire-color})

       {:positions positions
        :colors colors
        :vertex-count (length positions)
        :size (glm.vec3 body-length total-height (+ body-width (* 2 wheel-width)))
        :wheel-radius wheel-arch-radius
        :wheel-width wheel-width
        :front-axle front-axle
        :rear-axle rear-axle
        :body-length body-length
        :body-width body-width
        :body-height body-height
        :total-height total-height
        :wheel-height wheel-height
        :bounds {:min (glm.vec3 0 0 (- wheel-width))
                 :max (glm.vec3 body-length total-height (+ body-width wheel-width))
                 :size (glm.vec3 body-length total-height (+ body-width (* 2 wheel-width)))}}))

(fn RenderBuffer [ctx mesh]
       (assert (and ctx ctx.triangle-vector)
               "Car requires a triangle-vector in the build context")
       (local vector ctx.triangle-vector)
       (local vertex-count mesh.vertex-count)
       (local handle-size (* vertex-count 8))
       (var handle (vector:allocate handle-size))

       (fn ensure-handle []
         (when (not handle)
           (set handle (vector:allocate handle-size))))

       (fn release-handle []
         (when handle
           (when (and ctx ctx.untrack-triangle-handle)
             (ctx:untrack-triangle-handle handle))
           (vector:delete handle)
           (set handle nil)))

       (local state {:visible? true
                     :last-depth nil
                     :last-clip nil})

       (fn set-visible [self visible?]
         (local desired (not (not visible?)))
         (when (not (= desired self.visible?))
           (set self.visible? desired)
           (if desired
               (ensure-handle)
               (release-handle))))

       (fn update [self args]
         (when (not self.visible?)
           (self:set-visible true))
         (ensure-handle)
         (local position (or args.position (glm.vec3 0 0 0)))
         (local rotation (or args.rotation (glm.quat 1 0 0 0)))
         (local depth-index (or args.depth-index 0))
         (local clip-region args.clip-region)
         (set self.last-depth depth-index)
         (set self.last-clip clip-region)
	         (for [i 1 vertex-count]
	           (local vertex-offset (* (- i 1) 8))
	           (local local-position (. mesh.positions i))
	           (local rotated (rotation:rotate local-position))
	           (local final-position (+ position rotated))
	           (vector:set-glm-vec3 handle vertex-offset final-position)
	           (vector:set-glm-vec4 handle (+ vertex-offset 3) (. mesh.colors i))
	           (vector:set-float handle (+ vertex-offset 7) depth-index))
	         (when (and ctx ctx.track-triangle-handle)
	           (ctx:track-triangle-handle handle clip-region)))

       (set state.update update)
       (set state.set-visible set-visible)
       (set state.drop (fn [self] (release-handle)))
       state)

(fn Car [opts]
  (local options (or opts {}))
  (local mesh (MeshBuilder.build options))
  (local default-color (or options.body-color (glm.vec4 0.18 0.35 0.72 1.0)))

  (fn build [ctx]
    (local renderable (RenderBuffer ctx mesh))
    (local entity {:color default-color
                   :bounds {:min (glm.vec3 0 0 0)
                            :max mesh.bounds.max
                            :size mesh.size}
                   :visible? true
                   :render-visible? true
                   :mesh mesh})
    (var last-position nil)
    (var last-rotation nil)
    (var last-depth nil)
    (var last-clip nil)

    (fn measurer [self]
      (set self.measure mesh.size))

    (fn layouter [self]
      (local culled? (self:effective-culled?))
      (local should-render (and entity.visible? (not culled?)))
      (renderable:set-visible should-render)
      (set entity.render-visible? should-render)
      (when should-render
        (local position self.position)
        (local rotation self.rotation)
        (local depth-index self.depth-offset-index)
        (local clip self.clip-region)
        (local changed
          (or (not last-position)
              (not (vec3-equal? last-position position))
              (not (quat-equal? last-rotation rotation))
              (not (= last-depth depth-index))
              (not (= last-clip clip))))
        (when changed
          (renderable:update {:position position
                              :rotation rotation
                              :depth-index depth-index
                              :clip-region clip})
          (set last-position position)
          (set last-rotation rotation)
          (set last-depth depth-index)
          (set last-clip clip))))

    (local layout
      (Layout {:name "car"
               : measurer
               : layouter}))

    (fn set-visible [self visible? opts2]
      (local desired (not (not visible?)))
      (local mark-layout-dirty? (resolve-mark-flag opts2 :mark-layout-dirty? false))
      (when (not (= desired entity.visible?))
        (set entity.visible? desired)
        (renderable:set-visible desired)
        (when (and mark-layout-dirty? self.layout)
          (self.layout:mark-layout-dirty))))

    (set entity.layout layout)
    (set entity.set-visible set-visible)
    (set entity.drop (fn [self]
                       (self.layout:drop)
                       (renderable:drop)))
    entity))

Car
