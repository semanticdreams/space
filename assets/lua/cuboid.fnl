(local glm (require :glm))
(local {: Layout} (require :layout))

(local face-rotations
  [(glm.quat 1 0 0 0)
   (glm.quat math.pi (glm.vec3 0 1 0))
   (glm.quat (* 0.5 math.pi) (glm.vec3 0 1 0))
   (glm.quat (* 1.5 math.pi) (glm.vec3 0 1 0))
   (glm.quat (* 1.5 math.pi) (glm.vec3 1 0 0))
   (glm.quat (* 0.5 math.pi) (glm.vec3 1 0 0))])

(local axis-mapping
  {1 [1 2 3]
   2 [1 2 3]
   3 [3 2 1]
   4 [3 2 1]
   5 [1 3 2]
   6 [1 3 2]})

(local offset-fns
  [(fn [size] (glm.vec3 0 0 (. size 3)))
   (fn [size] (glm.vec3 (. size 1) 0 0))
   (fn [size] (glm.vec3 (. size 1) 0 (. size 3)))
   (fn [size] (glm.vec3 0 0 0))
   (fn [size] (glm.vec3 0 (. size 2) (. size 3)))
   (fn [size] (glm.vec3 0 0 0))])

(local safe-component
  (fn [children idx axis]
    (local target (. children idx))
    (if target
        (. target.measure axis)
        0)))

(fn Cuboid [opts]
  (assert (and opts.children (>= (length opts.children) 6))
          "Cuboid requires at least six child widgets.")
  (fn build [ctx]
    (local faces
      (icollect [_ child (ipairs opts.children)]
                (child ctx)))

    (fn measurer [self]
      (set self.measure (glm.vec3 0))
      (each [_ child (ipairs self.children)]
        (child:measurer))
      (local width (math.max
                     (safe-component self.children 1 1)
                     (safe-component self.children 2 1)
                     (safe-component self.children 5 1)
                     (safe-component self.children 6 1)))
      (local height (math.max
                      (safe-component self.children 1 2)
                      (safe-component self.children 2 2)
                      (safe-component self.children 3 2)
                      (safe-component self.children 4 2)))
      (local depth (math.max
                     (safe-component self.children 3 1)
                     (safe-component self.children 4 1)
                     (safe-component self.children 5 2)
                     (safe-component self.children 6 2)))
      (set self.measure (glm.vec3 width height depth)))

    (fn layouter [self]
      (each [i child (ipairs self.children)]
        (local axes (or (. axis-mapping i) [1 2 3]))
        (set child.size
             (glm.vec3 (. self.size (. axes 1))
                   (. self.size (. axes 2))
                   (. self.size (. axes 3))))
        (local local-rotation (or (. face-rotations i) (glm.quat 1 0 0 0)))
        (set child.rotation (* self.rotation local-rotation))
        (local offset ((or (. offset-fns i) (fn [_] (glm.vec3 0 0 0))) self.size))
        (set child.position
             (+ self.position (self.rotation:rotate offset)))
        (set child.depth-offset-index self.depth-offset-index)
        (set child.clip-region self.clip-region)
        (child:layouter)))

    (local layout
      (Layout {:name "cuboid"
               :children (icollect [_ face (ipairs faces)]
                                   face.layout)
               : measurer
               : layouter}))

    (fn drop [self]
      (self.layout:drop)
      (each [_ face (ipairs faces)]
        (face:drop)))

    {: faces : layout : drop}))

Cuboid
