(local M {})

(local native (require :perlin-terrain-native))

(fn clone-array [items]
  (icollect [_ value (ipairs (or items []))] value))

(fn default-heights [chunk-samples default-height]
  (local width (. chunk-samples 1))
  (local depth (. chunk-samples 2))
  (local heights [])
  (for [_ 1 (* width depth)]
    (table.insert heights default-height))
  heights)

(fn M.chunk-count [record]
  (length (or (and record record.chunks) [])))

(fn sample-bounds [record]
  (local options (or record.options {}))
  (local chunk-samples (or options.chunk-samples [17 17]))
  (local chunk-width (. chunk-samples 1))
  (local chunk-length (. chunk-samples 2))
  (local chunks (or record.chunks []))
  (var min-sample-x nil)
  (var min-sample-z nil)
  (var max-sample-x nil)
  (var max-sample-z nil)
  (each [_ chunk (ipairs chunks)]
    (local coord (or chunk.coord [0 0]))
    (local chunk-x (or (. coord 1) coord.x 0))
    (local chunk-z (or (. coord 2) coord.y coord.z 0))
    (local start-sample-x (* chunk-x (- chunk-width 1)))
    (local start-sample-z (* chunk-z (- chunk-length 1)))
    (local end-sample-x (+ start-sample-x (- chunk-width 1)))
    (local end-sample-z (+ start-sample-z (- chunk-length 1)))
    (if (= min-sample-x nil)
        (do
          (set min-sample-x start-sample-x)
          (set min-sample-z start-sample-z)
          (set max-sample-x end-sample-x)
          (set max-sample-z end-sample-z))
        (do
          (when (< start-sample-x min-sample-x)
            (set min-sample-x start-sample-x))
          (when (< start-sample-z min-sample-z)
            (set min-sample-z start-sample-z))
          (when (> end-sample-x max-sample-x)
            (set max-sample-x end-sample-x))
          (when (> end-sample-z max-sample-z)
            (set max-sample-z end-sample-z)))))
  (when (= min-sample-x nil)
    (set min-sample-x 0)
    (set min-sample-z 0)
    (set max-sample-x (- chunk-width 1))
    (set max-sample-z (- chunk-length 1)))
  {:min-sample-x min-sample-x
   :min-sample-z min-sample-z
   :max-sample-x max-sample-x
   :max-sample-z max-sample-z
   :width (+ (- max-sample-x min-sample-x) 1)
   :length (+ (- max-sample-z min-sample-z) 1)})

(fn sample-key [sample-x sample-z]
  (.. (tostring sample-x) ":" (tostring sample-z)))

(fn chunk-key [chunk-x chunk-z]
  (sample-key chunk-x chunk-z))

(fn sort-samples! [samples]
  (table.sort samples
    (fn [left right]
      (if (= left.z right.z)
          (< left.x right.x)
          (< left.z right.z)))))

(fn normalize-sample-target [record raw]
  (local bounds (sample-bounds record))
  (local unique {})
  (local ordered [])
  (each [_ sample (ipairs (or raw.samples []))]
    (local sample-x (and sample sample.x))
    (local sample-z (and sample sample.z))
    (when (and (not (= sample-x nil))
               (not (= sample-z nil))
               (>= sample-x bounds.min-sample-x)
               (<= sample-x bounds.max-sample-x)
               (>= sample-z bounds.min-sample-z)
               (<= sample-z bounds.max-sample-z))
      (local key (sample-key sample-x sample-z))
      (when (not (. unique key))
        (local entry {:x sample-x :z sample-z})
        (set (. unique key) entry)
        (table.insert ordered entry))))
  (if (= (length ordered) 0)
      nil
      (do
        (sort-samples! ordered)
        (var min-x (. (. ordered 1) :x))
        (var max-x min-x)
        (var min-z (. (. ordered 1) :z))
        (var max-z min-z)
        (each [_ sample (ipairs ordered)]
          (when (< sample.x min-x)
            (set min-x sample.x))
          (when (> sample.x max-x)
            (set max-x sample.x))
          (when (< sample.z min-z)
            (set min-z sample.z))
          (when (> sample.z max-z)
            (set max-z sample.z)))
        {:mode :samples
         :samples ordered
         :sample-lookup unique
         :sample-count (length ordered)
         :x0 min-x
         :z0 min-z
         :x1 max-x
         :z1 max-z
         :width (+ (- max-x min-x) 1)
         :length (+ (- max-z min-z) 1)})))

