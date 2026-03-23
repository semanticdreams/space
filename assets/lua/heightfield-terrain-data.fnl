(local M {})

(local native (require :perlin-terrain-native))

(fn M.fill-record! [record height]
  (local chunks (or record.chunks []))
  (when (not record.options)
    (set record.options {}))
  (set record.options.default-height height)
  (each [_ chunk (ipairs chunks)]
    (local heights (or chunk.heights []))
    (for [idx 1 (length heights)]
      (set (. heights idx) height)))
  record)

(fn M.chunk-count [record]
  (length (or (and record record.chunks) [])))

(fn sample-bounds [record]
  (local options (or record.options {}))
  (local chunk-samples (or options.chunk-samples [17 17]))
  (local chunk-width (. chunk-samples 1))
  (local chunk-length (. chunk-samples 2))
  (var min-sample-x 0)
  (var min-sample-z 0)
  (var max-sample-x (- chunk-width 1))
  (var max-sample-z (- chunk-length 1))
  (each [_ chunk (ipairs (or record.chunks []))]
    (local coord (or chunk.coord [0 0]))
    (local chunk-x (or (. coord 1) coord.x 0))
    (local chunk-z (or (. coord 2) coord.y coord.z 0))
    (local start-sample-x (* chunk-x (- chunk-width 1)))
    (local start-sample-z (* chunk-z (- chunk-length 1)))
    (local end-sample-x (+ start-sample-x (- chunk-width 1)))
    (local end-sample-z (+ start-sample-z (- chunk-length 1)))
    (when (< start-sample-x min-sample-x)
      (set min-sample-x start-sample-x))
    (when (< start-sample-z min-sample-z)
      (set min-sample-z start-sample-z))
    (when (> end-sample-x max-sample-x)
      (set max-sample-x end-sample-x))
    (when (> end-sample-z max-sample-z)
      (set max-sample-z end-sample-z)))
  {:min-sample-x min-sample-x
   :min-sample-z min-sample-z
   :max-sample-x max-sample-x
   :max-sample-z max-sample-z
   :width (+ (- max-sample-x min-sample-x) 1)
   :length (+ (- max-sample-z min-sample-z) 1)})

(fn M.apply-perlin-record! [record opts]
  (local options (or opts {}))
  (local bounds (sample-bounds record))
  (local mesh
    (native.PerlinTerrainMesh {:width bounds.width
                               :length bounds.length
                               :seed options.seed
                               :n1div options.n1div
                               :n2div options.n2div
                               :n3div options.n3div
                               :n1scale options.n1scale
                               :n2scale options.n2scale
                               :n3scale options.n3scale
                               :zroot options.zroot
                               :zpower options.zpower}))
  (local chunk-samples (or (and record.options record.options.chunk-samples) [17 17]))
  (local chunk-width (. chunk-samples 1))
  (local chunk-length (. chunk-samples 2))
  (each [_ chunk (ipairs (or record.chunks []))]
    (local coord (or chunk.coord [0 0]))
    (local chunk-x (or (. coord 1) coord.x 0))
    (local chunk-z (or (. coord 2) coord.y coord.z 0))
    (local heights (or chunk.heights []))
      (for [sample-z 0 (- chunk-length 1)]
        (for [sample-x 0 (- chunk-width 1)]
          (local global-x (+ (* chunk-x (- chunk-width 1)) sample-x))
          (local global-z (+ (* chunk-z (- chunk-length 1)) sample-z))
          (local idx (+ (* sample-z chunk-width) sample-x 1))
          (set (. heights idx)
               (mesh:point-height (- global-x bounds.min-sample-x)
                                  (- global-z bounds.min-sample-z))))))
  (when (not record.options)
    (set record.options {}))
  (set record.options.default-height 0.0)
  record)

M
