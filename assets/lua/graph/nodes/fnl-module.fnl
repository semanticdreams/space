(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local FnlModuleNodeView (require :graph/view/views/fnl-module))
(local Signal (require :signal))
(local ExternalEditor (require :external-editor))
(local fs (require :fs))
(local logging (require :logging))

(fn normalize-path [path]
    (if (= (type path) :table)
        (or path.path (tostring path))
        path))

(fn default-root []
    (if (and app app.engine app.engine.get-asset-path)
        (app.engine.get-asset-path "lua")
        (if (and fs fs.cwd fs.join-path)
            (fs.join-path (fs.cwd) "assets" "lua")
            "assets/lua")))

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

(fn display-label [path root]
    (if (and path root)
        (do
            (local prefix (.. root "/"))
            (if (= (string.sub path 1 (string.len prefix)) prefix)
                (string.sub path (+ (string.len prefix) 1))
                path))
        path))

(fn FnlModuleNode [opts]
    (local options (or opts {}))
    (local root (normalize-path (or options.lua-root (default-root))))
    (local path (normalize-path (or options.path options.module-path)))
    (assert path "FnlModuleNode requires path")
    (local absolute-path (if (and path fs.absolute)
                             (fs.absolute path)
                             path))
    (local key (or options.key (.. "fnl-module:" absolute-path)))
    (local label (or options.label (display-label absolute-path root)))
    (local node (GraphNode {:key key
                            :label label
                            :color (glm.vec4 0.7 0.45 0.8 1)
                            :sub-color (glm.vec4 0.6 0.35 0.7 1)
                            :size 8.0
                            :view FnlModuleNodeView}))
    (set node.kind "fnl-module")
    (set node.path absolute-path)
    (set node.lua-root root)
    (set node.items-changed (Signal))

    (set node.read-source
         (fn [self]
             (local (ok content) (pcall fs.read-file self.path))
             (if ok
                 content
                 (do
                     (logging.warn (.. "FnlModuleNode failed reading " self.path ": " content))
                     nil))))

    (set node.collect-items
         (fn [self]
             (local source (self:read-source))
             (local requires (parse-requires source))
             (local items [])
             (each [_ module-name (ipairs requires)]
                 (local dependency-path (resolve-module-path self.lua-root module-name))
                 (when dependency-path
                     (table.insert items [{:module module-name
                                           :path dependency-path}
                                          module-name])))
             items))

    (set node.emit-items
         (fn [self]
             (local items (self:collect-items))
             (self.items-changed:emit items)
             items))

    (set node.open-entry
         (fn [self entry]
             (local graph self.graph)
             (local item (if (= (type entry) :table)
                             (or entry (. entry 1) entry)
                             entry))
             (local path (and item item.path))
             (when (and graph path)
                 (local child (FnlModuleNode {:path path
                                              :lua-root self.lua-root}))
                 (graph:add-edge (GraphEdge {:source self
                                             :target child})))))

    (set node.actions
         (fn [self]
             (local actions
                    [{:name "Refresh"
                      :icon "refresh"
                      :fn (fn [_button _event]
                              (self:emit-items))}])
             (local stat (and fs.stat (fs.stat self.path)))
             (when (and stat stat.exists stat.is-file)
                 (table.insert actions 2
                               {:name "Edit"
                                :icon "edit"
                                :fn (fn [_button _event]
                                        (ExternalEditor.open-file self.path (fn [] nil)))}))
             actions))

    (set node.drop
         (fn [self]
             (when self.items-changed
                 (self.items-changed:clear))))

    node)

FnlModuleNode
