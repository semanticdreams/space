(local glm (require :glm))
(local Rectangle (require :rectangle))
(local Cuboid (require :cuboid))
(local Sized (require :sized))
(local Positioned (require :positioned))

(local bt (require :bt))
(fn physics-available? []
  (and bt app.engine app.engine.physics))

(fn bt-glm-vec3 [value]
  (bt.Vector3 (or value.x 0) (or value.y 0) (or value.z 0)))

(fn physics-glm-vec3 [value]
  (glm.vec3 (or value.x 0) (or value.y 0) (or value.z 0)))

(fn ensure-physics-configured []
  (when (physics-available?)
    (app.engine.physics:setGravity 0 -25 0)))

(var attach-movables nil)

(fn create-rigid-box [size position]
  (when (and size position (physics-available?))
    (local half-extents (bt.Vector3 (* 0.5 size.x)
                                        (* 0.5 size.y)
                                        (* 0.5 size.z)))
    (local shape (bt.BoxShape half-extents))
    (local transform (bt.Transform))
    (transform:setIdentity)
    (transform:setOrigin (bt-glm-vec3 position))
    (local motion-state (bt.DefaultMotionState transform))
    (local inertia (bt.Vector3 0 0 0))
    (shape:calculateLocalInertia 1.0 inertia)
    (local info (bt.RigidBodyConstructionInfo 1.0 motion-state shape inertia))
    (local body (bt.RigidBody info))
    (app.engine.physics:addRigidBody body)
    {:shape shape
     :motion-state motion-state
     :body body}))

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

(fn half-size [entry]
  (* entry.size (glm.vec3 0.5 0.5 0.5)))

(fn entity-transform [entity]
  (local layout (and entity entity.layout))
  {:position (or (and layout layout.position) (glm.vec3 0 0 0))
   :rotation (or (and layout layout.rotation) (glm.quat 1 0 0 0))})

(fn apply-layout-to-body [entry]
  (when (and entry.body entry.positioned entry.positioned.layout)
    (local layout entry.positioned.layout)
    (local transform (bt.Transform))
    (transform:setIdentity)
    (transform:setOrigin (bt-glm-vec3 (+ layout.position
                                     (layout.rotation:rotate (half-size entry)))))
    (entry.body:setWorldTransform transform)
    (local motion (and entry.rigid entry.rigid.motion-state))
    (when motion
      (motion:setWorldTransform transform))
    (entry.body:setLinearVelocity (bt.Vector3 0 0 0))))

(fn remove-body [entry]
  (when (and entry.body entry.body-active? (physics-available?))
    (app.engine.physics:removeRigidBody entry.body)
    (set entry.body-active? false)))

(fn add-body [entry]
  (when (and entry.body (not entry.body-active?) (physics-available?))
    (apply-layout-to-body entry)
    (app.engine.physics:addRigidBody entry.body)
    (set entry.body-active? true)))

(fn attach [entity cuboids]
  (local entries (or (and cuboids cuboids.entries) []))
  (local count (length entries))
  (when entity
    (when (> count 0)
      (ensure-physics-configured)
      (local child-count (length entity.children))
      (local start-index (+ 1 (- child-count count)))
      (local base-position (or entity.layout.position (glm.vec3 0 0 0)))
      (local base-rotation (or entity.layout.rotation (glm.quat 1 0 0 0)))
      (each [idx entry (ipairs entries)]
        (local metadata (. entity.children (+ start-index (- idx 1))))
        (when metadata
          (set entry.positioned metadata.element))
        (when (and (not entry.body) (physics-available?))
          (local half-size (* entry.size (glm.vec3 0.5 0.5 0.5)))
          (local local-center (+ entry.spawn half-size))
          (local world-center (+ base-position (base-rotation:rotate local-center)))
          (local rigid (create-rigid-box entry.size world-center))
          (when rigid
            (set entry.body rigid.body)
            (set entry.body-active? true)
            (set entry.rigid rigid))))
      (set entity.physics-cuboids entries)
      (local original-drop entity.drop)
      (set entity.drop
           (fn [self]
             (each [_ entry (ipairs entries)]
               (when entry.body
                 (remove-body entry)
                 (set entry.body nil)
                 (set entry.rigid nil)))
             (when original-drop
               (original-drop self)))))
      (attach-movables entity entries))
  (when (and entity (not entity.physics-cuboids))
    (set entity.physics-cuboids []))
  entity)

(fn create-movable-entry [entity entry]
  (local target (and entry.positioned entry.positioned.layout))
  (when target
    {:target target
     :handle target
     :key entry
     :on-drag-start
     (fn [_entry]
       (set entry.dragging true)
       (remove-body entry))
     :on-drag-end
     (fn [_entry]
       (set entry.dragging false)
       (local base (entity-transform entity))
       (local inverse (base.rotation:inverse))
       (local layout target)
       (local world-center (+ layout.position (layout.rotation:rotate (half-size entry))))
       (local relative (- world-center base.position))
       (local local-relative (inverse:rotate relative))
       (local local-offset (- local-relative (half-size entry)))
       (set entry.offset local-offset)
       (set entry.spawn local-offset)
       (apply-layout-to-body entry)
       (add-body entry))}))

(set attach-movables
     (fn [entity entries]
       (local movable-entries
         (icollect [_ entry (ipairs entries)]
           (create-movable-entry entity entry)))
       (local existing (or entity.movables []))
       (each [_ entry (ipairs movable-entries)]
         (when entry
           (table.insert existing entry)))
       (set entity.movables existing)))

(fn sync [entity]
  (local entries (and entity entity.physics-cuboids))
  (when (and entries (> (length entries) 0))
    (local container-layout entity.layout)
    (when container-layout
      (local base-position (or container-layout.position (glm.vec3 0 0 0)))
      (local base-rotation (or container-layout.rotation (glm.quat 1 0 0 0)))
      (local inverse (base-rotation:inverse))
      (each [_ entry (ipairs entries)]
        (local offset entry.offset)
        (local positioned entry.positioned)
        (when (and offset positioned)
          (local body entry.body)
          (local world-position
            (if entry.dragging
                (+ positioned.layout.position
                   (positioned.layout.rotation:rotate (half-size entry)))
                (if (and body entry.body-active? (physics-available?))
                    (do
                      (local transform (body:getCenterOfMassTransform))
                      (local origin (transform:getOrigin))
                      (physics-glm-vec3 origin))
                    (+ base-position
                       (base-rotation:rotate (+ entry.spawn (half-size entry)))))))
          (when world-position
            (local entry-half (half-size entry))
            (local relative (- world-position base-position))
            (local local-relative (inverse:rotate relative))
            (local local-offset (- local-relative entry-half))
            (set offset.x local-offset.x)
            (set offset.y local-offset.y)
            (set offset.z local-offset.z)
            (positioned.layout:mark-layout-dirty)))))))

{:new-cuboid new-cuboid
 :make make
 :attach attach
 :sync sync}
