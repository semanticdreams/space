(local glm (require :glm))
(local _ (require :main))
(local MathUtils (require :math-utils))

(local tests [])

(local approx (. MathUtils :approx))

(fn screen-ray-with-identity-matrices []
  (local original-viewport app.viewport)
  (local original-projection app.projection)
  (app.set-viewport {:x 0 :y 0 :width 1 :height 1})
  (local projection (glm.mat4 1))
  (set app.projection projection)
  (local view (glm.mat4 1))
  (local ray (app.screen-pos-ray {:x 0.5 :y 0.5}
                                    {:view view :viewport {:x 0 :y 0 :width 1 :height 1}}))
  (local origin ray.origin)
  (local direction ray.direction)
  (assert (approx origin.x 0))
  (assert (approx origin.y 0))
  (assert (approx origin.z -1))
  (assert (approx direction.x 0))
  (assert (approx direction.y 0))
  (assert (approx direction.z 1))
  (app.set-viewport original-viewport)
  (set app.projection original-projection))

(table.insert tests {:name "screen_pos_ray unprojects using provided matrices" :fn screen-ray-with-identity-matrices})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "screen-pos-ray"
                       :tests tests})))

{:name "screen-pos-ray"
 :tests tests
 :main main}
