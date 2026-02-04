(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))

(fn LlmModelNode [opts]
    (local options (or opts {}))
    (local key (or options.key "llm-model"))
    (local label (or options.label "llm model"))
    (GraphNode {:key key
                    :label label
                    :color (glm.vec4 0.2 0.7 0.6 1)
                    :sub-color (glm.vec4 0.1 0.6 0.5 1)}))

LlmModelNode
