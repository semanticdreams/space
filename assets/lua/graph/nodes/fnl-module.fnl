(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local FnlModuleNodeView (require :graph/view/views/fnl-module))
(local ModuleSemantics (require :graph/nodes/module-semantics))
(local fs (require :fs))

(fn safe-module-segment [module-name]
    (string.gsub module-name "%." "/"))

(fn resolve-module-path [root module-name]
    (local segment (safe-module-segment module-name))
    (local file-path (and fs.join-path (fs.join-path root (.. segment ".fnl"))))
    (local init-path (and fs.join-path (fs.join-path root segment "init.fnl")))
    (local file-stat (and file-path fs.stat (fs.stat file-path)))
    (if (and file-stat file-stat.exists file-stat.is-file)
        file-path
        (do
            (local init-stat (and init-path fs.stat (fs.stat init-path)))
            (if (and init-stat init-stat.exists init-stat.is-file)
                init-path
                nil))))

(fn parse-requires [source]
    (local modules {})
    (when source
        (each [module (string.gmatch source "require%s+:%s*([%w%._/%-]+)")]
            (set (. modules module) true))
        (each [module (string.gmatch source "require%s+\"([%w%._/%-]+)\"")]
            (set (. modules module) true)))
    (local list [])
    (each [module _ (pairs modules)]
        (table.insert list module))
    (table.sort list)
    list)

(fn default-root []
    (if (and app app.engine app.engine.get-asset-path)
        (app.engine.get-asset-path "lua")
        (if (and fs fs.cwd fs.join-path)
            (fs.join-path (fs.cwd) "assets" "lua")
            "assets/lua")))

(fn FnlModuleNode [opts]
    (local options (or opts {}))
    (local root (ModuleSemantics.normalize-path (or options.lua-root
                                                    options.root
                                                    (default-root))))
    (local path (ModuleSemantics.normalize-path (or options.path options.module-path)))
    (assert path "FnlModuleNode requires path")
    (local absolute-path (if (and path fs.absolute)
                             (fs.absolute path)
                             path))
    (local key (or options.key (.. "fnl-module:" absolute-path)))
    (local label (or options.label (ModuleSemantics.display-label absolute-path root)))
    (local node (GraphNode {:key key
                            :label label
                            :color (glm.vec4 0.7 0.45 0.8 1)
                            :sub-color (glm.vec4 0.6 0.35 0.7 1)
                            :size 8.0
                            :view FnlModuleNodeView}))
    (set node.lua-root root)

    (local semantics
        {:kind "fnl-module"
         :path absolute-path
         :project-root root
         :collect-items (fn [self]
                            (local source (self:read-source))
                            (local requires (parse-requires source))
                            (local items [])
                            (each [_ module-name (ipairs requires)]
                                (local dependency-path (resolve-module-path self.project-root module-name))
                                (when dependency-path
                                    (table.insert items [{:module module-name
                                                          :path dependency-path}
                                                         module-name])))
                            items)
         :resolve-child-node (fn [self item]
                                 (local path (and item item.path))
                                 (when path
                                     (FnlModuleNode {:path path
                                                     :lua-root self.project-root})))})

    (ModuleSemantics.apply-module-semantics node semantics)

    node)

FnlModuleNode
