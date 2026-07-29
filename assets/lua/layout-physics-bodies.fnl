(local glm (require :glm))
(local bt (require :bt))
(local CoordinateGuard (require :coordinate-guard))
(local logging (require :logging))

(local safe-vec3? CoordinateGuard.safe-vec3?)

(fn physics-available? []
  (and bt app.engine app.engine.physics))

(fn sync-moved-body [body]
  (when (and body (physics-available?) app.engine.physics.syncMovedRigidBody)
    (app.engine.physics:syncMovedRigidBody body)))

(fn bt-glm-vec3 [value]
  (bt.Vector3 (or value.x 0) (or value.y 0) (or value.z 0)))

(fn physics-glm-vec3 [value]
  (glm.vec3 (or value.x 0) (or value.y 0) (or value.z 0)))

(fn glm-bt-quat [value]
  (bt.Quaternion (or value.x 0) (or value.y 0) (or value.z 0) (or value.w 1)))

(fn bt-quat->glm-quat [rotation]
  (local w (and rotation (rotation:w)))
  (local x (and rotation (rotation:x)))
  (local y (and rotation (rotation:y)))
  (local z (and rotation (rotation:z)))
  (if (and w x y z)
      (glm.quat w x y z)
      (glm.quat 1 0 0 0)))

(fn clamp-size [size]
  (glm.vec3 (math.max (or size.x 0) 0.05)
            (math.max (or size.y 0) 0.05)
            (math.max (or size.z 0) 0.05)))

(fn resolve-layout-size [layout fallback]
  (if layout
      (clamp-size (or layout.size layout.measure fallback (glm.vec3 1 1 1)))
      (clamp-size (or fallback (glm.vec3 1 1 1)))))

(fn get-entries [entity]
  (or (and entity entity.physics-bodies) []))

(fn set-entries! [entity entries]
  (when entity
    (set entity.physics-bodies entries)))

(var attach-movables nil)

(fn apply-body-options! [body options]
  (local resolved (or options {}))
  (when resolved.friction
    (body:setFriction resolved.friction))
  (when resolved.rolling-friction
    (body:setRollingFriction resolved.rolling-friction))
  (when resolved.spinning-friction
    (body:setSpinningFriction resolved.spinning-friction))
  (when (or resolved.linear-damping resolved.angular-damping)
    (body:setDamping (or resolved.linear-damping 0)
                     (or resolved.angular-damping 0))))

(fn create-rigid-box [size position rotation options]
  (when (and size position (physics-available?))
    (local half-extents (bt.Vector3 (* 0.5 size.x)
                                    (* 0.5 size.y)
                                    (* 0.5 size.z)))
    (local shape (bt.BoxShape half-extents))
    (local transform (bt.Transform))
    (transform:setIdentity)
    (transform:setOrigin (bt-glm-vec3 position))
    (when rotation
      (transform:setRotation (glm-bt-quat rotation)))
    (local motion-state (bt.DefaultMotionState transform))
    (local inertia (bt.Vector3 0 0 0))
    (shape:calculateLocalInertia 1.0 inertia)
    (local info (bt.RigidBodyConstructionInfo 1.0 motion-state shape inertia))
    (local body (bt.RigidBody info))
    (apply-body-options! body options)
    (app.engine.physics:addRigidBody body)
    {:shape shape
     :motion-state motion-state
     :body body}))

(fn half-size [entry]
  (* entry.size (glm.vec3 0.5 0.5 0.5)))

(fn entity-transform [entity]
  (local layout (and entity entity.layout))
  {:position (or (and layout layout.position) (glm.vec3 0 0 0))
   :rotation (or (and layout layout.rotation) (glm.quat 1 0 0 0))})

(fn vec3-changed? [a b eps]
  (local e (or eps 1e-4))
  (or (> (math.abs (- a.x b.x)) e)
      (> (math.abs (- a.y b.y)) e)
      (> (math.abs (- a.z b.z)) e)))

(fn quat-changed? [a b eps]
  (local e (or eps 1e-4))
  (or (> (math.abs (- a.w b.w)) e)
      (> (math.abs (- a.x b.x)) e)
      (> (math.abs (- a.y b.y)) e)
      (> (math.abs (- a.z b.z)) e)))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn safe-quat? [value]
  (and value
       (finite-number? value.w)
       (finite-number? value.x)
       (finite-number? value.y)
       (finite-number? value.z)))

