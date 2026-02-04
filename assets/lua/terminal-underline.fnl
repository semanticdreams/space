(local glm (require :glm))
(local underline-stride (* 8 6))

(fn underline-geometry [state cell-size style line-height resolve-ascender-height]
  (local asc (or (resolve-ascender-height state) cell-size.y))
  (local baseline-start (math.max 0.0 (- cell-size.y asc)))
  (local reference-height (or (and style (line-height style)) cell-size.y))
  (local thickness (math.max 1.0 (* 0.08 reference-height)))
  (local underline-top (math.min cell-size.y (+ baseline-start asc)))
  (local y0 (math.max 0.0 (- underline-top thickness)))
  {:y0 y0
   :y1 (math.min cell-size.y (+ y0 thickness))})

(fn write-underline [opts]
  (local vector opts.vector)
  (local handle opts.handle)
  (local cell-origin opts.cell-origin)
  (local cell-size opts.cell-size)
  (local row opts.row)
  (local col opts.col)
  (local color opts.color)
  (local depth opts.depth)
  (local rotation opts.rotation)
  (local position opts.position)
  (local base opts.base)
  (local y0 opts.y0)
  (local y1 opts.y1)
  (local offset (cell-origin row col))
  (local verts [[0.0 y0 0.0]
                [0.0 y1 0.0]
                [cell-size.x y1 0.0]
                [cell-size.x y1 0.0]
                [cell-size.x y0 0.0]
                [0.0 y0 0.0]])
  (for [i 1 6]
    (local local-pos (glm.vec3 (table.unpack (. verts i))))
    (vector.set-glm-vec3
     vector
     handle
     (+ base (* (- i 1) 8))
     (+ (rotation:rotate (+ offset local-pos))
        position))
    (vector:set-glm-vec4 handle (+ base (* (- i 1) 8) 3) color)
    (vector:set-float handle (+ base (* (- i 1) 8) 7) depth)))

(fn write-empty-underline [vector handle base depth]
  (for [i 0 5]
    (local offset (+ base (* i 8)))
    (vector:set-glm-vec4 handle (+ offset 3) (glm.vec4 0 0 0 0))
    (vector:set-float handle (+ offset 7) depth)))

{:underline-geometry underline-geometry
 :write-underline write-underline
 :write-empty-underline write-empty-underline
 :underline-stride underline-stride}
