(local glm (require :glm))
(local Utils (require :graph/core/utils))

(fn GraphEdge [opts]
    (local options (or opts {}))
    {:source options.source
     :target options.target
     :label (or options.label "")
     :color (Utils.ensure-glm-vec4 options.color (glm.vec4 0.35 0.35 0.35 1))})

{:GraphEdge GraphEdge}
