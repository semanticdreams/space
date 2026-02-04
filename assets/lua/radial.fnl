(local glm (require :glm))
(local {: Layout} (require :layout))

(local plane-map
  {:xy {:a 1 :b 2 :normal 3}
   :xz {:a 1 :b 3 :normal 2}
   :yz {:a 2 :b 3 :normal 1}
   "xy" {:a 1 :b 2 :normal 3}
   "xz" {:a 1 :b 3 :normal 2}
   "yz" {:a 2 :b 3 :normal 1}})

(local align-options {:start :start :between :between :end :end
                      "start" :start "between" :between "end" :end})

(local cross-align-options {:start :start :center :center :end :end
                            "start" :start "center" :center "end" :end})

(local orientation-options {:neutral :neutral
                            :forward :forward
                            :backward :backward
                            :outward :outward
                            :inward :inward
                            "neutral" :neutral
                            "forward" :forward
                            "backward" :backward
                            "outward" :outward
                            "inward" :inward})

(fn resolve-plane [value]
  (or (. plane-map value) plane-map.xy))

(fn resolve-main-align [value]
  (or (. align-options value) :between))

(fn resolve-cross-align [value]
  (or (. cross-align-options value) :center))

(fn resolve-orientation [value]
  (or (. orientation-options value) :neutral))

(fn axis-vec [idx]
  (if (= idx 1)
      (glm.vec3 1 0 0)
      (if (= idx 2)
          (glm.vec3 0 1 0)
          (glm.vec3 0 0 1))))

(fn get_comp [v idx]
  (if (= idx 1)
      v.x
      (if (= idx 2)
          v.y
          v.z)))

(fn set_comp [v idx value]
  (if (= idx 1)
      (set v.x value)
      (if (= idx 2)
          (set v.y value)
          (set v.z value))))


(fn Radial [opts]
  (local options (or opts {}))
  (assert options.children "Radial requires :children")

  (fn build [ctx]
    (local entries
      (icollect [_ child-builder (ipairs options.children)]
        {:element (child-builder ctx)}))
    (local plane (resolve-plane options.plane))
    (local align-main (resolve-main-align options.align))
    (local cross-align (resolve-cross-align options.normal-align))
    (local orientation (resolve-orientation options.orientation))
    (local radius (math.max 0 (or options.radius 1)))
    (local start-angle (or options.start-angle 0))

    (fn measurer [self]
      (local max-size (glm.vec3 0 0 0))
      (var max-plane-padding 0)
      (each [_ child (ipairs self.children)]
        (child:measurer)
        (set max-size.x (math.max max-size.x child.measure.x))
        (set max-size.y (math.max max-size.y child.measure.y))
        (set max-size.z (math.max max-size.z child.measure.z))
        (local a (get_comp child.measure plane.a))
        (local b (get_comp child.measure plane.b))
        (local half-diagonal (* 0.5 (math.sqrt (+ (* a a) (* b b)))))
        (set max-plane-padding (math.max max-plane-padding half-diagonal)))
      (local radial-extent (+ radius max-plane-padding))
      (local diameter (* 2 radial-extent))
      (local measure (glm.vec3 diameter diameter diameter))
      (set_comp measure plane.a (math.max diameter (get_comp max-size plane.a)))
      (set_comp measure plane.b (math.max diameter (get_comp max-size plane.b)))
      (set_comp measure plane.normal
                (math.max (get_comp measure plane.normal)
                          (get_comp max-size plane.normal)))
      (set self.measure measure))

    (fn angle-step [count]
      (if (<= count 1)
          0
          (/ (* 2 math.pi) count)))

    (fn make-angle-plan [count]
      (local base-step (if (> count 0) (angle-step count) 0))
      (local span (if (= align-main :between)
                       (* base-step count)
                       base-step))
      (var start start-angle)
      (when (= align-main :end)
        (set start (- start span)))
      {:start start
       :step (if (> count 1)
                  (if (= align-main :between)
                      base-step
                      (if (> span 0) (/ span (- count 1)) 0))
                  0)})

    (fn oriented-rotation [base angle]
      (if (= orientation :neutral)
          base
          (do
            (local normal-axis (base:rotate (axis-vec plane.normal)))
            (local base-angle (- angle)) ; align +Z forward to tangential direction
            (local orient-angle
              (if (= orientation :forward)
                  base-angle
                  (if (= orientation :backward)
                      (+ base-angle math.pi)
                      (if (= orientation :inward)
                          (- base-angle (* 0.5 math.pi))
                          (+ base-angle (* 0.5 math.pi))))))
            (local orient-rot (glm.quat orient-angle normal-axis))
            (* base orient-rot))))

    (fn layouter [self]
      (local child-count (length self.children))
      (local plan (make-angle-plan child-count))
      (local normal-size (get_comp self.size plane.normal))
      (local base-rotation self.rotation)
      (local center self.position)
      (for [i 1 child-count]
        (local child (. self.children i))
        (local angle (+ plan.start (* (- i 1) plan.step)))
        (set child.size child.measure)
        (local radial-dir (glm.vec3 0 0 0))
        (set_comp radial-dir plane.a (math.cos angle))
        (set_comp radial-dir plane.b (math.sin angle))
        (local center-offset (glm.vec3 0 0 0))
        (set_comp center-offset plane.a (* radius (get_comp radial-dir plane.a)))
        (set_comp center-offset plane.b (* radius (get_comp radial-dir plane.b)))
        (local child-normal (get_comp child.size plane.normal))
        (local center-normal
          (if (= cross-align :start)
              (* 0.5 child-normal)
              (if (= cross-align :end)
                  (- normal-size (* 0.5 child-normal))
                  (/ normal-size 2))))
        (set_comp center-offset plane.normal center-normal)
        (local world-center (+ center (base-rotation:rotate center-offset)))
        (local child-rotation (oriented-rotation base-rotation angle))
        (set child.rotation child-rotation)
        (local half-size (glm.vec3 (* 0.5 child.size.x)
                               (* 0.5 child.size.y)
                               (* 0.5 child.size.z)))
        (local origin-offset (child-rotation:rotate half-size))
        (set child.position (- world-center origin-offset))
        (set child.depth-offset-index self.depth-offset-index)
        (set child.clip-region self.clip-region)
        (child:layouter)))

    (local layout
      (Layout {:name (or options.name "radial")
               :children (icollect [_ entry (ipairs entries)]
                                   entry.element.layout)
               :measurer measurer
               :layouter layouter}))

    (local widget {:layout layout
                   :children entries})

    (fn drop [_self]
      (layout:drop)
      (each [_ entry (ipairs entries)]
        (entry.element:drop)))

    (set widget.drop drop)
    widget))

Radial
