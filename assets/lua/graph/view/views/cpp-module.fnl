(local ModuleNodeView (require :graph/view/views/module))

(fn CppModuleNodeView [node opts]
    (local options (or opts {}))
    (ModuleNodeView node {:name "cpp-module-node-view"
                          :node (or options.node node)
                          :items (or options.items [])
                          :ctx options.ctx}))

CppModuleNodeView
