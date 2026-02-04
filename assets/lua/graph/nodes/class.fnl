(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))

(fn ClassNode [cls-data]
    (local label (or (and cls-data cls-data.name) "class"))
    (local key (or (and cls-data cls-data.id) label))
    (GraphNode {:key (.. "class:" key)
                    :label label
                    :color (glm.vec4 1 0.4 0 1)
                    :sub-color (glm.vec4 1 0.4 0 1)}))

ClassNode
