(local glm (require :glm))
(local RawPolyhedron (require :raw-polyhedron))
(local MathUtils (require :math-utils))
(local {: Layout : resolve-mark-flag} (require :layout))

(fn resolve-size [value fallback]
  (if
    (= value nil) fallback
    (= (type value) :userdata) value
    (= (type value) :number) (glm.vec3 value value value)
    (= (type value) :table)
      (do
        (local x (or (. value 1) value.x (. value "x") (and fallback fallback.x) 0))
        (local y (or (. value 2) value.y (. value "y") (and fallback fallback.y) 0))
        (local z (or (. value 3) value.z (. value "z") (and fallback fallback.z) 0))
        (glm.vec3 x y z))
    fallback))

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

(fn PolyhedronWidget [opts]
  (local options (or opts {}))
  (local default-size (resolve-size options.size (glm.vec3 16 16 16)))

  (fn build [ctx]
    (local entity {:visible? true
                   :render-visible? true})
    (var last-state nil)
    (local polyhedron
      ((RawPolyhedron {:triangles (assert options.triangles
                                         "PolyhedronWidget requires :triangles")
                       :color options.color})
       ctx))

    (fn measurer [self]
      (set self.measure default-size))

    (fn layouter [self]
      (local should-render (and entity.visible? (not (self:effective-culled?))))
      (polyhedron:set-visible should-render)
      (set entity.render-visible? should-render)
      (when should-render
        (local half-size (* self.size (glm.vec3 0.5 0.5 0.5)))
        (local next-state {:scale half-size
                           :position self.position
                           :rotation self.rotation
                           :depth-index self.depth-offset-index
                           :clip self.clip-region})
        (local changed
          (or (not last-state)
              (not (vec3-equal? last-state.scale next-state.scale))
              (not (vec3-equal? last-state.position next-state.position))
              (not (quat-equal? last-state.rotation next-state.rotation))
              (not (= last-state.depth-index next-state.depth-index))
              (not (= last-state.clip next-state.clip))))
        (when changed
          (set polyhedron.scale half-size)
          (set polyhedron.position self.position)
          (set polyhedron.rotation self.rotation)
          (set polyhedron.depth-offset-index self.depth-offset-index)
          (set polyhedron.clip-region self.clip-region)
          (polyhedron:update)
          (set last-state next-state))))

    (local layout
      (Layout {:name (or options.name "polyhedron")
               :measurer measurer
               :layouter layouter}))

    (fn set-visible [self visible? opts2]
      (local desired (not (not visible?)))
      (local mark-layout-dirty? (resolve-mark-flag opts2 :mark-layout-dirty? false))
      (when (not (= desired self.visible?))
        (set self.visible? desired)
        (polyhedron:set-visible desired)
        (when (and mark-layout-dirty? self.layout)
          (self.layout:mark-layout-dirty))))

    {:layout layout
     :set-visible set-visible
     :drop (fn [self]
             (self.layout:drop)
             (polyhedron:drop))
     :visible? true
     :render-visible? true}))

PolyhedronWidget
