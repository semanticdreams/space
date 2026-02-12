(local ModuleNodeView (require :graph/view/views/module))

(fn TextModuleNodeView [node opts]
    (local options (or opts {}))
    (ModuleNodeView node {:name "text-module-node-view"
                          :node (or options.node node)
                          :items (or options.items [])
                          :ctx options.ctx}))

TextModuleNodeView