(fn normalize-rectangular-sample-target [record raw]
  (local bounds (sample-bounds record))
  (local raw-x0 (math.min raw.x0 raw.x1))
  (local raw-x1 (math.max raw.x0 raw.x1))
  (local raw-z0 (math.min raw.z0 raw.z1))
  (local raw-z1 (math.max raw.z0 raw.z1))
  (if (or (< raw-x1 bounds.min-sample-x)
          (> raw-x0 bounds.max-sample-x)
          (< raw-z1 bounds.min-sample-z)
          (> raw-z0 bounds.max-sample-z))
      nil
      (do
        (local x0 (math.max bounds.min-sample-x raw-x0))
        (local x1 (math.min bounds.max-sample-x raw-x1))
        (local z0 (math.max bounds.min-sample-z raw-z0))
        (local z1 (math.min bounds.max-sample-z raw-z1))
        {:mode :samples
         :shape :rect
         :x0 x0
         :z0 z0
         :x1 x1
         :z1 z1
         :sample-count (* (+ (- x1 x0) 1)
                          (+ (- z1 z0) 1))
         :width (+ (- x1 x0) 1)
         :length (+ (- z1 z0) 1)})))

(fn normalize-target [record target]
  (local raw (or target {:mode :whole}))
  (local mode
    (if (or (= raw.mode :rect) (= raw.mode "rect"))
        :rect
        (or (= raw.mode :samples) (= raw.mode "samples"))
        :samples
        :whole))
  (if (= mode :whole)
      (do
        (local bounds (sample-bounds record))
        {:mode :whole
         :x0 bounds.min-sample-x
         :z0 bounds.min-sample-z
         :x1 bounds.max-sample-x
         :z1 bounds.max-sample-z
         :width bounds.width
         :length bounds.length})
      (if (or (= mode :rect)
              (= raw.shape :rect))
          (normalize-rectangular-sample-target record raw)
          (normalize-sample-target record raw))))

(fn rectangularize-target [record target]
  (local normalized (normalize-target record target))
  (if (or (= normalized nil)
          (not (= normalized.mode :samples)))
      normalized
      (normalize-rectangular-sample-target record normalized)))

(fn target-contains-sample? [target sample-x sample-z]
  (if (= target.mode :samples)
      (if (= target.shape :rect)
          (and (>= sample-x target.x0)
               (<= sample-x target.x1)
               (>= sample-z target.z0)
               (<= sample-z target.z1))
          (not (= (. (or target.sample-lookup {}) (sample-key sample-x sample-z)) nil)))
      (and (>= sample-x target.x0)
           (<= sample-x target.x1)
           (>= sample-z target.z0)
           (<= sample-z target.z1))))

(fn resolve-sample-slot [record chunk-map sample-x sample-z]
  (local options (or record.options {}))
  (local chunk-samples (or options.chunk-samples [17 17]))
  (local chunk-width (. chunk-samples 1))
  (local chunk-length (. chunk-samples 2))
  (local stride-x (- chunk-width 1))
  (local stride-z (- chunk-length 1))
  (local primary-chunk-x (math.floor (/ sample-x stride-x)))
  (local primary-chunk-z (math.floor (/ sample-z stride-z)))
  (local primary-local-x (- sample-x (* primary-chunk-x stride-x)))
  (local primary-local-z (- sample-z (* primary-chunk-z stride-z)))

  (fn try-slot [chunk-x chunk-z local-x local-z]
    (local chunk (. chunk-map (.. chunk-x ":" chunk-z)))
    (if (and chunk
             (>= local-x 0) (< local-x chunk-width)
             (>= local-z 0) (< local-z chunk-length))
        (do
          (local heights (or chunk.heights []))
          (local idx (+ (* local-z chunk-width) local-x 1))
          {:chunk chunk
           :heights heights
           :idx idx
           :sample-x sample-x
           :sample-z sample-z})
        nil))

  (local primary
    (try-slot primary-chunk-x primary-chunk-z primary-local-x primary-local-z))
  (if (not (= primary nil))
      primary
      (do
        (local seam-x-slot
          (if (= primary-local-x 0)
              (try-slot (- primary-chunk-x 1) primary-chunk-z stride-x primary-local-z)
              nil))
        (if (not (= seam-x-slot nil))
            seam-x-slot
            (do
              (local seam-z-slot
                (if (= primary-local-z 0)
                    (try-slot primary-chunk-x (- primary-chunk-z 1) primary-local-x stride-z)
                    nil))
              (if (not (= seam-z-slot nil))
                  seam-z-slot
                  (if (and (= primary-local-x 0) (= primary-local-z 0))
                      (try-slot (- primary-chunk-x 1) (- primary-chunk-z 1) stride-x stride-z)
                      nil)))))))