(fn sanitize-rotation [candidate fallback]
  (if (safe-quat? candidate)
      candidate
      (if (safe-quat? fallback)
          fallback
          (glm.quat 1 0 0 0))))

(fn recover-entry-transform! [entry body base-position base-rotation positioned offset]
  (local entry-half (half-size entry))
  (local safe-base-rotation (sanitize-rotation base-rotation (glm.quat 1 0 0 0)))
  (local safe-entry-spawn
    (if (safe-vec3? entry.spawn)
        entry.spawn
        (glm.vec3 0 0 0)))
  (local fallback-center
    (+ base-position
       (safe-base-rotation:rotate (+ safe-entry-spawn entry-half))))
  (local fallback-rotation
    (sanitize-rotation positioned.layout.rotation safe-base-rotation))
  (local fallback-position
    (- fallback-center (fallback-rotation:rotate entry-half)))
  (set offset.x safe-entry-spawn.x)
  (set offset.y safe-entry-spawn.y)
  (set offset.z safe-entry-spawn.z)
  (when entry.metadata
    (set entry.metadata.transform-applied? true)
    (set entry.metadata.physics-transform-recovered? true))
  (set positioned.layout.rotation fallback-rotation)
  (set positioned.layout.position fallback-position)
  (positioned.layout:mark-layout-dirty)
  (when body
    (local reset-transform (bt.Transform))
    (reset-transform:setIdentity)
    (reset-transform:setOrigin (bt-glm-vec3 fallback-center))
    (reset-transform:setRotation (glm-bt-quat fallback-rotation))
    (body:setWorldTransform reset-transform)
    (when (and entry.rigid entry.rigid.motion-state)
      (entry.rigid.motion-state:setWorldTransform reset-transform))
    (body:setLinearVelocity (bt.Vector3 0 0 0))
    (when body.setAngularVelocity
      (body:setAngularVelocity (bt.Vector3 0 0 0)))
    (when body.forceActivationState
      (body:forceActivationState 1))
    (when body.activate
      (body:activate true))))

(fn remove-body [entry]
  (when (and entry.body entry.body-active? (physics-available?))
    (app.engine.physics:removeRigidBody entry.body)
    (set entry.body-active? false)))

(fn apply-layout-to-body [entry]
  (when (and entry.body entry.positioned entry.positioned.layout)
    (local layout entry.positioned.layout)
    (local half (half-size entry))
    (local transform (bt.Transform))
    (transform:setIdentity)
    (transform:setOrigin (bt-glm-vec3 (+ layout.position
                                       (layout.rotation:rotate half))))
    (transform:setRotation (glm-bt-quat layout.rotation))
    (entry.body:setWorldTransform transform)
    (local motion (and entry.rigid entry.rigid.motion-state))
    (when motion
      (motion:setWorldTransform transform))
    (entry.body:setLinearVelocity (bt.Vector3 0 0 0))))

(fn local-offset-from-layout [entity entry]
  (local base (entity-transform entity))
  (local inverse (base.rotation:inverse))
  (local layout (and entry.positioned entry.positioned.layout))
  (if layout
      (do
        (local world-center (+ layout.position
                               (layout.rotation:rotate (half-size entry))))
        (local relative (- world-center base.position))
        (local local-relative (inverse:rotate relative))
        (- local-relative (half-size entry)))
      entry.spawn))

(fn copy-vec3-into! [dst src]
  (when (and dst src)
    (set dst.x src.x)
    (set dst.y src.y)
    (set dst.z src.z))
  dst)

(fn world-state-from-layout [entry]
  (local layout (and entry.positioned entry.positioned.layout))
  (if layout
      {:position (+ layout.position (layout.rotation:rotate (half-size entry)))
       :rotation (or layout.rotation (glm.quat 1 0 0 0))}
      {:position (glm.vec3 0 0 0)
       :rotation (glm.quat 1 0 0 0)}))

