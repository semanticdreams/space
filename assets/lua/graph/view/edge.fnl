(local glm (require :glm))
(local Utils (require :graph/view/utils))

(fn new-triangle-line [ctx opts]
    (assert ctx "Graph edges require a build context")
    (local vector (and ctx ctx.triangle-vector))
    (assert vector "Graph edges require ctx.triangle-vector")
    (local options (or opts {}))
    (var color (Utils.ensure-glm-vec4 options.color (glm.vec4 0.4 0.4 0.4 1)))
    (local thickness (or options.thickness 2.0))
    (local depth-offset (or options.depth-offset -10.0))
    (local label (or options.label options.key "edge"))
    (var handle nil)

    (fn release-handle [self]
        (when handle
            (when (and ctx ctx.untrack-triangle-handle)
                (ctx:untrack-triangle-handle handle))
            (vector:delete handle)
            (set handle nil)
            (set self.handle nil)))

    (fn ensure-handle [self]
        (when (not handle)
            (set handle (vector:allocate 24))
            (set self.handle handle)))

    (fn write-vertex [_self index position]
        (local offset (* index 8))
        (vector:set-glm-vec3 handle offset position)
        (vector:set-glm-vec4 handle (+ offset 3) color)
        (vector:set-float handle (+ offset 7) depth-offset))

    (fn write-batch-data [self start-pos end-pos]
        (assert start-pos "Graph edge update missing start position")
        (assert end-pos "Graph edge update missing end position")
        (local delta (- end-pos start-pos))
        (local len (glm.length delta))
        (if (> len 0.0001)
            (do
                (ensure-handle self)
                (var perp (glm.vec3 (- delta.y) delta.x delta.z))
                (local perp-length (glm.length perp))
                (if (> perp-length 0.00001)
                    (set perp (glm.normalize perp))
                    (set perp (glm.vec3 0 0 0)))
                (local start-offset (* perp (* thickness 0.3)))
                (local v0 (- start-pos start-offset))
                (local v1 (+ start-pos start-offset))
                (local v2 end-pos)
                (local data [v0.x v0.y v0.z color.x color.y color.z color.w depth-offset
                             v1.x v1.y v1.z color.x color.y color.z color.w depth-offset
                             v2.x v2.y v2.z color.x color.y color.z color.w depth-offset])
                (when (and ctx ctx.track-triangle-handle)
                    (ctx:track-triangle-handle handle nil))
                (set self.start start-pos)
                (set self.finish end-pos)
                {:handle handle :vector vector :data data})
            (do
                (release-handle self)
                (set self.start start-pos)
                (set self.finish end-pos)
                nil)))

    (fn prepare-batch [self start-pos end-pos]
        (assert start-pos "Graph edge update missing start position")
        (assert end-pos "Graph edge update missing end position")
        (local delta (- end-pos start-pos))
        (local len (glm.length delta))
        (if (> len 0.0001)
            (do
                (ensure-handle self)
                (when (and ctx ctx.track-triangle-handle)
                    (ctx:track-triangle-handle handle nil)))
            (release-handle self))
        (set self.start start-pos)
        (set self.finish end-pos)
        handle)

    (fn update [self start-pos end-pos]
        (assert start-pos "Graph edge update missing start position")
        (assert end-pos "Graph edge update missing end position")
        (local delta (- end-pos start-pos))
        (local len (glm.length delta))
        (if (> len 0.0001)
            (do
                (ensure-handle self)
                (var perp (glm.vec3 (- delta.y) delta.x delta.z))
                (local perp-length (glm.length perp))
                (if (> perp-length 0.00001)
                    (set perp (glm.normalize perp))
                    (set perp (glm.vec3 0 0 0)))
                (local start-offset (* perp (* thickness 0.3)))
                (write-vertex self 0 (- start-pos start-offset))
                (write-vertex self 1 (+ start-pos start-offset))
                (write-vertex self 2 end-pos)
                (when (and ctx ctx.track-triangle-handle)
                    (ctx:track-triangle-handle handle nil)))
            (release-handle self))
        (set self.start start-pos)
        (set self.finish end-pos)
        self)

    (fn set-color [self new-color]
        (set color (Utils.ensure-glm-vec4 new-color color))
        (set self.color color)
        (when handle
            (for [i 0 2]
                (local offset (* i 8))
                (vector:set-glm-vec4 handle (+ offset 3) color)))
        self)

    (fn drop [self]
        (release-handle self))

    {:update update
     :build-vertex-data write-batch-data
     :prepare-batch prepare-batch
     :set-color set-color
     :drop drop
     :vector vector
     :color color
     :thickness thickness
     :depth-offset depth-offset
     :handle nil
     :start nil
     :finish nil
     :depth-offset-index depth-offset
     :clip-region nil})

{:new-triangle-line new-triangle-line}