(fn each-target-sample [record target f]
  (if (and (= target.mode :samples)
           (not (= target.shape :rect)))
      (do
        (local chunk-map {})
        (each [_ chunk (ipairs (or record.chunks []))]
          (local coord (or chunk.coord [0 0]))
          (local chunk-x (or (. coord 1) coord.x 0))
          (local chunk-z (or (. coord 2) coord.y coord.z 0))
          (set (. chunk-map (sample-key chunk-x chunk-z)) chunk))
        (each [_ sample (ipairs (or target.samples []))]
          (local slot (resolve-sample-slot record chunk-map sample.x sample.z))
          (when slot
            (f slot.chunk slot.heights slot.idx slot.sample-x slot.sample-z))))
      (do
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
              (when (target-contains-sample? target global-x global-z)
                (local idx (+ (* sample-z chunk-width) sample-x 1))
                (f chunk heights idx global-x global-z))))))))

(fn M.fill-record! [record height target]
  (local resolved-target (normalize-target record target))
  (when (not record.options)
    (set record.options {}))
  (when (= resolved-target.mode :whole)
    (set record.options.default-height height))
  (each-target-sample record resolved-target
    (fn [_chunk heights idx _sample-x _sample-z]
      (set (. heights idx) height)))
  record)

(fn M.apply-perlin-record! [record opts]
  (local options (or opts {}))
  (local target (normalize-target record options.target))
  (local mesh
    (native.PerlinTerrainMesh {:width target.width
                               :length target.length
                               :seed options.seed
                               :n1div options.n1div
                               :n2div options.n2div
                               :n3div options.n3div
                               :n1scale options.n1scale
                               :n2scale options.n2scale
                               :n3scale options.n3scale
                               :zroot options.zroot
                               :zpower options.zpower}))
  (each-target-sample record target
    (fn [_chunk heights idx sample-x sample-z]
      (set (. heights idx)
           (mesh:point-height (- sample-x target.x0)
                              (- sample-z target.z0)))))
  (when (not record.options)
    (set record.options {}))
  (when (= target.mode :whole)
    (set record.options.default-height 0.0))
  record)

(fn M.adjust-record! [record delta target]
  (local resolved-target (normalize-target record target))
  (when (not record.options)
    (set record.options {}))
  (when (= resolved-target.mode :whole)
    (set record.options.default-height (+ (or record.options.default-height 0.0) delta)))
  (each-target-sample record resolved-target
    (fn [_chunk heights idx _sample-x _sample-z]
      (set (. heights idx) (+ (or (. heights idx) 0.0) delta))))
  record)

(fn M.adjust-record-targets! [record delta targets]
  (each [_ target (ipairs (or targets []))]
    (M.adjust-record! record delta target))
  record)

(fn M.resize-record! [record opts]
  (local options (or opts {}))
  (local min-chunk-x (math.min options.min-chunk-x options.max-chunk-x))
  (local max-chunk-x (math.max options.min-chunk-x options.max-chunk-x))
  (local min-chunk-z (math.min options.min-chunk-z options.max-chunk-z))
  (local max-chunk-z (math.max options.min-chunk-z options.max-chunk-z))
  (when (not record.options)
    (set record.options {}))
  (local chunk-samples (or record.options.chunk-samples [17 17]))
  (local fill-height
    (if (= options.fill-height nil)
        (or record.options.default-height 0.0)
        options.fill-height))
  (local existing {})
  (each [_ chunk (ipairs (or record.chunks []))]
    (local coord (or chunk.coord [0 0]))
    (local chunk-x (or (. coord 1) coord.x 0))
    (local chunk-z (or (. coord 2) coord.y coord.z 0))
    (set (. existing (chunk-key chunk-x chunk-z)) chunk))
  (local resized [])
  (for [chunk-z min-chunk-z max-chunk-z]
    (for [chunk-x min-chunk-x max-chunk-x]
      (local existing-chunk (. existing (chunk-key chunk-x chunk-z)))
      (table.insert resized
        (if existing-chunk
            {:coord [chunk-x chunk-z]
             :size chunk-samples
             :heights (clone-array existing-chunk.heights)}
            {:coord [chunk-x chunk-z]
             :size chunk-samples
             :heights (default-heights chunk-samples fill-height)}))))
  (set record.chunks resized)
  (set record.options.default-height fill-height)
  record)

{:chunk-count M.chunk-count
 :sample-bounds sample-bounds
 :normalize-target normalize-target
 :rectangular-sample-target normalize-rectangular-sample-target
 :rectangularize-target rectangularize-target
 :fill-record! M.fill-record!
 :adjust-record! M.adjust-record!
 :adjust-record-targets! M.adjust-record-targets!
 :apply-perlin-record! M.apply-perlin-record!
 :resize-record! M.resize-record!}
