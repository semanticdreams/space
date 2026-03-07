(local ClipUtils (require :clip-utils))
(local glm (require :glm))
(local glm-is-mat4 glm.is-mat4)

(local DrawBatcher (require :draw-batcher))
(local {:VectorBuffer VectorBuffer} (require :vector-buffer))
(local {: fallback-glyph
        : codepoints-from-text
        : copy-codepoints
        : line-height
        : line-break?
        : newline-codepoint
        : carriage-return-codepoint} (require :text-utils))

(local os os)
(local string string)
(local glyph-stride 12)
(local group-matrix-stride 16)
(local clip-matrix-stride 16)
(local group-depth-index-stride 1)

(fn zero-matrix []
  (glm.mat4 0))

(fn translation-matrix [x y z]
  (glm.translate (glm.mat4 1) (glm.vec3 (or x 0) (or y 0) (or z 0))))

(fn matrix-from-opts [opts]
  (if (and opts opts.group-matrix)
      opts.group-matrix
      (translation-matrix (and opts opts.x) (and opts opts.y) (and opts opts.z))))

(fn ensure-style [opts]
  (local options (or opts {}))
  {:font options.font
   :scale (or options.scale 1.0)
   :line-height (or options.line-height nil)
   :color (or options.color (glm.vec4 1 1 1 1))})

(fn clip-matrix-key [matrix]
  (if (or (= matrix nil) (= matrix false))
      "clip:nil"
      (do
        (assert (glm-is-mat4 matrix)
                "TextSsboBatcher.clip-matrix-key requires clip matrix to be glm.mat4")
        (ClipUtils.matrix-key matrix))))

(fn hash-codepoints [codepoints scale line-height-value]
  (var hash 2166136261)
  (local scale-part (math.floor (* scale 1000000)))
  (set hash (bxor hash scale-part))
  (set hash (% (* hash 16777619) 4294967296))
  (local line-part
    (if line-height-value
        (math.floor (* line-height-value 1000000))
        0))
  (set hash (bxor hash line-part))
  (set hash (% (* hash 16777619) 4294967296))
  (each [_ codepoint (ipairs codepoints)]
    (set hash (bxor hash codepoint))
    (set hash (% (* hash 16777619) 4294967296)))
  hash)

(fn codepoints-equal? [a b]
  (if (not (= (length a) (length b)))
      false
      (do
        (var equal? true)
        (each [i value (ipairs a)]
          (when (not (= value (. b i)))
            (set equal? false)))
        equal?)))

(fn colors-equal? [a b]
  (and a b
       (= a.x b.x)
       (= a.y b.y)
       (= a.z b.z)
       (= a.w b.w)))

(fn copy-floats [float-list]
  (local out [])
  (each [i value (ipairs float-list)]
    (set (. out i) value))
  out)

(fn collect-diff-ranges [previous next-values]
  (local ranges [])
  (local value-count (length next-values))
  (var range-start nil)
  (for [i 1 value-count]
    (if (not (= (. previous i) (. next-values i)))
        (when (not range-start)
          (set range-start i))
        (when range-start
          (table.insert ranges {:start range-start
                                :end (- i 1)})
          (set range-start nil))))
  (when range-start
    (table.insert ranges {:start range-start
                          :end value-count}))
  ranges)

