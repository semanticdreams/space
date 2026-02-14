(local glm (require :glm))
(local NextLayout (require :next-app/layout))
(local Node NextLayout.Node)

(local face-rotations
  {1 (glm.quat 1 0 0 0)
   2 (glm.quat math.pi (glm.vec3 0 1 0))
   3 (glm.quat (* 0.5 math.pi) (glm.vec3 0 1 0))
   4 (glm.quat (* 1.5 math.pi) (glm.vec3 0 1 0))
   5 (glm.quat (* 1.5 math.pi) (glm.vec3 1 0 0))
   6 (glm.quat (* 0.5 math.pi) (glm.vec3 1 0 0))})

(local axis-mapping
  {1 [1 2 3]
   2 [1 2 3]
   3 [3 2 1]
   4 [3 2 1]
   5 [1 3 2]
   6 [1 3 2]})

(local offset-fns
  {1 (fn [_width _height depth] [0 0 depth])
   2 (fn [width _height _depth] [width 0 0])
   3 (fn [width _height depth] [width 0 depth])
   4 (fn [_width _height _depth] [0 0 0])
   5 (fn [_width height depth] [0 height depth])
   6 (fn [_width _height _depth] [0 0 0])})

(fn safe-face [faces idx]
  (. faces idx))

(fn safe-size-component [face key]
  (if face
      (or (. face key) 0)
      0))

(fn resolve-axes [idx]
  (or (. axis-mapping idx) [1 2 3]))

(fn axis-value [axes width height depth axis-idx]
  (local axis (. axes axis-idx))
  (if (= axis 1)
      width
      (if (= axis 2)
          height
          depth)))

(fn resolve-rotation [idx]
  (or (. face-rotations idx) (glm.quat 1 0 0 0)))

(fn resolve-offset [idx width height depth]
  (local offset-fn (or (. offset-fns idx) (fn [_w _h _d] [0 0 0])))
  (offset-fn width height depth))

(fn CuboidWidget [opts]
  (local options (or opts {}))
  (local faces (or options.children []))
  (assert (>= (length faces) 6)
          "CuboidWidget requires at least six child nodes.")

  (fn measure-fn [self max-width max-height max-depth]
    (each [_ child (ipairs faces)]
      (child:run-measure-subtree max-width max-height max-depth))
    (local f1 (safe-face faces 1))
    (local f2 (safe-face faces 2))
    (local f3 (safe-face faces 3))
    (local f4 (safe-face faces 4))
    (local f5 (safe-face faces 5))
    (local f6 (safe-face faces 6))
    (local width (math.max (safe-size-component f1 :measured-width)
                           (safe-size-component f2 :measured-width)
                           (safe-size-component f5 :measured-width)
                           (safe-size-component f6 :measured-width)))
    (local height (math.max (safe-size-component f1 :measured-height)
                            (safe-size-component f2 :measured-height)
                            (safe-size-component f3 :measured-height)
                            (safe-size-component f4 :measured-height)))
    (local depth (math.max (safe-size-component f3 :measured-width)
                           (safe-size-component f4 :measured-width)
                           (safe-size-component f5 :measured-height)
                           (safe-size-component f6 :measured-height)))
    (self:set-measure width height depth))

  (fn layout-fn [self width height depth]
    (self:set-size width height depth {:mark-dirty? false})
    (each [idx child (ipairs faces)]
      (local axes (resolve-axes idx))
      (local child-width (axis-value axes width height depth 1))
      (local child-height (axis-value axes width height depth 2))
      (local child-depth (axis-value axes width height depth 3))
      (local [x y z] (resolve-offset idx width height depth))
      (child:layout-set-frame x y z child-width child-height child-depth (resolve-rotation idx))
      (child:run-layout-subtree child.width child.height child.depth)))

  (local cuboid
    (Node.new {:name (or options.name "next-cuboid")
               :measure-fn measure-fn
               :layout-fn layout-fn}))
  (each [_ child (ipairs faces)]
    (cuboid:add-child child))
  (set cuboid.faces faces)
  cuboid)

CuboidWidget
