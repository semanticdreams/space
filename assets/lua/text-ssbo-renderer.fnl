(local gl (require :gl))
(local shaders (require :shaders))
(local os os)

(local glyph-stride 8)
(local group-matrix-stride 16)
(local clip-matrix-stride 16)
(local stream-ring-size 3)
(local query-ring-size 4)

(fn make-buffer-ring []
  (local out [])
  (for [_ 1 stream-ring-size]
    (table.insert out (gl.glGenBuffers 1)))
  out)

(fn make-query-ring []
  (local out [])
  (for [_ 1 query-ring-size]
    (table.insert out (gl.glGenQueries 1)))
  out)

(fn TextSsboRenderer []
  (local shader
    (shaders.load-shader-from-files
      "msdf-ssbo"
      (app.engine.get-asset-path "shaders/msdf-ssbo.vert")
      (app.engine.get-asset-path "shaders/msdf-ssbo.frag")))
  (shader:use)
  (shader:setInteger "msdf" 0)

  (local vao (gl.glGenVertexArrays 1))
  (local quad-buffer (gl.glGenBuffers 1))
  (local glyph-buffers (make-buffer-ring))
  (local glyph-group-buffers (make-buffer-ring))
  (local groups-ssbos (make-buffer-ring))
  (local clips-ssbos (make-buffer-ring))
  (local group-clip-index-ssbos (make-buffer-ring))
  (local gpu-query-supported?
    (and gl.glGenQueries
         gl.glBeginQuery
         gl.glEndQuery
         gl.glGetQueryObjectuiv
         gl.glGetQueryObjectui64v
         gl.GL_TIME_ELAPSED
         gl.GL_QUERY_RESULT_AVAILABLE
         gl.GL_QUERY_RESULT))
  (local upload-gpu-queries (if gpu-query-supported? (make-query-ring) nil))
  (local draw-gpu-queries (if gpu-query-supported? (make-query-ring) nil))
  (var upload-query-submitted {})
  (var draw-query-submitted {})
  (var active-query-slot 1)
  (var active-stream-slot 1)
  (var stream-frame-id 0)
  (var slot-last-frame {})
  (var active-glyph-buffer (. glyph-buffers active-stream-slot))
  (var active-glyph-group-buffer (. glyph-group-buffers active-stream-slot))
  (var active-groups-ssbo (. groups-ssbos active-stream-slot))
  (var active-clips-ssbo (. clips-ssbos active-stream-slot))
  (var active-group-clip-index-ssbo (. group-clip-index-ssbos active-stream-slot))

  (gl.glBindVertexArray vao)
  (gl.glBindBuffer gl.GL_ARRAY_BUFFER quad-buffer)
  ;; x y u v
  (gl.glBufferData gl.GL_ARRAY_BUFFER
                   [0 0 0 0
                    1 0 1 0
                    0 1 0 1
                    1 1 1 1]
                   gl.GL_STATIC_DRAW)
  (gl.glEnableVertexAttribArray 0)
  (gl.glVertexAttribPointer 0 2 gl.GL_FLOAT gl.GL_FALSE (* 4 4) 0)
  (gl.glEnableVertexAttribArray 1)
  (gl.glVertexAttribPointer 1 2 gl.GL_FLOAT gl.GL_FALSE (* 4 4) (* 2 4))

  (gl.glBindBuffer gl.GL_ARRAY_BUFFER active-glyph-buffer)
  (local stride-bytes (* glyph-stride 4))
  ;; glyphOffset.xy glyphSize.xy glyphUV.xyzw
  (gl.glEnableVertexAttribArray 2)
  (gl.glVertexAttribPointer 2 2 gl.GL_FLOAT gl.GL_FALSE stride-bytes 0)
  (gl.glVertexAttribDivisor 2 1)
  (gl.glEnableVertexAttribArray 3)
  (gl.glVertexAttribPointer 3 2 gl.GL_FLOAT gl.GL_FALSE stride-bytes (* 2 4))
  (gl.glVertexAttribDivisor 3 1)
  (gl.glEnableVertexAttribArray 4)
  (gl.glVertexAttribPointer 4 4 gl.GL_FLOAT gl.GL_FALSE stride-bytes (* 4 4))
  (gl.glVertexAttribDivisor 4 1)

  (gl.glBindBuffer gl.GL_ARRAY_BUFFER active-glyph-group-buffer)
  (local group-stride-bytes 4)
  (gl.glEnableVertexAttribArray 5)
  (gl.glVertexAttribIPointer 5 1 gl.GL_UNSIGNED_INT group-stride-bytes 0)
  (gl.glVertexAttribDivisor 5 1)
  (gl.glBindVertexArray 0)

  (fn resolve-batches [_self glyph-vector batches]
    (if (and batches (> (length batches) 0))
        batches
        (if (and glyph-vector (> (glyph-vector:length) 0))
            [{:clip nil
              :firsts [0]
              :counts [(math.floor (/ (glyph-vector:length) glyph-stride))]}]
            [])))

  (var uploaded-glyph-vectors {})
  (var uploaded-glyph-floats {})
  (fn upload-glyphs [_self glyph-vector stale-slot?]
    (local float-count (and glyph-vector (glyph-vector:length)))
    (when (and float-count (> float-count 0))
      (local slot active-stream-slot)
      (local uploaded-glyph-vector (. uploaded-glyph-vectors slot))
      (local uploaded-glyph-float-count (. uploaded-glyph-floats slot))
      (var dirty-from nil)
      (var dirty-to nil)
      (when (. glyph-vector :dirty-range)
        (local (from to) (glyph-vector:dirty-range))
        (set dirty-from from)
        (set dirty-to to))
      (local dirty? (and dirty-from dirty-to (> dirty-to dirty-from)))
      (local needs-full?
        (or (and stale-slot? dirty?)
            (not (= glyph-vector uploaded-glyph-vector))
            (not (= float-count uploaded-glyph-float-count))))
      (if needs-full?
          (do
            (gl.bufferDataFromVectorBuffer glyph-vector gl.GL_ARRAY_BUFFER gl.GL_STREAM_DRAW)
            (set (. uploaded-glyph-vectors slot) glyph-vector)
            (set (. uploaded-glyph-floats slot) float-count)
            (when (. glyph-vector :clear-dirty)
              (glyph-vector:clear-dirty)))
          (when dirty?
            (gl.bufferSubDataFromVectorBuffer
              glyph-vector
              gl.GL_ARRAY_BUFFER
              (* dirty-from 4)
              (* (- dirty-to dirty-from) 4))
            (when (. glyph-vector :clear-dirty)
              (glyph-vector:clear-dirty))))))

  (var uploaded-group-vectors {})
  (var uploaded-group-floats {})
  (fn upload-groups [_self group-vector stale-slot?]
    (local float-count (and group-vector (group-vector:length)))
    (when (and float-count (> float-count 0))
      (local slot active-stream-slot)
      (local uploaded-group-vector (. uploaded-group-vectors slot))
      (local uploaded-group-float-count (. uploaded-group-floats slot))
      (var dirty-from nil)
      (var dirty-to nil)
      (when (. group-vector :dirty-range)
        (local (from to) (group-vector:dirty-range))
        (set dirty-from from)
        (set dirty-to to))
      (local dirty? (and dirty-from dirty-to (> dirty-to dirty-from)))
      (local needs-full?
        (or (and stale-slot? dirty?)
            (not (= group-vector uploaded-group-vector))
            (not (= float-count uploaded-group-float-count))))
      (if needs-full?
          (do
            (gl.bufferDataFromVectorBuffer group-vector gl.GL_SHADER_STORAGE_BUFFER gl.GL_STREAM_DRAW)
            (set (. uploaded-group-vectors slot) group-vector)
            (set (. uploaded-group-floats slot) float-count)
            (when (. group-vector :clear-dirty)
              (group-vector:clear-dirty)))
          (when dirty?
            (gl.bufferSubDataFromVectorBuffer
              group-vector
              gl.GL_SHADER_STORAGE_BUFFER
              (* dirty-from 4)
              (* (- dirty-to dirty-from) 4))
            (when (. group-vector :clear-dirty)
              (group-vector:clear-dirty))))))

  (var uploaded-clip-vectors {})
  (var uploaded-clip-floats {})
  (fn upload-clips [_self clip-vector stale-slot?]
    (local float-count (and clip-vector (clip-vector:length)))
    (when (and float-count (> float-count 0))
      (local slot active-stream-slot)
      (local uploaded-clip-vector (. uploaded-clip-vectors slot))
      (local uploaded-clip-float-count (. uploaded-clip-floats slot))
      (var dirty-from nil)
      (var dirty-to nil)
      (when (. clip-vector :dirty-range)
        (local (from to) (clip-vector:dirty-range))
        (set dirty-from from)
        (set dirty-to to))
      (local dirty? (and dirty-from dirty-to (> dirty-to dirty-from)))
      (local needs-full?
        (or (and stale-slot? dirty?)
            (not (= clip-vector uploaded-clip-vector))
            (not (= float-count uploaded-clip-float-count))))
      (if needs-full?
          (do
            (gl.bufferDataFromVectorBuffer clip-vector gl.GL_SHADER_STORAGE_BUFFER gl.GL_STREAM_DRAW)
            (set (. uploaded-clip-vectors slot) clip-vector)
            (set (. uploaded-clip-floats slot) float-count)
            (when (. clip-vector :clear-dirty)
              (clip-vector:clear-dirty)))
          (when dirty?
            (gl.bufferSubDataFromVectorBuffer
              clip-vector
              gl.GL_SHADER_STORAGE_BUFFER
              (* dirty-from 4)
              (* (- dirty-to dirty-from) 4))
            (when (. clip-vector :clear-dirty)
              (clip-vector:clear-dirty))))))

  (var uploaded-group-index-vectors {})
  (var uploaded-group-index-counts {})
  (fn upload-group-indices [_self glyph-group-vector stale-slot?]
    (local element-count (and glyph-group-vector (glyph-group-vector:length)))
    (when (and element-count (> element-count 0))
      (local slot active-stream-slot)
      (local uploaded-group-index-vector (. uploaded-group-index-vectors slot))
      (local uploaded-group-index-count (. uploaded-group-index-counts slot))
      (var dirty-from nil)
      (var dirty-to nil)
      (when (. glyph-group-vector :dirty-range)
        (local (from to) (glyph-group-vector:dirty-range))
        (set dirty-from from)
        (set dirty-to to))
      (local dirty? (and dirty-from dirty-to (> dirty-to dirty-from)))
      (local needs-full?
        (or (and stale-slot? dirty?)
            (not (= glyph-group-vector uploaded-group-index-vector))
            (not (= element-count uploaded-group-index-count))))
      (if needs-full?
          (do
            (gl.bufferDataUIntFromVectorBuffer glyph-group-vector gl.GL_ARRAY_BUFFER gl.GL_STREAM_DRAW)
            (set (. uploaded-group-index-vectors slot) glyph-group-vector)
            (set (. uploaded-group-index-counts slot) element-count)
            (when (. glyph-group-vector :clear-dirty)
              (glyph-group-vector:clear-dirty)))
          (when dirty?
            (gl.bufferSubDataUIntFromVectorBuffer
              glyph-group-vector
              gl.GL_ARRAY_BUFFER
              dirty-from
              (- dirty-to dirty-from))
            (when (. glyph-group-vector :clear-dirty)
              (glyph-group-vector:clear-dirty))))))

  (var uploaded-group-clip-index-vectors {})
  (var uploaded-group-clip-index-counts {})
  (var last-upload-seconds 0.0)
  (var last-draw-seconds 0.0)
  (var last-gpu-upload-seconds 0.0)
  (var last-gpu-draw-seconds 0.0)

  (fn rotate-query-slot [_self]
    (set active-query-slot (+ (% active-query-slot query-ring-size) 1)))

  (fn update-gpu-query-result [_self queries submitted slot setter]
    (when (and gpu-query-supported?
               (. submitted slot))
      (local query (. queries slot))
      (local available
        (gl.glGetQueryObjectuiv query gl.GL_QUERY_RESULT_AVAILABLE))
      (when (= available 1)
        (setter (* (gl.glGetQueryObjectui64v query gl.GL_QUERY_RESULT) 0.000000001)))))
  (fn upload-group-clip-indices [_self group-clip-index-vector stale-slot?]
    (local element-count (and group-clip-index-vector (group-clip-index-vector:length)))
    (when (and element-count (> element-count 0))
      (local slot active-stream-slot)
      (local uploaded-group-clip-index-vector (. uploaded-group-clip-index-vectors slot))
      (local uploaded-group-clip-index-count (. uploaded-group-clip-index-counts slot))
      (var dirty-from nil)
      (var dirty-to nil)
      (when (. group-clip-index-vector :dirty-range)
        (local (from to) (group-clip-index-vector:dirty-range))
        (set dirty-from from)
        (set dirty-to to))
      (local dirty? (and dirty-from dirty-to (> dirty-to dirty-from)))
      (local needs-full?
        (or (and stale-slot? dirty?)
            (not (= group-clip-index-vector uploaded-group-clip-index-vector))
            (not (= element-count uploaded-group-clip-index-count))))
      (if needs-full?
          (do
            (gl.bufferDataUIntFromVectorBuffer group-clip-index-vector gl.GL_SHADER_STORAGE_BUFFER gl.GL_STREAM_DRAW)
            (set (. uploaded-group-clip-index-vectors slot) group-clip-index-vector)
            (set (. uploaded-group-clip-index-counts slot) element-count)
            (when (. group-clip-index-vector :clear-dirty)
              (group-clip-index-vector:clear-dirty)))
          (when dirty?
            (gl.bufferSubDataUIntFromVectorBuffer
              group-clip-index-vector
              gl.GL_SHADER_STORAGE_BUFFER
              dirty-from
              (- dirty-to dirty-from))
            (when (. group-clip-index-vector :clear-dirty)
              (group-clip-index-vector:clear-dirty))))))

  (var active-instance-first nil)
  (fn bind-instance-window [_self first]
    (when (not (= first active-instance-first))
      (set active-instance-first first)
      (local base-bytes (* first stride-bytes))
      (local group-base-bytes (* first 4))
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER active-glyph-buffer)
      (gl.glVertexAttribPointer 2 2 gl.GL_FLOAT gl.GL_FALSE stride-bytes base-bytes)
      (gl.glVertexAttribPointer 3 2 gl.GL_FLOAT gl.GL_FALSE stride-bytes (+ base-bytes (* 2 4)))
      (gl.glVertexAttribPointer 4 4 gl.GL_FLOAT gl.GL_FALSE stride-bytes (+ base-bytes (* 4 4)))
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER active-glyph-group-buffer)
      (gl.glVertexAttribIPointer 5 1 gl.GL_UNSIGNED_INT 4 group-base-bytes)))

  (fn rotate-stream-slot [_self]
    (set active-stream-slot (+ (% active-stream-slot stream-ring-size) 1))
    (set active-glyph-buffer (. glyph-buffers active-stream-slot))
    (set active-glyph-group-buffer (. glyph-group-buffers active-stream-slot))
    (set active-groups-ssbo (. groups-ssbos active-stream-slot))
    (set active-clips-ssbo (. clips-ssbos active-stream-slot))
    (set active-group-clip-index-ssbo (. group-clip-index-ssbos active-stream-slot)))

  (fn render [self glyph-vector glyph-group-vector group-vector group-clip-index-vector clip-vector font projection view batches]
    (when (and glyph-vector
               glyph-group-vector
               group-vector
               group-clip-index-vector
               clip-vector
               font
               font.texture
               font.texture.ready
               (> (glyph-vector:length) 0)
               (>= (glyph-group-vector:length) (math.floor (/ (glyph-vector:length) glyph-stride)))
               (>= (group-vector:length) group-matrix-stride)
               (>= (group-clip-index-vector:length) 1)
               (>= (clip-vector:length) clip-matrix-stride))
      (gl.glBindVertexArray vao)
      (set stream-frame-id (+ stream-frame-id 1))
      (self:rotate-query-slot)
      (self:update-gpu-query-result upload-gpu-queries
                                    upload-query-submitted
                                    active-query-slot
                                    (fn [value] (set last-gpu-upload-seconds value)))
      (self:update-gpu-query-result draw-gpu-queries
                                    draw-query-submitted
                                    active-query-slot
                                    (fn [value] (set last-gpu-draw-seconds value)))
      (self:rotate-stream-slot)
      (local upload-start (os.clock))
      (local last-frame (. slot-last-frame active-stream-slot))
      (local stale-slot?
        (or (= last-frame nil)
            (> (- stream-frame-id last-frame) 1)))
      (gl.glBindBuffer gl.GL_ARRAY_BUFFER active-glyph-buffer)
      (when gpu-query-supported?
        (gl.glBeginQuery gl.GL_TIME_ELAPSED (. upload-gpu-queries active-query-slot)))
      (set active-instance-first nil)
      (self:upload-glyphs glyph-vector stale-slot?)

      (gl.glBindBuffer gl.GL_ARRAY_BUFFER active-glyph-group-buffer)
      (self:upload-group-indices glyph-group-vector stale-slot?)

      (gl.glBindBuffer gl.GL_SHADER_STORAGE_BUFFER active-groups-ssbo)
      (self:upload-groups group-vector stale-slot?)
      (gl.glBindBufferBase gl.GL_SHADER_STORAGE_BUFFER 0 active-groups-ssbo)

      (gl.glBindBuffer gl.GL_SHADER_STORAGE_BUFFER active-clips-ssbo)
      (self:upload-clips clip-vector stale-slot?)
      (gl.glBindBufferBase gl.GL_SHADER_STORAGE_BUFFER 1 active-clips-ssbo)

      (gl.glBindBuffer gl.GL_SHADER_STORAGE_BUFFER active-group-clip-index-ssbo)
      (self:upload-group-clip-indices group-clip-index-vector stale-slot?)
      (gl.glBindBufferBase gl.GL_SHADER_STORAGE_BUFFER 2 active-group-clip-index-ssbo)
      (when gpu-query-supported?
        (gl.glEndQuery gl.GL_TIME_ELAPSED)
        (set (. upload-query-submitted active-query-slot) true))
      (set (. slot-last-frame active-stream-slot) stream-frame-id)

      (set last-upload-seconds (- (os.clock) upload-start))
      (local draw-start (os.clock))
      (when gpu-query-supported?
        (gl.glBeginQuery gl.GL_TIME_ELAPSED (. draw-gpu-queries active-query-slot)))

      (shader:use)
      (shader:setMatrix4 "projection" projection)
      (shader:setMatrix4 "view" view)
      (shader:setFloat "pxRange" font.metadata.atlas.distanceRange)
      (shader:setInteger "msdf" 0)
      (shader:setVector3f "textColor" 1 1 1)
      (shader:setFloat "textAlpha" 1)

      (gl.glActiveTexture gl.GL_TEXTURE0)
      (gl.glBindTexture gl.GL_TEXTURE_2D font.texture.id)

      (each [_ bucket (ipairs (self:resolve-batches glyph-vector batches))]
        (each [i first (ipairs bucket.firsts)]
          (local count (. bucket.counts i))
          (when (and count (> count 0))
            (self:bind-instance-window first)
            (gl.glDrawArraysInstanced gl.GL_TRIANGLE_STRIP 0 4 count))))
      (when gpu-query-supported?
        (gl.glEndQuery gl.GL_TIME_ELAPSED)
        (set (. draw-query-submitted active-query-slot) true))
      (set last-draw-seconds (- (os.clock) draw-start))))

  {:shader shader
   :glyph-stride glyph-stride
   :group-matrix-stride group-matrix-stride
   :resolve-batches resolve-batches
   :upload-glyphs upload-glyphs
   :upload-group-indices upload-group-indices
   :upload-groups upload-groups
   :upload-clips upload-clips
   :upload-group-clip-indices upload-group-clip-indices
   :bind-instance-window bind-instance-window
   :rotate-query-slot rotate-query-slot
   :update-gpu-query-result update-gpu-query-result
   :rotate-stream-slot rotate-stream-slot
   :get-last-upload-seconds (fn [_self] last-upload-seconds)
   :get-last-draw-seconds (fn [_self] last-draw-seconds)
   :get-last-gpu-upload-seconds (fn [_self] last-gpu-upload-seconds)
   :get-last-gpu-draw-seconds (fn [_self] last-gpu-draw-seconds)
   :render render})

TextSsboRenderer
