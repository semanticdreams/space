(local Utils (require :graph/core/utils))


(fn GraphEdge [opts]
    (local options (or opts {}))
    (local edge {:source options.source
                 :target options.target
                 :label (or options.label "")})
    (when (not (= options.color nil))
        (set edge.color (Utils.ensure-glm-vec4 options.color)))
    edge)

{:GraphEdge GraphEdge}
