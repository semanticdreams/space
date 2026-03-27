(local glm (require :glm))
(local MathUtils (require :math-utils))
(local {: Layout : resolve-mark-flag} (require :layout))
(local {: model-matrix} (require :static-triangle-buffer))
(local InstancedColorMeshBatch (require :instanced-color-mesh-batch))
(local SharedInstancedMeshCache (require :shared-instanced-mesh-cache))
(local SoccerBallMesh (require :soccer-ball-mesh))

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

(fn style-cache-key [options]
  (local style (SoccerBallMesh.style-key options))
  (.. "soccer-ball|seam="
      (SoccerBallMesh.vec4-key style.seam-color)
      "|inset="
      (SoccerBallMesh.scalar-key style.seam-inset)
      "|pentagon="
      (SoccerBallMesh.vec4-key style.pentagon-color)
      "|hexagon="
      (SoccerBallMesh.vec4-key style.hexagon-color)))

(fn ensure-shared-batch [ctx options]
  (local key (style-cache-key options))
  (SharedInstancedMeshCache.acquire
    ctx
    key
    (fn []
      (local mesh (SoccerBallMesh.build-mesh options))
      (InstancedColorMeshBatch
        ctx
        {:vertices mesh.vertices
         :indices mesh.indices
         :unlit false}))))

(fn SoccerBallVisual [opts]
  (local options (or opts {}))
  (local default-size (resolve-size options.size (glm.vec3 16 16 16)))

  (fn build [ctx]
    (local shared-entry (ensure-shared-batch ctx options))
    (local entity {:visible? true
                   :render-visible? true})
    (local instance (shared-entry.batch:add-instance (glm.mat4 1)))
    (var last-state nil)

    (fn measurer [self]
      (set self.measure default-size))

    (fn layouter [self]
      (local should-render (and entity.visible? (not (self:effective-culled?))))
      (shared-entry.batch:set-instance-visible instance should-render)
      (set entity.render-visible? should-render)
      (when should-render
        (local half-size (* self.size (glm.vec3 0.5 0.5 0.5)))
        (local next-state {:scale half-size
                           :position self.position
                           :rotation self.rotation})
        (local changed
          (or (not last-state)
              (not (vec3-equal? last-state.scale next-state.scale))
              (not (vec3-equal? last-state.position next-state.position))
              (not (quat-equal? last-state.rotation next-state.rotation))))
        (when changed
          (shared-entry.batch:update-instance-model
            instance
            (model-matrix self.position self.rotation half-size half-size))
          (set last-state next-state))))

    (local layout
      (Layout {:name "soccer-ball"
               :measurer measurer
               :layouter layouter}))

    (fn set-visible [self visible? opts2]
      (local desired (not (not visible?)))
      (local mark-layout-dirty? (resolve-mark-flag opts2 :mark-layout-dirty? false))
      (when (not (= desired self.visible?))
        (set self.visible? desired)
        (shared-entry.batch:set-instance-visible instance desired)
        (when (and mark-layout-dirty? self.layout)
          (self.layout:mark-layout-dirty))))

    {:layout layout
     :set-visible set-visible
     :drop (fn [self]
             (self.layout:drop)
             (shared-entry.batch:remove-instance instance)
             (SharedInstancedMeshCache.release ctx shared-entry))
     :visible? true
     :render-visible? true}))

SoccerBallVisual
