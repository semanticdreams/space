(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local CppModuleNodeView (require :graph/view/views/cpp-module))
(local Signal (require :signal))
(local ExternalEditor (require :external-editor))
(local fs (require :fs))
(local logging (require :logging))

(fn normalize-path [path]
    (if (= (type path) :table)
        (or path.path (tostring path))
        path))

(fn default-project-root []
    (if (and fs fs.cwd)
        (fs.cwd)
        "."))

(fn display-label [path root]
    (if (and path root)
        (do
            (local prefix (.. root "/"))
            (if (= (string.sub path 1 (string.len prefix)) prefix)
                (string.sub path (+ (string.len prefix) 1))
                path))
        path))

(fn unique-sorted [items]
    (local seen {})
    (local out [])
    (each [_ item (ipairs items)]
        (when (and item (not (. seen item)))
            (set (. seen item) true)
            (table.insert out item)))
    (table.sort out)
    out)

(fn parse-includes [source]
    (local includes [])
    (when source
        (each [value (string.gmatch source "#include%s*\"([^\"]+)\"")]
            (table.insert includes {:name value :quoted? true}))
        (each [value (string.gmatch source "#include%s*<([^>]+)>")]
            (table.insert includes {:name value :quoted? false})))
    includes)

(fn resolve-include-path [self include-entry]
    (local include-name (and include-entry include-entry.name))
    (when include-name
        (local current-dir (and fs.parent (fs.parent self.path)))
        (local roots (unique-sorted
                        [(and self.project-root self.project-root)
                         (and self.project-root fs.join-path (fs.join-path self.project-root "src"))
                         (and self.project-root fs.join-path (fs.join-path self.project-root "apps"))
                         (and self.project-root fs.join-path (fs.join-path self.project-root "include"))]))
        (local candidates [])
        (when (and include-entry.quoted? current-dir fs.join-path)
            (table.insert candidates (fs.join-path current-dir include-name)))
        (each [_ root (ipairs roots)]
            (when (and root fs.join-path)
                (table.insert candidates (fs.join-path root include-name))))
        (var resolved nil)
        (each [_ candidate (ipairs candidates)]
            (when (not resolved)
                (local stat (and candidate fs.stat (fs.stat candidate)))
                (when (and stat stat.exists stat.is-file)
                    (set resolved (if fs.absolute (fs.absolute candidate) candidate)))))
        resolved))

(fn CppModuleNode [opts]
    (local options (or opts {}))
    (local path (normalize-path (or options.path options.module-path)))
    (assert path "CppModuleNode requires path")
    (local absolute-path (if (and path fs.absolute)
                             (fs.absolute path)
                             path))
    (local project-root (normalize-path (or options.project-root (default-project-root))))
    (local key (or options.key (.. "cpp-module:" absolute-path)))
    (local label (or options.label (display-label absolute-path project-root)))
    (local node (GraphNode {:key key
                            :label label
                            :color (glm.vec4 0.35 0.6 0.85 1)
                            :sub-color (glm.vec4 0.25 0.5 0.75 1)
                            :size 8.0
                            :view CppModuleNodeView}))
    (set node.kind "cpp-module")
    (set node.path absolute-path)
    (set node.project-root project-root)
    (set node.items-changed (Signal))

    (set node.read-source
         (fn [self]
             (local (ok content) (pcall fs.read-file self.path))
             (if ok
                 content
                 (do
                    (logging.warn (.. "CppModuleNode failed reading " self.path ": " content))
                    nil))))

    (set node.collect-items
         (fn [self]
             (local source (self:read-source))
             (local includes (parse-includes source))
             (local items [])
             (each [_ include-entry (ipairs includes)]
                (local path (self:resolve-include-path include-entry))
                (when path
                    (table.insert items [{:name include-entry.name
                                          :path path}
                                         include-entry.name])))
             items))

    (set node.emit-items
         (fn [self]
             (local items (self:collect-items))
             (self.items-changed:emit items)
             items))

    (set node.resolve-include-path resolve-include-path)

    (set node.open-entry
         (fn [self entry]
             (local graph self.graph)
             (local item (if (= (type entry) :table)
                             (or entry (. entry 1) entry)
                             entry))
             (local path (and item item.path))
             (when (and graph path)
                 (local child (CppModuleNode {:path path
                                              :project-root self.project-root}))
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

CppModuleNode
