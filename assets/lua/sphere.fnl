(local glm (require :glm))
(local RawSphere (require :raw-sphere))
(local MathUtils (require :math-utils))
(local {: Layout : resolve-mark-flag} (require :layout))

(fn resolve-size [value fallback]
  (if
    (= value nil) fallback
    (= (type value) :userdata) value
    (= (type value) :number) (glm.vec3 value value value)
    (= (type value) :table)
      (let [x (or (. value 1) value.x (. value "x") (and fallback fallback.x) 0)
            y (or (. value 2) value.y (. value "y") (and fallback fallback.y) 0)
            z (or (. value 3) value.z (. value "z") (and fallback fallback.z) 0)]
        (glm.vec3 x y z))
    fallback))

(local approx (. MathUtils :approx))

(local vec3-equal? (fn [a b]
                     (and a b
                          (approx a.x b.x)
                          (approx a.y b.y)
                          (approx a.z b.z))))

(local quat-equal? (fn [a b]
                     (and a b
                          (approx a.w b.w)
                          (approx a.x b.x)
                          (approx a.y b.y)
                          (approx a.z b.z))))

(fn Sphere [opts]
  (local options (or opts {}))
  (local default-radius (or options.radius 8))
  (local fallback-size (glm.vec3 (* 2 default-radius)
                             (* 2 default-radius)
                             (* 2 default-radius)))
  (local default-size (resolve-size options.size fallback-size))
  (local default-scale (glm.vec3 (* 0.5 default-size.x)
                             (* 0.5 default-size.y)
                             (* 0.5 default-size.z)))
  (local default-color (or options.color (glm.vec4 0.4 0.75 1.0 1.0)))

  (fn build [ctx]
    (local entity {:color default-color
                   :visible? true
                   :render-visible? true})
    (var last-state nil)

    (local sphere
      ((RawSphere {:color entity.color
                   :scale default-scale
                   :segments options.segments
                   :rings options.rings})
       ctx))

    (fn measurer [self]
      (set self.measure default-size))

    (fn layouter [self]
      (local should-render (and entity.visible? (not (self:effective-culled?))))
      (sphere:set-visible should-render)
      (set entity.render-visible? should-render)
      (when should-render
        (local half-size (glm.vec3 (* 0.5 self.size.x)
                               (* 0.5 self.size.y)
                               (* 0.5 self.size.z)))
        (local next-state {:color entity.color
                           :scale half-size
                           :position self.position
                           :rotation self.rotation
                           :depth-index self.depth-offset-index
                           :clip self.clip-region})
        (local changed
          (or (not last-state)
              (not (vec3-equal? last-state.scale next-state.scale))
              (not (vec3-equal? last-state.position next-state.position))
              (not (quat-equal? last-state.rotation next-state.rotation))
              (not (= last-state.color next-state.color))
              (not (= last-state.depth-index next-state.depth-index))
              (not (= last-state.clip next-state.clip))))
        (when changed
          (set sphere.color entity.color)
          (set sphere.scale half-size)
          (set sphere.position self.position)
          (set sphere.rotation self.rotation)
          (set sphere.depth-offset-index self.depth-offset-index)
          (set sphere.clip-region self.clip-region)
          (sphere:update)
          (set last-state next-state))))

    (local layout
      (Layout {:name "sphere"
               : measurer
               : layouter}))

    (fn set-visible [self visible? opts2]
      (local desired (not (not visible?)))
      (local mark-layout-dirty? (resolve-mark-flag opts2 :mark-layout-dirty? false))
      (when (not (= desired self.visible?))
        (set self.visible? desired)
        (sphere:set-visible desired)
        (when (and mark-layout-dirty? self.layout)
          (self.layout:mark-layout-dirty))))

    (set entity.layout layout)
    (set entity.set-visible set-visible)
    (set entity.drop (fn [self]
                       (self.layout:drop)
                       (sphere:drop)))
    entity))

Sphere
