(local glm (require :glm))
(local Cuboid (require :cuboid))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))

(local tests [])

(local approx (. MathUtils :approx))

(fn vec-approx= [a b]
  (and (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn quat-approx= [a b]
  (and (approx a.w b.w)
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)))

(fn make-face [measure]
  (local state {:measure-calls 0
                :layout-calls 0
                :last-size nil
                :last-position nil
                :last-rotation nil})
  (local builder
    (fn [_ctx]
      (local layout
        (Layout {:name "cuboid-test-face"
                 :measurer (fn [self]
                             (set state.measure-calls (+ state.measure-calls 1))
                             (set self.measure measure))
                 :layouter (fn [self]
                             (set state.layout-calls (+ state.layout-calls 1))
                             (set state.last-size self.size)
                             (set state.last-position self.position)
                             (set state.last-rotation self.rotation))}))
      (local child {:layout layout})
      (set child.drop (fn [_]))
      child))
  {:builder builder :state state :measure measure})

(fn cuboid-measurer-computes-bounds []
  (local faces
    [(make-face (glm.vec3 8 9 0))
     (make-face (glm.vec3 10 7 0))
     (make-face (glm.vec3 12 11 0))
     (make-face (glm.vec3 9 5 0))
     (make-face (glm.vec3 6 3 0))
     (make-face (glm.vec3 4 2 0))])
  (local cuboid
    ((Cuboid {:children (icollect [_ face (ipairs faces)]
                                  face.builder)}) {}))

  (cuboid.layout:measurer)

  (assert (vec-approx= cuboid.layout.measure (glm.vec3 10 11 12)))

  (cuboid:drop))

(table.insert tests {:name "Cuboid measurer computes envelope" :fn cuboid-measurer-computes-bounds})

(local expected-face-rotations
  [(glm.quat 1 0 0 0)
   (glm.quat math.pi (glm.vec3 0 1 0))
   (glm.quat (* 0.5 math.pi) (glm.vec3 0 1 0))
   (glm.quat (* 1.5 math.pi) (glm.vec3 0 1 0))
   (glm.quat (* 1.5 math.pi) (glm.vec3 1 0 0))
   (glm.quat (* 0.5 math.pi) (glm.vec3 1 0 0))])

(local expected-offsets
  [(fn [size] (glm.vec3 0 0 size.z))
   (fn [size] (glm.vec3 size.x 0 0))
   (fn [size] (glm.vec3 size.x 0 size.z))
   (fn [_] (glm.vec3 0 0 0))
   (fn [size] (glm.vec3 0 size.y size.z))
   (fn [_] (glm.vec3 0 0 0))])

(local expected-axis-orders
  [[1 2 3] [1 2 3] [3 2 1] [3 2 1] [1 3 2] [1 3 2]])

(fn cuboid-layouter-positions-faces []
  (local faces
    (icollect [_ _ (ipairs expected-face-rotations)]
      (make-face (glm.vec3 1 1 1))))
  (local cuboid
    ((Cuboid {:children (icollect [_ face (ipairs faces)]
                                  face.builder)}) {}))
  (cuboid.layout:measurer)

  (local parent-size (glm.vec3 4 3 2))
  (local parent-position (glm.vec3 10 20 30))
  (local parent-rotation (glm.quat (math.rad 30) (glm.vec3 0 1 0)))

  (set cuboid.layout.size parent-size)
  (cuboid.layout:set-position parent-position)
  (cuboid.layout:set-rotation parent-rotation)
  (cuboid.layout:layouter)

  (each [i face (ipairs faces)]
    (local state face.state)
    (local axes (. expected-axis-orders i))
    (local expected-size
      (glm.vec3 (. parent-size (. axes 1))
            (. parent-size (. axes 2))
            (. parent-size (. axes 3))))
    (assert (vec-approx= state.last-size expected-size))
    (local expected-rotation (* parent-rotation (. expected-face-rotations i)))
    (assert (quat-approx= state.last-rotation expected-rotation))
    (local offset-fn (. expected-offsets i))
    (local base-offset (offset-fn parent-size))
    (local rotated-offset (parent-rotation:rotate base-offset))
    (assert (vec-approx= state.last-position (+ parent-position rotated-offset))))

  (cuboid:drop))

(table.insert tests {:name "Cuboid layouter orients faces" :fn cuboid-layouter-positions-faces})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "cuboid"
                       :tests tests})))

{:name "cuboid"
 :tests tests
 :main main}
