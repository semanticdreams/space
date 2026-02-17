(local glm (require :glm))
(local Rectangle (require :rectangle))
(local Cuboid (require :cuboid))
(local Sized (require :sized))
(local Positioned (require :positioned))
(local LayoutPhysicsBodies (require :layout-physics-bodies))

(fn new-cuboid []
  (Cuboid
    {:children
     [(Rectangle {:color (glm.vec4 0.9 0.0 0.0 1)})
      (Rectangle {:color (glm.vec4 0.0 0.9 0.1 1)})
      (Rectangle {:color (glm.vec4 0.0 0.0 0.9 1)})
      (Rectangle {:color (glm.vec4 0.0 0.9 0.9 1)})
      (Rectangle {:color (glm.vec4 1 0.9 0.0 1)})
      (Rectangle {:color (glm.vec4 0.9 0.0 0.9 1)})]}))

(fn make []
  (local spawn-pattern
    [{:spawn (glm.vec3 -30 -55 -20) :size (glm.vec3 8 5 8)}
     {:spawn (glm.vec3 6 -52 10) :size (glm.vec3 6 6 6)}
     {:spawn (glm.vec3 26 -48 -8) :size (glm.vec3 10 4 7)}])
  (local entries [])
  (local builders [])
  (each [_ desc (ipairs spawn-pattern)]
    (local offset (glm.vec3 desc.spawn.x desc.spawn.y desc.spawn.z))
    (local cube (Sized {:size desc.size
                        :child (new-cuboid)}))
    (local positioned (Positioned {:position offset
                                   :child cube}))
    (table.insert builders positioned)
    (table.insert entries {:spawn desc.spawn
                           :size desc.size
                           :offset offset
                           :positioned nil
                           :body nil
                           :body-active? false
                           :dragging false}))
  {:builders builders
   :entries entries})

{:new-cuboid new-cuboid
 :make make
 :attach LayoutPhysicsBodies.attach
 :add-runtime-layout-body LayoutPhysicsBodies.add-runtime-layout-body
 :remove-runtime-layout-body-for-element LayoutPhysicsBodies.remove-runtime-layout-body-for-element
 :collect-movables LayoutPhysicsBodies.collect-movables
 :sync LayoutPhysicsBodies.sync}