(fn rebuild-body-for-size [entry next-size]
  (local size (clamp-size next-size))
  (local world-state
    (if (and entry.body entry.body-active? (physics-available?))
        (do
          (local transform (entry.body:getCenterOfMassTransform))
          (local origin (transform:getOrigin))
          (local rotation (transform:getRotation))
          {:position (physics-glm-vec3 origin)
           :rotation (bt-quat->glm-quat rotation)})
        (world-state-from-layout entry)))
  (local should-remain-active? entry.body-active?)
  (when entry.body
    (remove-body entry)
    (set entry.body nil)
    (set entry.rigid nil)
    (set entry.body-active? false))
  (set entry.size size)
  (when (physics-available?)
    (local rigid (create-rigid-box size world-state.position world-state.rotation entry.body-options))
    (when rigid
      (set entry.body rigid.body)
      (set entry.rigid rigid)
      (set entry.body-active? true)
      (if should-remain-active?
          (do
            (when entry.body.forceActivationState
              (entry.body:forceActivationState 1))
            (when entry.body.activate
              (entry.body:activate true)))
          (remove-body entry)))))

(fn ensure-body-matches-layout-size [entry]
  (local layout (and entry.positioned entry.positioned.layout))
  (when layout
    (local size (resolve-layout-size layout entry.size))
    (when (or (not entry.body)
              (vec3-changed? size entry.size 1e-3))
      (rebuild-body-for-size entry size))))

(fn add-body [entry]
  (when (and entry.body (not entry.body-active?) (physics-available?))
    (apply-layout-to-body entry)
    (app.engine.physics:addRigidBody entry.body)
    (when (and entry.body entry.body.forceActivationState)
      (entry.body:forceActivationState 1))
    (when (and entry.body entry.body.activate)
      (entry.body:activate true))
    (entry.body:setLinearVelocity (bt.Vector3 0 -0.01 0))
    (entry.body:applyForce (bt.Vector3 0 -0.5 0))
    (set entry.body-active? true)))

(fn activate-entry-body! [entry]
  (when (and entry.body entry.body.forceActivationState)
    (entry.body:forceActivationState 1))
  (when (and entry.body entry.body.activate)
    (entry.body:activate true)))

(fn update-entry-offset-from-world-center! [entry base-position inverse world-center]
  (local relative (- world-center base-position))
  (local local-relative (inverse:rotate relative))
  (local local-offset (- local-relative (half-size entry)))
  (if entry.offset
      (copy-vec3-into! entry.offset local-offset)
      (set entry.offset (glm.vec3 local-offset.x local-offset.y local-offset.z)))
  (if entry.spawn
      (copy-vec3-into! entry.spawn local-offset)
      (set entry.spawn (glm.vec3 local-offset.x local-offset.y local-offset.z))))

(fn resolve-entry-world-state [entry base-position base-rotation positioned]
  (local body entry.body)
  (local transform
    (if (and body entry.body-active? (physics-available?))
        (body:getCenterOfMassTransform)
        nil))
  {:body body
   :world-position
   (if entry.dragging
       (if (= (drag-attachment-mode) :anchor)
           (if transform
               (do
                 (local origin (transform:getOrigin))
                 (physics-glm-vec3 origin))
               (+ positioned.layout.position
                  (positioned.layout.rotation:rotate (half-size entry))))
           (do
             (apply-layout-to-body entry)
             (+ positioned.layout.position
                (positioned.layout.rotation:rotate (half-size entry)))))
       (if transform
           (do
             (local origin (transform:getOrigin))
             (physics-glm-vec3 origin))
           (+ base-position
              (base-rotation:rotate (+ entry.spawn (half-size entry))))))
   :world-rotation
   (if transform
       (do
         (local rotation (transform:getRotation))
         (bt-quat->glm-quat rotation))
       (or positioned.layout.rotation (glm.quat 1 0 0 0)))})

