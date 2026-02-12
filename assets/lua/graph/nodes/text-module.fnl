(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local TextModuleNodeView (require :graph/view/views/text-module))
(local ModuleSemantics (require :graph/nodes/module-semantics))
(local fs (require :fs))

(fn normalize-relative-path [path]
    (if (and path (string.find path "^%./"))
        (string.sub path 3)
        path))

(fn collect-path-references [source]
    (local refs {})
    (when source
        (each [path (string.gmatch source "%]%(([^%)]+)%)")]
            (when (and path
                       (not (string.find path "^https?://"))
                       (not (string.find path "^mailto:"))
                       (not (string.find path "^#")))
                (set (. refs (normalize-relative-path path)) true)))
        (each [path (string.gmatch source "\"([%w%._/%-]+%.[%w_]+)\"")]
            (set (. refs (normalize-relative-path path)) true)))
    (local items [])
    (each [path _ (pairs refs)]
        (table.insert items path))
    (table.sort items)
    items)

(fn resolve-ref-path [self ref]
    (when ref
        (local base-dir (and fs.parent (fs.parent self.path)))
        (local candidate (and base-dir fs.join-path (fs.join-path base-dir ref)))
        (local stat (and candidate fs.stat (fs.stat candidate)))
        (if (and stat stat.exists stat.is-file)
            (if fs.absolute
                (fs.absolute candidate)
                candidate)
            nil)))

(fn TextModuleNode [opts]
    (local options (or opts {}))
    (local path (ModuleSemantics.normalize-path (or options.path options.module-path)))
    (assert path "TextModuleNode requires path")
    (local absolute-path (if (and path fs.absolute)
                             (fs.absolute path)
                             path))
    (local root (ModuleSemantics.normalize-path
                    (or options.project-root
                        options.root
                        (ModuleSemantics.default-project-root))))
    (local key (or options.key (.. "text-module:" absolute-path)))
    (local label (or options.label (ModuleSemantics.display-label absolute-path root)))
    (local node (GraphNode {:key key
                            :label label
                            :color (glm.vec4 0.7 0.7 0.45 1)
                            :sub-color (glm.vec4 0.6 0.6 0.35 1)
                            :size 8.0
                            :view TextModuleNodeView}))

    (local semantics
        {:kind "text-module"
         :path absolute-path
         :project-root root
         :collect-items (fn [self]
                            (local source (self:read-source))
                            (local refs (collect-path-references source))
                            (local items [])
                            (each [_ ref (ipairs refs)]
                                (local ref-path (resolve-ref-path self ref))
                                (when ref-path
                                    (table.insert items [{:name ref
                                                          :path ref-path}
                                                         ref])))
                            items)
         :resolve-child-node (fn [self item]
                                 (local path (and item item.path))
                                 (when path
                                     (TextModuleNode {:path path
                                                      :project-root self.project-root})))})

    (ModuleSemantics.apply-module-semantics node semantics)

    node)

TextModuleNode
