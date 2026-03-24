(local glm (require :glm))
(local Ball (require :ball))
(local Sphere (require :sphere))
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
  {:triangle-vector (make-vector-buffer)})

(local approx (. MathUtils :approx))

(fn vec-approx= [a b]
  (and a b
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn ball-measure-matches-radius []
  (local builder (Ball {:radius 3
                        :position (glm.vec3 1 2 3)}))
  (local ball (builder (make-test-ctx)))

  (ball.layout:measurer)

  (assert (vec-approx= ball.layout.measure (glm.vec3 6 6 6)))

  (ball:drop))

(fn ball-accepts-custom-visual-builder []
  (local builder
    (Ball {:radius 3
           :position (glm.vec3 1 2 3)
           :visual (Sphere {:color (glm.vec4 1 0 0 1)
                            :size (glm.vec3 6 6 6)})}))
  (local ball (builder (make-test-ctx)))

  (ball.layout:measurer)

  (assert (vec-approx= ball.layout.measure (glm.vec3 6 6 6)))

  (ball:drop))

(fn ball-syncs-position-from-physics []
  (assert bt "Ball physics test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (app.engine.physics:setGravity 0 -10 0)

  (local builder (Ball {:radius 2
                            :position (glm.vec3 0 10 0)}))
  (local ball (builder (make-test-ctx)))
  (local root (Layout {:name "ball-root"}))

  (ball:ensure-body root)
  (local start-layout-y (or (and ball.layout ball.layout.position ball.layout.position.y) 0))

  (for [i 1 45]
    (app.engine.physics:update 0))
  (ball:sync root)

  (assert (< ball.layout.position.y start-layout-y)
          "Ball layout position did not move downward after physics update")

  (ball:drop))

(fn ball-syncs-rotation-from-physics []
  (assert bt "Ball physics test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")

  (local builder (Ball {:radius 2
                        :position (glm.vec3 0 10 0)}))
  (local ball (builder (make-test-ctx)))
  (local root (Layout {:name "ball-rotation-root"}))
  (local target-rotation (glm.quat (* 0.5 math.pi) (glm.vec3 0 1 0)))

  (ball:ensure-body root)

  (local transform (bt.Transform))
  (transform:setIdentity)
  (transform:setOrigin (bt.Vector3 0 10 0))
  (transform:setRotation (bt.Quaternion target-rotation.x
                                        target-rotation.y
                                        target-rotation.z
                                        target-rotation.w))
  (ball.body:setWorldTransform transform)
  (when ball.motion-state
    (ball.motion-state:setWorldTransform transform))

  (ball:sync root)

  (assert (approx ball.layout.rotation.w target-rotation.w)
          "Ball layout rotation w did not sync from Bullet body")
  (assert (approx ball.layout.rotation.x target-rotation.x)
          "Ball layout rotation x did not sync from Bullet body")
  (assert (approx ball.layout.rotation.y target-rotation.y)
          "Ball layout rotation y did not sync from Bullet body")
  (assert (approx ball.layout.rotation.z target-rotation.z)
          "Ball layout rotation z did not sync from Bullet body")

  (ball:drop))

(table.insert tests {:name "Ball measurer matches default size" :fn ball-measure-matches-radius})
(table.insert tests {:name "Ball accepts custom visual builder" :fn ball-accepts-custom-visual-builder})
(table.insert tests {:name "Ball sync updates from Bullet body" :fn ball-syncs-position-from-physics})
(table.insert tests {:name "Ball sync updates rotation from Bullet body" :fn ball-syncs-rotation-from-physics})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "ball"
                       :tests tests})))

{:name "ball"
 :tests tests
 :main main}
