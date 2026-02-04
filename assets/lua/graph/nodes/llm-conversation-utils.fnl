(fn find-parent-node [graph node]
    (var parent nil)
    (each [_ edge (ipairs graph.edges)]
        (when (= edge.target node)
            (if parent
                (error (.. "Graph node has multiple parents: " (tostring node.key)))
                (set parent edge.source))))
    parent)

(fn find-conversation-node [graph node]
    (var current node)
    (var visited {})
    (var convo nil)
    (while current
        (when (rawget visited current)
            (error "Detected a cycle while searching for conversation"))
        (set (. visited current) true)
        (if (= current.kind "llm-conversation")
            (do
                (set convo current)
                (set current nil))
            (set current (find-parent-node graph current))))
    (assert convo "Missing conversation root for llm item")
    convo)

(fn resolve-conversation-record [node opts]
    (local options (or opts {}))
    (if node.graph
        (find-conversation-node node.graph node)
        (or options.conversation
            (and node.store node.llm-id node.store.find-conversation-for-item
                 (node.store:find-conversation-for-item node.llm-id)))))

{:find-conversation-node find-conversation-node
 :resolve-conversation-record resolve-conversation-record}
