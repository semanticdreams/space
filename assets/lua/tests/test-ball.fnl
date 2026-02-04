(local glm (require :glm))
(local Ball (require :ball))
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

(fn ball-syncs-position-from-physics []
  (assert bt "Ball physics test requires Bullet bindings")
  (assert (and app.engine app.engine.physics) "Physics instance not available")
  (app.engine.physics:setGravity 0 -10 0)

  (local builder (Ball {:radius 2
                            :position (glm.vec3 0 10 0)}))
  (local ball (builder (make-test-ctx)))
  (local root (Layout {:name "ball-root"}))

  (ball:ensure-body root)
  (local start-offset-y ball.offset.y)

  (for [i 1 45]
    (app.engine.physics:update 0))
  (ball:sync root)

  (assert (< ball.offset.y start-offset-y)
          "Ball offset did not move downward after physics update")

  (ball:drop))

(table.insert tests {:name "Ball measurer matches default size" :fn ball-measure-matches-radius})
(table.insert tests {:name "Ball sync updates from Bullet body" :fn ball-syncs-position-from-physics})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "ball"
                       :tests tests})))

{:name "ball"
 :tests tests
 :main main}