(fn apply-entry-world-state! [entry positioned offset base-position base-rotation inverse body world-position world-rotation]
  (if (or (not (safe-vec3? world-position))
          (not (safe-quat? world-rotation)))
      (do
        (logging.error "[physics-bodies] invalid physics transform; recovered entry to safe spawn")
        (recover-entry-transform! entry body base-position base-rotation positioned offset))
      (when world-position
        (local entry-half (half-size entry))
        (local relative (- world-position base-position))
        (local local-relative (inverse:rotate relative))
        (local local-offset (- local-relative entry-half))
        (local layout-position (- world-position (world-rotation:rotate entry-half)))
        (if (or (not (safe-vec3? local-offset))
                (not (safe-vec3? layout-position)))
            (do
              (logging.error "[physics-bodies] unsafe derived layout transform; recovered entry to safe spawn")
              (recover-entry-transform! entry body base-position base-rotation positioned offset))
            (when (or (vec3-changed? offset local-offset 1e-3)
                      (vec3-changed? positioned.layout.position layout-position 1e-3)
                      (quat-changed? positioned.layout.rotation world-rotation 1e-3))
              (set offset.x local-offset.x)
              (set offset.y local-offset.y)
              (set offset.z local-offset.z)
              (when entry.metadata
                (set entry.metadata.transform-applied? true))
              (set positioned.layout.rotation world-rotation)
              (set positioned.layout.position layout-position)
              (positioned.layout:mark-layout-dirty))))))

(fn sync-entry [entry base-position base-rotation inverse]
  (local offset entry.offset)
  (local positioned entry.positioned)
  (when (and offset positioned positioned.layout)
    (ensure-body-matches-layout-size entry)
    (when (and (not entry.dragging)
               entry.body
               (not entry.body-active?)
               (physics-available?))
      (add-body entry))
    (local world-state
      (resolve-entry-world-state entry base-position base-rotation positioned))
    (apply-entry-world-state! entry
                              positioned
                              offset
                              base-position
                              base-rotation
                              inverse
                              world-state.body
                              world-state.world-position
                              world-state.world-rotation)))

(fn attach [entity entries-spec]
  (local entries (or (and entries-spec entries-spec.entries) []))
  (local count (length entries))
  (when entity
    (when (> count 0)
      (local child-count (length entity.children))
      (local start-index (+ 1 (- child-count count)))
      (local base-position (or entity.layout.position (glm.vec3 0 0 0)))
      (local base-rotation (or entity.layout.rotation (glm.quat 1 0 0 0)))
      (each [idx entry (ipairs entries)]
        (local metadata (. entity.children (+ start-index (- idx 1))))
        (when metadata
          (set entry.positioned metadata.element))
        (when entry.positioned
          (set entry.size (resolve-layout-size entry.positioned.layout entry.size)))
        (when (and (not entry.body) (physics-available?))
          (local center (+ entry.spawn (half-size entry)))
          (local world-center (+ base-position (base-rotation:rotate center)))
          (local rigid (create-rigid-box entry.size
                                         world-center
                                         entry.positioned.layout.rotation
                                         entry.body-options))
          (when rigid
            (set entry.body rigid.body)
            (set entry.body-active? true)
            (set entry.rigid rigid))))
      (set-entries! entity entries)
      (local original-drop entity.drop)
      (set entity.drop
           (fn [self]
             (each [_ entry (ipairs entries)]
               (when entry.body
                 (remove-body entry)
                 (set entry.body nil)
                 (set entry.rigid nil)))
             (when original-drop
               (original-drop self))))
      (attach-movables entity entries))
    (when (not entity.physics-bodies)
      (set-entries! entity [])))
  entity)

(fn ensure-runtime-state [entity]
  (when (and entity (not entity.physics-bodies))
    (set-entries! entity []))
  (when (and entity (not entity.__physics-bodies-drop-wrapped))
    (local original-drop entity.drop)
    (set entity.drop
         (fn [self]
           (each [_ entry (ipairs (get-entries self))]
             (when entry.body
               (remove-body entry)
               (set entry.body nil)
               (set entry.rigid nil)
               (set entry.body-active? false)))
           (when original-drop
             (original-drop self))))
    (set entity.__physics-bodies-drop-wrapped true)))

