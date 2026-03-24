(local bt (require :bt))

(local default-floor-y -100.0)

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn available? []
  (and bt app.engine app.engine.physics))

(fn resolve-floor-y [opts]
  (local options (or opts {}))
  (local configured (or options.floor-y app.physics-floor-y default-floor-y))
  (if (finite-number? configured)
      configured
      default-floor-y))

(fn ensure-installed [opts]
  (when (available?)
    (local floor-y (resolve-floor-y opts))
    (local existing app.__physics-global-floor)
    (local physics app.engine.physics)
    (local already-installed?
      (and existing
           existing.body
           existing.physics
           (= existing.physics physics)
           (= existing.y floor-y)))
    (when (not already-installed?)
      (when (and existing existing.body existing.physics)
        (pcall (fn []
                 (existing.physics:removeRigidBody existing.body))))
      (local shape (bt.StaticPlaneShape (bt.Vector3 0 1 0) floor-y))
      (local transform (bt.Transform))
      (transform:setIdentity)
      (local motion-state (bt.DefaultMotionState transform))
      (local inertia (bt.Vector3 0 0 0))
      (local info (bt.RigidBodyConstructionInfo 0 motion-state shape inertia))
      (local body (bt.RigidBody info))
      (physics:addRigidBody body)
      (set app.__physics-global-floor
           {:y floor-y
            :shape shape
            :motion-state motion-state
            :body body
            :physics physics}))))

{:default-floor-y default-floor-y
 :available? available?
 :resolve-floor-y resolve-floor-y
 :ensure-installed ensure-installed}
