(local glm (require :glm))
(local Car (require :car))
(local Positioned (require :positioned))

(local default-car-opts {:body-length 24
                         :body-width 11
                         :body-height 5
                         :wheel-arch-radius 2.1
                         :roof-height 3
                         :hood-angle (math.rad 16)
                         :rear-slope (math.rad 10)
                         :window-height 1.8
                         :chamfer 0.8})

(fn DemoCar [opts]
  (local options (or opts {}))
  (local car-builder (Car (or options.car default-car-opts)))
  (local position (or options.position (glm.vec3 -18 0 12)))
  (local rotation (or options.rotation (glm.quat (math.rad -18) (glm.vec3 0 1 0))))

  (fn build [ctx runtime-opts]
    (local car (car-builder ctx runtime-opts))
    (local size (or options.size (and car car.bounds car.bounds.size)))
    (local positioned
      ((Positioned {:position position
                    :rotation rotation
                    :size size
                    :child (fn [_] car)})
       ctx runtime-opts))
    (set positioned.car car)
    (set positioned.car-offset position)
    (set positioned.car-rotation rotation)
    (set positioned.car-size size)
    (set positioned.__demo_car true)
    positioned)
  build)

DemoCar
