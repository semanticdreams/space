(local glm (require :glm))
(local glm-is-mat4 glm.is-mat4)
(local glm-mat4-bytes-key glm.mat4-bytes-key)
(local ClipUtils (require :clip-utils))
(local {:VectorBuffer VectorBuffer} (require :vector-buffer))
(local os os)

(fn identity-matrix []
  (glm.mat4 1))

(fn QuadBatcher [opts]
  (local options (or opts {}))
  (local instance-stride (or options.instance-stride 21))
  (local vector (VectorBuffer))
  (local clip-vector (VectorBuffer))
  (local clip-group-vector (VectorBuffer))
  (local handles [])
  (local clip-handles [])
  (local clip-group-handles [])
  (var entries [])
  (var entry-by-key {})
  (var free-slots [])
  (var clip-index-by-key {})
  (var clip-group-count 0)
  (var active-count 0)
  (var write-seconds 0.0)
  (var write-count 0)
  (var upsert-count 0)

  (fn clip-matrix-key [matrix]
    (if (or (= matrix nil) (= matrix false))
        "clip:nil"
        (do
          (assert (glm-is-mat4 matrix)
                  "QuadBatcher.clip-matrix-key requires clip matrix to be glm.mat4")
          (glm-mat4-bytes-key matrix))))

  (fn zero-matrix []
    (glm.mat4 0))

  (fn ensure-handle [index]
    (var handle (. handles index))
    (if handle
        handle
        (do
          (set handle (vector:allocate instance-stride))
          (set (. handles index) handle)
          handle)))

  (fn ensure-clip-handle [index]
    (var handle (. clip-handles index))
    (if handle
        handle
        (do
          (set handle (clip-vector:allocate 16))
          (set (. clip-handles index) handle)
          handle)))

  (fn ensure-clip-group-handle [index]
    (var handle (. clip-group-handles index))
    (if handle
        handle
        (do
          (set handle (clip-group-vector:allocate 1))
          (set (. clip-group-handles index) handle)
          handle)))

  (fn write-clip-matrix [clip-index matrix]
    (local handle (ensure-clip-handle (+ clip-index 1)))
    (if (glm-is-mat4 matrix)
        (clip-vector:set-glm-mat4 handle 0 matrix)
        (for [i 1 16]
          (clip-vector:set-float handle (- i 1) (. matrix i)))))

  (fn init-clip-groups []
    (local zero (zero-matrix))
    (set clip-index-by-key {})
    (set clip-group-count 1)
    (set (. clip-index-by-key "clip:nil") 0)
    (set (. clip-index-by-key (clip-matrix-key zero)) 0)
    (write-clip-matrix 0 zero))

  (fn ensure-entry [key]
    (local existing (. entry-by-key key))
    (if existing
        existing
        (do
          (local slot
            (if (> (length free-slots) 0)
                (table.remove free-slots)
                (do
                  (set active-count (+ active-count 1))
                  active-count)))
          ;; Reused holes can sit above current active-count after tail trimming.
          ;; Keep draw-count covering the highest occupied slot.
          (if (> slot active-count)
              (set active-count slot))
          (ensure-handle slot)
          (ensure-clip-group-handle slot)
          (local entry {:slot slot
                        :key key
                        :matrix {}
                        :color {}
                        :depth nil
                        :clip-group nil
                        :visible false})
          (set (. entries slot) entry)
          (set (. entry-by-key key) entry)
          entry)))

  (var ensure-clip-group nil)

  (fn write-entry [entry opts]
    (local write-start (os.clock))
    (local slot entry.slot)
    (local handle (ensure-handle slot))
    (local clip-group-handle (ensure-clip-group-handle slot))
    (local matrix (or opts.matrix (identity-matrix)))
    (local color (or opts.color (glm.vec4 1 1 1 1)))
    (local color1 (or color.x (. color 1) 1))
    (local color2 (or color.y (. color 2) 1))
    (local color3 (or color.z (. color 3) 1))
    (local color4 (or color.w (. color 4) 1))
    (local depth-offset (or opts.depth-offset 0))
    (local clip-matrix
      (if opts.clip-matrix
          opts.clip-matrix
          (ClipUtils.resolve-matrix opts.clip)))
    ;; Clip matrices can be updated in place, so identity checks are unsafe.
    ;; Always resolve the clip group from current matrix values.
    (local clip-group (ensure-clip-group clip-matrix))
    (if (glm-is-mat4 matrix)
        (do
          (set write-count (+ write-count (vector:set-glm-mat4-diff handle 0 matrix))))
        (for [i 1 16]
          (local next-value (. matrix i))
          (when (not (= (. entry.matrix i) next-value))
            (set (. entry.matrix i) next-value)
            (set write-count (+ write-count 1))
            (vector:set-float handle (- i 1) next-value))))
    (when (not (= (. entry.color 1) color1))
      (set (. entry.color 1) color1)
      (set write-count (+ write-count 1))
      (vector:set-float handle 16 color1))
    (when (not (= (. entry.color 2) color2))
      (set (. entry.color 2) color2)
      (set write-count (+ write-count 1))
      (vector:set-float handle 17 color2))
    (when (not (= (. entry.color 3) color3))
      (set (. entry.color 3) color3)
      (set write-count (+ write-count 1))
      (vector:set-float handle 18 color3))
    (when (not (= (. entry.color 4) color4))
      (set (. entry.color 4) color4)
      (set write-count (+ write-count 1))
      (vector:set-float handle 19 color4))
    (when (not (= entry.depth depth-offset))
      (set entry.depth depth-offset)
      (set write-count (+ write-count 1))
      (vector:set-float handle 20 depth-offset))
    (when (not (= entry.clip-group clip-group))
      (set entry.clip-group clip-group)
      (set write-count (+ write-count 1))
      (clip-group-vector:set-float clip-group-handle 0 clip-group))
    (set entry.visible true)
    (set write-seconds (+ write-seconds (- (os.clock) write-start))))

  (fn hide-entry [entry]
    (local handle (ensure-handle entry.slot))
    ;; Keep geometry untouched; shader discards alpha==0 instances so
    ;; hidden slots cannot write depth or leak stale visuals.
    (when (not (= (. entry.color 4) 0))
      (set (. entry.color 4) 0)
      (set write-count (+ write-count 1))
      (vector:set-float handle 19 0))
    (set entry.visible false))

  (fn begin-frame [_self]
    (set write-seconds 0.0)
    (set write-count 0)
    (set upsert-count 0))

  (fn upsert-quad [_self key opts]
    (assert key "QuadBatcher.upsert-quad requires :key")
    (set upsert-count (+ upsert-count 1))
    (local entry (ensure-entry key))
    (write-entry entry (or opts {})))

  (fn end-frame [_self]
    nil)

  (fn remove-quad [_self key]
    (local entry (. entry-by-key key))
    (when entry
      (hide-entry entry)
      (local slot entry.slot)
      (set (. entry-by-key key) nil)
      (set (. entries slot) nil)
      (table.insert free-slots slot)
      (while (and (> active-count 0) (= (. entries active-count) nil))
        (set active-count (- active-count 1)))
      (set entry.visible false)))

  (fn get-last-stats [_self]
    {:write-seconds write-seconds
     :write-count write-count
     :upsert-count upsert-count})

  (set ensure-clip-group
       (fn [clip-matrix]
         (if (or (= clip-matrix nil) (= clip-matrix false))
             0
             (do
               (local key (clip-matrix-key clip-matrix))
               (local existing (. clip-index-by-key key))
               (if (not (= existing nil))
                   existing
                   (do
                     (local clip-index clip-group-count)
                     (set clip-group-count (+ clip-group-count 1))
                     (set (. clip-index-by-key key) clip-index)
                     (write-clip-matrix clip-index clip-matrix)
                     clip-index))))))

  (fn clear [_self]
    (set active-count 0)
    (set entries [])
    (set entry-by-key {})
    (set free-slots [])
    (init-clip-groups))

  (fn add-quad [_self opts]
    (local options (or opts {}))
    (if options.key
        (upsert-quad nil options.key options)
        (do
          (set active-count (+ active-count 1))
          (local handle (ensure-handle active-count))
          (local matrix (or options.matrix (identity-matrix)))
          (if (glm-is-mat4 matrix)
              (vector:set-glm-mat4 handle 0 matrix)
              (for [i 1 16]
                (vector:set-float handle (- i 1) (. matrix i))))
          (vector:set-glm-vec4 handle 16 (or options.color (glm.vec4 1 1 1 1)))
          (vector:set-float handle 20 (or options.depth-offset 0))
          (local clip-matrix
            (if options.clip-matrix
                options.clip-matrix
                (ClipUtils.resolve-matrix options.clip)))
          (local clip-group (ensure-clip-group clip-matrix))
          (local clip-group-handle (ensure-clip-group-handle active-count))
          (clip-group-vector:set-float clip-group-handle 0 clip-group))))

  (fn get-vector [_self]
    vector)

  (fn get-instance-count [_self]
    active-count)

  (fn get-clip-vector [_self]
    clip-vector)

  (fn get-clip-group-vector [_self]
    clip-group-vector)

  (fn get-clip-count [_self]
    clip-group-count)

  (fn get-batches [_self]
    (if (> active-count 0)
        [{:model nil :firsts [0] :counts [active-count]}]
        []))

  (fn drop [_self]
    (each [_ handle (ipairs handles)]
      (vector:delete handle))
    (each [_ handle (ipairs clip-handles)]
      (clip-vector:delete handle))
    (each [_ handle (ipairs clip-group-handles)]
      (clip-group-vector:delete handle)))

  (init-clip-groups)

  {:clear clear
   :begin-frame begin-frame
   :upsert-quad upsert-quad
   :end-frame end-frame
   :remove-quad remove-quad
   :get-last-stats get-last-stats
   :add-quad add-quad
   :get-vector get-vector
   :get-instance-count get-instance-count
   :get-clip-vector get-clip-vector
   :get-clip-group-vector get-clip-group-vector
   :get-clip-count get-clip-count
   :get-batches get-batches
   :drop drop})

QuadBatcher
