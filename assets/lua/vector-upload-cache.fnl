(local gl (require :gl))

(fn VectorUploadCache [options]
  (local target (or (and options options.target) gl.GL_ARRAY_BUFFER))
  (local usage (or (and options options.usage) gl.GL_STREAM_DRAW))
  (local max-entries (or (and options options.max-entries) 64))
  (local evict-per-upload (or (and options options.evict-per-upload) 1))
  (assert (and (= (type max-entries) :number)
               (= max-entries (math.floor max-entries))
               (> max-entries 0))
          "VectorUploadCache requires :max-entries to be a positive integer")
  (assert (and (= (type evict-per-upload) :number)
               (= evict-per-upload (math.floor evict-per-upload))
               (> evict-per-upload 0))
          "VectorUploadCache requires :evict-per-upload to be a positive integer")
  (local entries {})
  (var entry-count 0)
  (var tick 0)

  (fn delete-entry [key entry]
    (when (and entry entry.vbo)
      (gl.glDeleteBuffers entry.vbo))
    (set (. entries key) nil)
    (set entry-count (math.max 0 (- entry-count 1))))

  (fn evict-one [current-key]
    (var oldest-key nil)
    (var oldest-entry nil)
    (each [key entry (pairs entries)]
      (when (and (not (= key current-key))
                 (or (not oldest-entry)
                     (< entry.last-used oldest-entry.last-used)))
        (set oldest-key key)
        (set oldest-entry entry)))
    (when oldest-entry
      (delete-entry oldest-key oldest-entry)
      true))

  (fn maybe-evict [current-key]
    (var evicted 0)
    (while (and (> entry-count max-entries)
                (< evicted evict-per-upload))
      (if (evict-one current-key)
          (set evicted (+ evicted 1))
          (set evicted evict-per-upload))))

  (fn ensure-entry [vector]
    (local existing (. entries vector))
    (if existing
        existing
        (do
          (local entry {:vbo (gl.glGenBuffers 1)
                        :uploaded-floats nil
                        :last-used 0})
          (set (. entries vector) entry)
          (set entry-count (+ entry-count 1))
          entry)))

  (fn upload [self vector configure-attributes]
    (local float-count (and vector (vector:length)))
    (when (and float-count (> float-count 0))
      (set tick (+ tick 1))
      (local entry (ensure-entry vector))
      (set entry.last-used tick)
      (gl.glBindBuffer target entry.vbo)
      (when configure-attributes
        (configure-attributes))
      (if (not (= float-count entry.uploaded-floats))
          (do
            (gl.bufferDataFromVectorBuffer vector target usage)
            (set entry.uploaded-floats float-count)
            (when (. vector :clear-dirty)
              (vector:clear-dirty)))
          (do
            (var dirty-from nil)
            (var dirty-to nil)
            (when (. vector :dirty-range)
              (local (from to) (vector:dirty-range))
              (set dirty-from from)
              (set dirty-to to))
            (when (and dirty-from dirty-to (> dirty-to dirty-from))
              (gl.bufferSubDataFromVectorBuffer
                vector
                target
                (* dirty-from 4)
                (* (- dirty-to dirty-from) 4))
              (when (. vector :clear-dirty)
                (vector:clear-dirty)))))
      (maybe-evict vector)
      entry))

  (fn drop [_self]
    (each [key entry (pairs entries)]
      (delete-entry key entry))
    (set entry-count 0))

  (fn stats [_self]
    {:entries entry-count
     :tick tick})

  {:upload upload
   :drop drop
   :stats stats})

VectorUploadCache
