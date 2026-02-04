(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local QuitNodeView (require :graph/view/views/quit))
(local logging (require :logging))

(fn QuitNode [opts]
    (local node (GraphNode {:key (or (and opts opts.key) "quit")
                                :label "quit"
                                :color (glm.vec4 0.8 0.1 0.1 1)
                                :sub-color (glm.vec4 1 0.2 0.2 1)
                                :view QuitNodeView}))
    (set node.on-quit (and opts opts.on-quit))
    (set node.activate
        (fn [_self]
            (local handler node.on-quit)
            (if (and handler (= (type handler) :function))
                (handler)
                (logging.info "[graph] quit requested"))))
    node)

QuitNode