(fn add-runtime-layout-body [entity opts]
  (local options (or opts {}))
  (local element (assert options.element "LayoutPhysicsBodies.add-runtime-layout-body requires :element"))
  (local layout (and element element.layout))
  (local size (resolve-layout-size layout options.size))
  (var metadata options.metadata)
  (when (not metadata)
    (each [_ child-metadata (ipairs (or entity.children []))]
      (when (and (not metadata)
                 child-metadata
                 (= child-metadata.element element))
        (set metadata child-metadata))))
  (local metadata-position (or (and metadata metadata.position) (glm.vec3 0 0 0)))
  (local entry {:spawn (glm.vec3 0 0 0)
                :size size
                :offset metadata-position
                :body-options (or options.body-options {})
                :positioned element
                :metadata metadata
                :body nil
                :body-active? false
                :dragging false
                :rigid nil})
  (ensure-runtime-state entity)
  (set entry.spawn (local-offset-from-layout entity entry))
  (set entry.offset.x entry.spawn.x)
  (set entry.offset.y entry.spawn.y)
  (set entry.offset.z entry.spawn.z)
  (ensure-body-matches-layout-size entry)
  (local entries (get-entries entity))
  (table.insert entries entry)
  (set-entries! entity entries)
  entry)

(fn remove-runtime-layout-body-for-element [entity element]
  (local entries (get-entries entity))
  (when entries
    (var remove-idx nil)
    (each [idx entry (ipairs entries)]
      (when (and (not remove-idx)
                 (= entry.positioned element))
        (set remove-idx idx)))
    (when remove-idx
      (local entry (. entries remove-idx))
      (when entry
        (remove-body entry)
        (set entry.body nil)
        (set entry.rigid nil)
        (set entry.body-active? false))
      (table.remove entries remove-idx)
      entry)))

(fn drag-attachment-mode []
  (if (and app.activity-drag-attachment-provider
           (= (app.activity-drag-attachment-provider) :anchor))
      :anchor
      :center))

(fn compute-body-center [entry]
  (if (and entry.body entry.body.getCenterOfMassTransform)
      (let [transform (entry.body:getCenterOfMassTransform)
            origin (transform:getOrigin)]
        (glm.vec3 (or origin.x 0) (or origin.y 0) (or origin.z 0)))
      (let [layout (and entry.positioned entry.positioned.layout)]
        (if layout
            (+ layout.position
               (layout.rotation:rotate (half-size entry)))
            (glm.vec3 0 0 0)))))

(fn apply-anchor-force! [entry relative-anchor desired-world-position]
  (local spring-strength 35.0)
  (local body entry.body)
  (local body-center (compute-body-center entry))
  (local current-anchor-world
    (+ body-center relative-anchor))
  (local spring-force
    (* (- desired-world-position current-anchor-world)
       (glm.vec3 spring-strength spring-strength spring-strength)))
  ;; Apply velocity damping if getVelocityInLocalPoint is available
  (local damped-force
    (if body.getVelocityInLocalPoint
        (let [velocity (body:getVelocityInLocalPoint (bt-glm-vec3 relative-anchor))]
          (- spring-force (* (physics-glm-vec3 velocity) (glm.vec3 4.0 4.0 4.0))))
        spring-force))
  (body:applyForceAtPosition (bt-glm-vec3 damped-force)
                              (bt-glm-vec3 relative-anchor))
  ;; Activate the body
  (when body.activate
    (body:activate true)))

