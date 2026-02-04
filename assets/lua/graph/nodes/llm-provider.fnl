(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))

(fn LlmProviderNode [opts]
    (local options (or opts {}))
    (local key (or options.key "llm-provider"))
    (local label (or options.label "llm provider"))
    (GraphNode {:key key
                    :label label
                    :color (glm.vec4 0.2 0.7 0.6 1)
                    :sub-color (glm.vec4 0.1 0.6 0.5 1)}))

LlmProviderNode
