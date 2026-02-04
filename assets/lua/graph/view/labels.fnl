(local glm (require :glm))
(local Utils (require :graph/view/utils))
(local NodeBase (require :graph/node-base))

(local ensure-glm-vec4 Utils.ensure-glm-vec4)
(local truncate-with-ellipsis Utils.truncate-with-ellipsis)
(local wrap-text Utils.wrap-text)
(local node-id NodeBase.node-id)
(local Text (require :text))
(local TextStyle (require :text-style))

(fn GraphViewLabels [opts]
    (local options (or opts {}))
    (local ctx options.ctx)
    (local label-color (ensure-glm-vec4 options.label-color (glm.vec4 0.6 0.6 0.6 1)))
    (local label-depth-offset (or options.label-depth-offset 1.0))
    (local camera options.camera)
    (var last-camera-position nil)
    (var camera-dirty? false)
    (var camera-handler nil)
    (local labels {})
    (local node-lod {})

    (fn label-settings [lod]
        (if (= lod 0)
            {:text-length 120 :line-length 30 :scale 3}
            (= lod 1)
            {:text-length 60 :line-length 20 :scale 5}
            (= lod 2)
            {:text-length 20 :line-length nil :scale 8}
            nil))

    (fn label-target [distance]
        (if (< distance 250.0)
            0
            (< distance 500.0)
            1
            (< distance 800.0)
            2
            3))

    (fn current-camera-position []
        (and camera camera.position))

    (when (and camera camera.debounced-changed)
        (set camera-handler
             (camera.debounced-changed:connect
               (fn [payload]
                   (local pos (and payload payload.position))
                   (when pos
                       (set last-camera-position pos)
                       (set camera-dirty? true))))))

    (fn label-text [node settings]
        (local base (or node.label (node-id node)))
        (local truncated (truncate-with-ellipsis base settings.text-length))
        (if settings.line-length
            (wrap-text truncated settings.line-length)
            truncated))

    (fn place-label [span point]
        (when (and span point)
            (local measure (or span.layout.measure (glm.vec3 0 0 0)))
            (local half-point (/ (or point.size 0.0) 2.0))
            (local offset (glm.vec3 (- (/ measure.x 2.0))
                                (- (+ half-point 1.0 measure.y))
                                0.05))
            (set span.layout.depth-offset-index label-depth-offset)
            (set span.layout.position (+ point.position offset))
            (set span.layout.rotation (glm.quat 1 0 0 0))
            (span.layout:layouter)))

    (fn drop-label [node]
        (local span (. labels node))
        (when span
            (span:drop))
        (set (. labels node) nil)
        (set (. node-lod node) nil))

    (fn update-node-label [node point camera-pos force?]
        (local distance (glm.length (- point.position camera-pos)))
        (local target (label-target distance))
        (local current (. node-lod node))
        (when (or force? (not (= target current)))
            (if (< target 3)
                (do
                    (local settings (label-settings target))
                    (local text (label-text node settings))
                    (local existing (. labels node))
                    (var span existing)
                    (if span
                        (do
                            (span:set-text text {:mark-measure-dirty? true})
                            (set span.style.scale settings.scale))
                        (do
                            (local builder (Text {:text text
                                                  :style (TextStyle {:color label-color
                                                                     :scale settings.scale})}))
                            (set span (builder ctx))
                            (set (. labels node) span)))
                    (span.layout:measurer)
                    (place-label span point))
                (drop-label node))
            (set (. node-lod node) target)))

    (fn update [_self points nodes opts]
        (local camera-pos (current-camera-position))
        (when camera-pos
            (local force? (or (and opts opts.force?) false))
            (var should-run force?)
            (when (not should-run)
                (set should-run (or camera-dirty? (not last-camera-position))))
            (when should-run
                (set camera-dirty? false)
                (when force?
                    (set last-camera-position camera-pos))
                (when (not last-camera-position)
                    (set last-camera-position camera-pos))
                (local effective-pos (or last-camera-position camera-pos))
                (if nodes
                    (each [_ node (ipairs nodes)]
                        (local point (. points node))
                        (when point
                            (update-node-label node point effective-pos force?)))
                    (each [node point (pairs points)]
                        (update-node-label node point effective-pos force?))))))

    (fn refresh-positions [_self points nodes]
        (local targets (or nodes []))
        (when (not nodes)
            (each [node _ (pairs labels)]
                (table.insert targets node)))
        (each [_ node (ipairs targets)]
            (local span (. labels node))
            (local point (. points node))
            (when (and span point)
                (place-label span point))))

    (fn drop-node [_self node]
        (drop-label node))

    (fn drop-all [_self]
        (each [node span (pairs labels)]
            (when span
                (span:drop))
            (set (. labels node) nil)
            (set (. node-lod node) nil))
        (set last-camera-position nil)
        (set camera-dirty? false)
        (when (and camera camera-handler)
            (camera.debounced-changed:disconnect camera-handler true)
            (set camera-handler nil)))

    (fn move-label [_self existing node]
        (when (. labels existing)
            (set (. labels node) (. labels existing))
            (set (. labels existing) nil))
        (when (. node-lod existing)
            (set (. node-lod node) (. node-lod existing))
            (set (. node-lod existing) nil)))

    (local self {:update update
                 :refresh-positions refresh-positions
                 :drop-node drop-node
                 :drop-all drop-all
                 :move-label move-label
                 :labels labels
                 :node-lod node-lod})
    self)

GraphViewLabels