(fn TextSsboBatcher [_opts]
  (local buckets {})
  (var entries-by-key {})
  (var frame-id 0)
  (var append-id 0)
  (var write-seconds 0.0)
  (var write-count 0)
  (var glyph-write-count 0)
  (var transform-write-count 0)
  (var upsert-count 0)
  (var content-upsert-count 0)
  (var transform-update-count 0)

  (fn reset-entry-geometry [entry]
    (when entry.glyph-handle
      (entry.bucket.draw-batcher:untrack-handle entry.glyph-handle)
      (set entry.glyph-handle nil)
      (set entry.glyph-group-handle nil)
      (set entry.renderable-count 0)
      (set entry.glyph-values-cache nil)
      (set entry.group-fill-count 0)))

  (fn recycle-entry-geometry [entry]
    (when entry.glyph-handle
      (local key entry.renderable-count)
      (when (not (. entry.bucket.free-glyph-handles key))
        (set (. entry.bucket.free-glyph-handles key) []))
      (table.insert (. entry.bucket.free-glyph-handles key) entry.glyph-handle)
      (when (not (. entry.bucket.free-group-index-handles key))
        (set (. entry.bucket.free-group-index-handles key) []))
      (table.insert (. entry.bucket.free-group-index-handles key) entry.glyph-group-handle)))

  (fn acquire-geometry-handles [bucket renderable-count]
    (local glyph-pool (. bucket.free-glyph-handles renderable-count))
    (local group-pool (. bucket.free-group-index-handles renderable-count))
    (if (and glyph-pool group-pool (> (length glyph-pool) 0) (> (length group-pool) 0))
        (values (table.remove glyph-pool) (table.remove group-pool))
        (values nil nil)))

  (fn set-entry-visible [entry value]
    (local next-visible (not (= value false)))
    (when (not (= entry.visible next-visible))
      (set entry.visible next-visible)
      (set entry.bucket.active-entry-count
           (+ entry.bucket.active-entry-count
              (if next-visible 1 -1)))))

  (fn clear-bucket [bucket]
    (each [_ handle (ipairs bucket.glyph-handles)]
      (bucket.glyph-vector:delete handle))
    (each [_ handle (ipairs bucket.group-index-handles)]
      (bucket.glyph-group-vector:delete handle))
    (each [_ handle (ipairs bucket.group-handles)]
      (bucket.group-vector:delete handle))
    (each [_ handle (ipairs bucket.group-clip-index-handles)]
      (bucket.group-clip-index-vector:delete handle))
    (each [_ handle (ipairs bucket.group-depth-index-handles)]
      (bucket.group-depth-index-vector:delete handle))
    (each [_ handle (ipairs bucket.clip-handles)]
      (bucket.clip-vector:delete handle))
    (set bucket.glyph-handles [])
    (set bucket.group-index-handles [])
    (set bucket.group-handles [])
    (set bucket.group-clip-index-handles [])
    (set bucket.group-depth-index-handles [])
    (set bucket.clip-handles [])
    (set bucket.clip-index-by-key {})
    (set bucket.glyph-layout-cache {})
    (set bucket.free-glyph-handles {})
    (set bucket.free-group-index-handles {})
    (set bucket.draw-batcher (DrawBatcher {:stride glyph-stride}))
    (set bucket.active-entry-count 0))

  (fn clear [_self]
    (each [_ bucket (pairs buckets)]
      (clear-bucket bucket))
    (set entries-by-key {})
    (set append-id 0))

  (fn ensure-bucket [font]
    (var bucket (. buckets font))
    (if bucket
        bucket
        (do
          (set bucket {:font font
                       :glyph-vector (VectorBuffer)
                       :glyph-group-vector (VectorBuffer)
                       :group-vector (VectorBuffer)
                       :group-clip-index-vector (VectorBuffer)
                       :group-depth-index-vector (VectorBuffer)
                       :clip-vector (VectorBuffer)
                       :draw-batcher (DrawBatcher {:stride glyph-stride})
                       :glyph-handles []
                       :group-index-handles []
                       :group-handles []
                       :group-clip-index-handles []
                       :group-depth-index-handles []
                       :clip-handles []
                       :clip-index-by-key {}
                       :glyph-layout-cache {}
                       :free-glyph-handles {}
                       :free-group-index-handles {}
                       :active-entry-count 0})
          (set (. buckets font) bucket)
          bucket)))

  (fn ensure-clip-index [bucket clip-matrix]
    (local key (clip-matrix-key clip-matrix))
    (local existing (. bucket.clip-index-by-key key))
    (if (not (= existing nil))
        existing
        (do
          (local handle (bucket.clip-vector:allocate clip-matrix-stride))
          (if (glm-is-mat4 clip-matrix)
              (bucket.clip-vector:set-glm-mat4 handle 0 clip-matrix)
              (for [i 1 clip-matrix-stride]
                (bucket.clip-vector:set-float handle (- i 1) (. clip-matrix i))))
          (table.insert bucket.clip-handles handle)
          (local clip-index (math.floor (/ handle.index clip-matrix-stride)))
          (set (. bucket.clip-index-by-key key) clip-index)
          clip-index)))

  (fn ensure-entry [key style]
    (var existing (. entries-by-key key))
    (when (and existing (not (= existing.font style.font)))
      (recycle-entry-geometry existing)
      (reset-entry-geometry existing)
      (set-entry-visible existing false)
      (set (. entries-by-key key) nil)
      (set existing nil))
    (if existing
        existing
        (do
          (local bucket (ensure-bucket style.font))
          (local group-handle (bucket.group-vector:allocate group-matrix-stride))
          (local group-clip-index-handle (bucket.group-clip-index-vector:allocate 1))
          (local group-depth-index-handle
            (bucket.group-depth-index-vector:allocate group-depth-index-stride))
          (table.insert bucket.group-handles group-handle)
          (table.insert bucket.group-clip-index-handles group-clip-index-handle)
          (table.insert bucket.group-depth-index-handles group-depth-index-handle)
          (local entry {:key key
                        :font style.font
                        :bucket bucket
                        :glyph-handle nil
                        :glyph-group-handle nil
                        :group-handle group-handle
                        :group-clip-index-handle group-clip-index-handle
                        :group-depth-index-handle group-depth-index-handle
                        :group-index (math.floor (/ group-handle.index group-matrix-stride))
                        :clip-index nil
                        :clip-key nil
                        :depth-offset-index nil
                        :renderable-count 0
                        :visible false
                        :matrix-cache {}
                        :glyph-values-cache nil
                        :group-fill-count 0
                        :content-hash nil})
          (set (. entries-by-key key) entry)
          entry)))

  (fn write-group-matrix [entry matrix]
    (if (glm-is-mat4 matrix)
        (do
          (local changed (entry.bucket.group-vector:set-glm-mat4-diff entry.group-handle 0 matrix))
          (set write-count (+ write-count changed))
          (set transform-write-count (+ transform-write-count changed)))
        (for [i 1 group-matrix-stride]
          (local next-value (. matrix i))
          (when (not (= (. entry.matrix-cache i) next-value))
            (set (. entry.matrix-cache i) next-value)
            (set write-count (+ write-count 1))
            (set transform-write-count (+ transform-write-count 1))
            (entry.bucket.group-vector:set-float entry.group-handle (- i 1) next-value)))))

  (fn write-group-clip-index [entry clip-index clip-key]
    (when (or (not (= entry.clip-index clip-index))
              (not (= entry.clip-key clip-key)))
      (set entry.clip-index clip-index)
      (set entry.clip-key clip-key)
      (set write-count (+ write-count 1))
      (set transform-write-count (+ transform-write-count 1))
      (entry.bucket.group-clip-index-vector:set-float entry.group-clip-index-handle 0 clip-index)))

  (fn write-group-depth-index [entry depth-offset-index]
    (local next-index (or depth-offset-index 0))
    (when (not (= entry.depth-offset-index next-index))
      (set entry.depth-offset-index next-index)
      (set write-count (+ write-count 1))
      (set transform-write-count (+ transform-write-count 1))
      (entry.bucket.group-depth-index-vector:set-float
       entry.group-depth-index-handle
       0
       next-index)))

  (fn ensure-glyph-capacity [entry renderable-count]
    (if (= renderable-count entry.renderable-count)
        nil
        (do
          (recycle-entry-geometry entry)
          (reset-entry-geometry entry)
          (when (> renderable-count 0)
            (local (pooled-glyph pooled-group)
              (acquire-geometry-handles entry.bucket renderable-count))
            (set entry.glyph-handle
                 (or pooled-glyph
                     (entry.bucket.glyph-vector:allocate (* renderable-count glyph-stride))))
            (set entry.glyph-group-handle
                 (or pooled-group
                     (entry.bucket.glyph-group-vector:allocate renderable-count)))
            (set entry.renderable-count renderable-count)
            (when (not pooled-glyph)
              (table.insert entry.bucket.glyph-handles entry.glyph-handle))
            (when (not pooled-group)
              (table.insert entry.bucket.group-index-handles entry.glyph-group-handle))
            (entry.bucket.draw-batcher:track-handle entry.glyph-handle nil nil)))))

(fn build-glyph-layout [codepoints style]
    (local font style.font)
    (local metrics (and font.metadata font.metadata.metrics))
    (local resolved-line-height (or style.line-height (line-height style)))
    (local ascender (if (and metrics metrics.ascender)
                        (* style.scale metrics.ascender)
                        resolved-line-height))
    (var x-cursor 0.0)
    (var line-index 0)
    (var renderable-index 0)
    (local glyph-values [])
    (local atlas font.metadata.atlas)
    (local color style.color)
    (local cr (or color.x 1.0))
    (local cg (or color.y 1.0))
    (local cb (or color.z 1.0))
    (local ca (or color.w 1.0))
    (local total (length codepoints))
    (var i 1)
    (while (<= i total)
      (local codepoint (. codepoints i))
      (if (line-break? codepoint)
          (do
            (set line-index (+ line-index 1))
            (set x-cursor 0.0)
            (when (and (= codepoint carriage-return-codepoint)
                       (< i total)
                       (= (. codepoints (+ i 1)) newline-codepoint))
              (set i (+ i 1))))
          (do
            (local glyph (fallback-glyph font codepoint))
            (when (and glyph glyph.planeBounds glyph.atlasBounds)
              (local left (* glyph.planeBounds.left style.scale))
              (local right (* glyph.planeBounds.right style.scale))
              (local bottom (* glyph.planeBounds.bottom style.scale))
              (local top (* glyph.planeBounds.top style.scale))
              (local offset (* renderable-index glyph-stride))
              (local x0 (+ x-cursor left))
              (local y0 (+ (- 0 (* line-index resolved-line-height) ascender) bottom))
              (local width (- right left))
              (local height (- top bottom))
              (local s0 (/ glyph.atlasBounds.left atlas.width))
              (local t0 (/ glyph.atlasBounds.bottom atlas.height))
              (local s1 (/ glyph.atlasBounds.right atlas.width))
              (local t1 (/ glyph.atlasBounds.top atlas.height))
              (set (. glyph-values (+ offset 1)) x0)
              (set (. glyph-values (+ offset 2)) y0)
              (set (. glyph-values (+ offset 3)) width)
              (set (. glyph-values (+ offset 4)) height)
              (set (. glyph-values (+ offset 5)) s0)
              (set (. glyph-values (+ offset 6)) t0)
              (set (. glyph-values (+ offset 7)) s1)
              (set (. glyph-values (+ offset 8)) t1)
              (set (. glyph-values (+ offset 9)) cr)
              (set (. glyph-values (+ offset 10)) cg)
              (set (. glyph-values (+ offset 11)) cb)
              (set (. glyph-values (+ offset 12)) ca)
              (set renderable-index (+ renderable-index 1)))
            (local advance (if (and glyph glyph.advance)
                               (* glyph.advance style.scale)
                               0))
            (set x-cursor (+ x-cursor advance))))
      (set i (+ i 1)))

    {:renderable-count renderable-index
     :values glyph-values})

  (fn resolve-glyph-layout [bucket codepoints style content-hash]
    (local layout-key (.. content-hash ":" (length codepoints)))
    (local existing (. bucket.glyph-layout-cache layout-key))
    (if (and existing
             (= existing.scale style.scale)
             (= existing.line-height style.line-height)
             (colors-equal? existing.color style.color)
             (codepoints-equal? existing.codepoints codepoints))
        existing
        (do
          (local built (build-glyph-layout codepoints style))
          (set built.codepoints (copy-codepoints codepoints))
          (set built.scale style.scale)
          (set built.line-height style.line-height)
          (set built.color style.color)
          (set (. bucket.glyph-layout-cache layout-key) built)
          built)))

  (fn write-glyph-instances [entry layout]
    (local glyph-values layout.values)
    (local previous entry.glyph-values-cache)
    (local value-count (length glyph-values))
    (var changed 0)
    (if (and previous (= (length previous) value-count))
        (do
          (local ranges (collect-diff-ranges previous glyph-values))
          (local range-count (length ranges))
          (if (= range-count 0)
              nil
              (if (<= range-count 4)
                  (each [_ range (ipairs ranges)]
                    (local range-values [])
                    (for [i range.start range.end]
                      (table.insert range-values (. glyph-values i)))
                    (set changed
                         (+ changed
                            (entry.bucket.glyph-vector:set-floats-diff
                              entry.glyph-handle
                              (- range.start 1)
                              range-values))))
                  (set changed
                       (entry.bucket.glyph-vector:set-floats-diff entry.glyph-handle
                                                                  0
                                                                  glyph-values)))))
        (set changed
             (entry.bucket.glyph-vector:set-floats-diff entry.glyph-handle
                                                        0
                                                        glyph-values)))
    (set write-count (+ write-count changed))
    (set glyph-write-count (+ glyph-write-count changed))
    (set entry.glyph-values-cache (copy-floats glyph-values))
    (local group-changed
      (if (and (= entry.group-fill-count layout.renderable-count)
               (not (= entry.group-index nil)))
          0
          (entry.bucket.glyph-group-vector:set-float-fill-diff entry.glyph-group-handle
                                                                0
                                                                layout.renderable-count
                                                                entry.group-index)))
    (set write-count (+ write-count group-changed))
    (set glyph-write-count (+ glyph-write-count group-changed))
    (set entry.group-fill-count layout.renderable-count))

  (fn resolve-clip-matrix [options]
    (if options.clip-matrix
        options.clip-matrix
        (if options.clip
            (ClipUtils.resolve-matrix options.clip)
            (zero-matrix))))

  (fn upsert-text [_self key opts]
    (assert key "TextSsboBatcher.upsert-text requires :key")
    (local write-start (os.clock))
    (set upsert-count (+ upsert-count 1))
    (set content-upsert-count (+ content-upsert-count 1))
    (local options (or opts {}))
    (local style (ensure-style options))
    (assert style.font "TextSsboBatcher.upsert-text requires :font")
    (assert (and style.font.metadata style.font.metadata.atlas)
            "TextSsboBatcher.upsert-text requires font metadata atlas")
    (local codepoints
      (if options.codepoints
          (copy-codepoints options.codepoints)
          (codepoints-from-text (or options.text ""))))
    (local entry (ensure-entry key style))
    (local content-hash (hash-codepoints codepoints style.scale style.line-height))
    (local layout (resolve-glyph-layout entry.bucket codepoints style content-hash))
    (local renderable-count layout.renderable-count)
    (if (= renderable-count 0)
        (do
          (recycle-entry-geometry entry)
          (reset-entry-geometry entry)
          (set-entry-visible entry false)
          (set entry.content-hash nil))
        (do
          (ensure-glyph-capacity entry renderable-count)
          (write-group-matrix entry (matrix-from-opts options))
          (write-group-depth-index entry options.depth-offset-index)
          (local clip-matrix (resolve-clip-matrix options))
          (local next-clip-key (clip-matrix-key clip-matrix))
          (local clip-index (ensure-clip-index entry.bucket clip-matrix))
          (write-group-clip-index entry clip-index next-clip-key)
          (when (or (not (= entry.content-hash content-hash))
                    (not (= entry.renderable-count renderable-count)))
            (set entry.content-hash content-hash)
            (write-glyph-instances entry layout))
          (set-entry-visible entry true)))
    (set write-seconds (+ write-seconds (- (os.clock) write-start))))

  (fn update-text-transform [_self key opts]
    (assert key "TextSsboBatcher.update-text-transform requires :key")
    (local entry (. entries-by-key key))
    (when entry
      (local write-start (os.clock))
      (set transform-update-count (+ transform-update-count 1))
      (local options (or opts {}))
      (write-group-matrix entry (matrix-from-opts options))
      (write-group-depth-index entry options.depth-offset-index)
      (local clip-matrix (resolve-clip-matrix options))
      (local next-clip-key (clip-matrix-key clip-matrix))
      (local clip-index (ensure-clip-index entry.bucket clip-matrix))
      (write-group-clip-index entry clip-index next-clip-key)
      (set-entry-visible entry true)
      (set write-seconds (+ write-seconds (- (os.clock) write-start)))))

  (fn remove-text [_self key]
    (local entry (. entries-by-key key))
    (when entry
      (recycle-entry-geometry entry)
      (reset-entry-geometry entry)
      (set-entry-visible entry false)
      (set entry.content-hash nil)))

  (fn add-text [self opts]
    (local options (or opts {}))
    (if options.key
        (self:upsert-text options.key options)
        (do
          (set append-id (+ append-id 1))
          (self:upsert-text {:append-id append-id} options))))

  (fn begin-frame [_self]
    (set frame-id (+ frame-id 1))
    (set write-seconds 0.0)
    (set write-count 0)
    (set glyph-write-count 0)
    (set transform-write-count 0)
    (set upsert-count 0)
    (set content-upsert-count 0)
    (set transform-update-count 0))

  (fn end-frame [_self]
    nil)

  (fn get-last-stats [_self]
    {:frame-id frame-id
     :write-seconds write-seconds
     :write-count write-count
     :glyph-write-count glyph-write-count
     :transform-write-count transform-write-count
     :upsert-count upsert-count
     :content-upsert-count content-upsert-count
     :transform-update-count transform-update-count})

  (fn get-draw-list [_self]
    (local out [])
    (each [_ bucket (pairs buckets)]
      (when (> bucket.active-entry-count 0)
        (local batches (bucket.draw-batcher:get-batches))
        (when (> (# batches) 0)
          (table.insert out {:font bucket.font
                             :glyph-vector bucket.glyph-vector
                             :glyph-group-vector bucket.glyph-group-vector
                             :group-vector bucket.group-vector
                             :group-clip-index-vector bucket.group-clip-index-vector
                             :group-depth-index-vector bucket.group-depth-index-vector
                             :clip-vector bucket.clip-vector
                             :batches batches}))))
    out)

  (fn render [self renderer projection view]
    (each [_ entry (ipairs (self:get-draw-list))]
      (renderer:render entry.glyph-vector
                       entry.glyph-group-vector
                       entry.group-vector
                       entry.group-clip-index-vector
                       entry.group-depth-index-vector
                       entry.clip-vector
                       entry.font
                       projection
                       view
                       entry.batches)))

  {:clear clear
   :begin-frame begin-frame
   :upsert-text upsert-text
   :update-text-transform update-text-transform
   :end-frame end-frame
   :remove-text remove-text
   :get-last-stats get-last-stats
   :add-text add-text
   :get-draw-list get-draw-list
   :render render})

TextSsboBatcher
