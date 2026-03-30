(local glm (require :glm))
(local LightBall (require :light-ball))
(local {: Layout} (require :layout))
(local bt (require :bt))
(local MathUtils (require :math-utils))

(local tests [])

(fn make-vector-buffer []
  (local buffer {})
  (set buffer.allocate (fn [_self _count] 1))
  (set buffer.delete (fn [_self _handle] nil))
  (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
  (set buffer.set-float (fn [_self _handle _offset _value] nil))
  buffer)

(fn make-test-ctx []
  (local instanced-batches [])
  {:triangle-vector (make-vector-buffer)
   :instanced-color-mesh-batches instanced-batches
   :register-instanced-color-mesh-batch (fn [_self batch]
                                          (table.insert instanced-batches batch)
                                          batch)
   :unregister-instanced-color-mesh-batch (fn [_self batch]
                                            (for [idx 1 (length instanced-batches)]
                                              (when (= (. instanced-batches idx) batch)
                                                (table.remove instanced-batches idx)
                                                (lua "break")))
                                            nil)})

(local approx (. MathUtils :approx))

(fn vec-approx= [a b]
  (and a b
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn light-ball-default-physics-is-floaty []
  (local builder
    (LightBall {:radius 5
                :position (glm.vec3 1 2 3)}))
  (local light-ball (builder (make-test-ctx)))

  (assert (approx light-ball.restitution 0.82)
          "Light ball default restitution should be floatier")
  (assert (approx light-ball.linear-damping 0.08)
          "Light ball default linear damping should be set")
  (assert (approx light-ball.angular-damping 0.16)
          "Light ball default angular damping should be set")
  (assert (vec-approx= light-ball.gravity (bt.Vector3 0 -4.5 0))
          "Light ball default gravity should be reduced")
  (assert (= light-ball.body-flags bt.BT_DISABLE_WORLD_GRAVITY)
          "Light ball default body flags should disable world gravity")

  (light-ball:drop))

(fn light-ball-default-physics-reaches-bullet-body []
  (assert bt "LightBall physics test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")

  (local builder
    (LightBall {:radius 5
                :position (glm.vec3 0 12 0)}))
  (local light-ball (builder (make-test-ctx)))
  (local root (Layout {:name "light-ball-root"}))

  (light-ball:ensure-body root)

  (assert (approx (light-ball.body:getRestitution) 0.82)
          "Light ball body should inherit default restitution")
  (assert (approx (light-ball.body:getLinearDamping) 0.08)
          "Light ball body should inherit default linear damping")
  (assert (approx (light-ball.body:getAngularDamping) 0.16)
          "Light ball body should inherit default angular damping")
  (assert (vec-approx= (light-ball.body:getGravity) (bt.Vector3 0 -4.5 0))
          "Light ball body should inherit reduced gravity")
  (assert (= (light-ball.body:getFlags) bt.BT_DISABLE_WORLD_GRAVITY)
          "Light ball body should disable world gravity for custom gravity")

  (light-ball:drop))

(table.insert tests {:name "Light ball defaults use floaty physics"
                     :fn light-ball-default-physics-is-floaty})
(table.insert tests {:name "Light ball body inherits floaty default physics"
                     :fn light-ball-default-physics-reaches-bullet-body})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "light-ball"
                       :tests tests})))

{:name "light-ball"
 :tests tests
 :main main}