(fn create-movable-entry [entity entry]
  (local target (and entry.positioned entry.positioned.layout))
  (when target
    {:target target
     :handle target
     :key entry
     :owner entry.positioned
     :on-drag-start
      (fn [_movable drag _payload]
        (set entry.dragging true)
        (ensure-body-matches-layout-size entry)
        (when (= (drag-attachment-mode) :anchor)
          (set drag.relative-anchor
               (- drag.hit-point (compute-body-center entry)))))
     :on-drag-update
     (fn [movable drag update]
       (local mode (drag-attachment-mode))
       (if (= mode :anchor)
           (do
             (assert entry.body "Anchor drag requires a physics body on the entry")
             (assert entry.body.applyForceAtPosition
                     "Anchor drag requires body:applyForceAtPosition binding")
             (local body-center (compute-body-center entry))
             (when (not drag.relative-anchor)
               (set drag.relative-anchor
                    (- drag.hit-point body-center)))
             (apply-anchor-force! entry drag.relative-anchor update.new-position)
             true)
           false))
     :on-drag-end
      (fn [_movable]
        (set entry.dragging false)
        (local base (entity-transform entity))
        (local inverse (base.rotation:inverse))
        (local mode (drag-attachment-mode))
        (if (= mode :anchor)
            (let [body-center (compute-body-center entry)
                  entry-half (half-size entry)
                  layout-rotation (or target.rotation (glm.quat 1 0 0 0))
                  layout-position (- body-center (layout-rotation:rotate entry-half))]
              (set target.position layout-position)
              (update-entry-offset-from-world-center! entry base.position inverse body-center)
              (when (and entry.positioned entry.positioned.layout)
                (entry.positioned.layout:mark-layout-dirty))
              (ensure-body-matches-layout-size entry)
              (apply-layout-to-body entry)
              (activate-entry-body! entry)
              (when entry.body
                (sync-moved-body entry.body)
                (entry.body:applyForce (bt.Vector3 0 -0.5 0))))
            (do
              (local world-center (+ target.position (target.rotation:rotate (half-size entry))))
              (update-entry-offset-from-world-center! entry base.position inverse world-center)
              (when (and entry.positioned entry.positioned.layout)
                (entry.positioned.layout:mark-layout-dirty))
              (ensure-body-matches-layout-size entry)
              (apply-layout-to-body entry)
              (activate-entry-body! entry)
              (when entry.body
                (sync-moved-body entry.body)
                (entry.body:applyForce (bt.Vector3 0 -0.5 0))))))
     }))

(fn collect-movables [entity]
  (var entries [])
  (each [_ entry (ipairs (get-entries entity))]
    (local movable-entry (create-movable-entry entity entry))
    (when movable-entry
      (table.insert entries movable-entry)))
  entries)

(fn reposition-element [entity element next-layout-position next-layout-rotation]
  (local entries (get-entries entity))
  (var matched-entry nil)
  (each [_ entry (ipairs entries)]
    (when (and (not matched-entry)
               (= entry.positioned element))
      (set matched-entry entry)))
  (if (not matched-entry)
      false
      (do
        (local layout (and element element.layout))
        (assert layout "LayoutPhysicsBodies.reposition-element requires element layout")
        (local rotation (or next-layout-rotation layout.rotation (glm.quat 1 0 0 0)))
        (set layout.position next-layout-position)
        (set layout.rotation rotation)
        (layout:mark-layout-dirty)
        (local base (entity-transform entity))
        (local inverse (base.rotation:inverse))
        (local world-center (+ layout.position (layout.rotation:rotate (half-size matched-entry))))
        (update-entry-offset-from-world-center! matched-entry base.position inverse world-center)
        (ensure-body-matches-layout-size matched-entry)
        (apply-layout-to-body matched-entry)
        (activate-entry-body! matched-entry)
        (when matched-entry.body
          (sync-moved-body matched-entry.body))
        true)))

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

(fn deactivate [entity]
  (local entries (get-entries entity))
  (each [_ entry (ipairs entries)]
    (when (and entry.body entry.body-active? (physics-available?))
      (remove-body entry)))
  true)

(fn activate [entity]
  (local entries (get-entries entity))
  (each [_ entry (ipairs entries)]
    (ensure-body-matches-layout-size entry)
    (when (and entry.body (not entry.body-active?) (physics-available?))
      (add-body entry)))
  true)

(fn sync [entity]
  (local entries (get-entries entity))
  (when (and entries (> (length entries) 0))
    (local container-layout entity.layout)
    (when container-layout
      (local base-position (or container-layout.position (glm.vec3 0 0 0)))
      (local base-rotation (or container-layout.rotation (glm.quat 1 0 0 0)))
      (local inverse (base-rotation:inverse))
      (each [_ entry (ipairs entries)]
        (sync-entry entry base-position base-rotation inverse)))
  nil))

{:attach attach
 :add-runtime-layout-body add-runtime-layout-body
 :remove-runtime-layout-body-for-element remove-runtime-layout-body-for-element
 :reposition-element reposition-element
 :collect-movables collect-movables
 :deactivate deactivate
 :activate activate
 :sync sync}
