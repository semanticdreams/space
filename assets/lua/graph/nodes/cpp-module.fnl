(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local CppModuleNodeView (require :graph/view/views/cpp-module))
(local ModuleSemantics (require :graph/nodes/module-semantics))
(local fs (require :fs))

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
                        [self.project-root
                         (and self.project-root fs.join-path
                              (fs.join-path self.project-root "src"))
                         (and self.project-root fs.join-path
                              (fs.join-path self.project-root "apps"))
                         (and self.project-root fs.join-path
                              (fs.join-path self.project-root "include"))]))
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
    (local path (ModuleSemantics.normalize-path (or options.path options.module-path)))
    (assert path "CppModuleNode requires path")
    (local absolute-path (if (and path fs.absolute)
                             (fs.absolute path)
                             path))
    (local root (ModuleSemantics.normalize-path
                    (or options.project-root
                        options.root
                        (ModuleSemantics.default-project-root))))
    (local key (or options.key (.. "cpp-module:" absolute-path)))
    (local label (or options.label (ModuleSemantics.display-label absolute-path root)))
    (local node (GraphNode {:key key
                            :label label
                            :color (glm.vec4 0.35 0.6 0.85 1)
                            :sub-color (glm.vec4 0.25 0.5 0.75 1)
                            :size 8.0
                            :view CppModuleNodeView}))

    (local semantics
        {:kind "cpp-module"
         :path absolute-path
         :project-root root
         :collect-items (fn [self]
                            (local source (self:read-source))
                            (local includes (parse-includes source))
                            (local items [])
                            (each [_ include-entry (ipairs includes)]
                                (local include-path (resolve-include-path self include-entry))
                                (when include-path
                                    (table.insert items [{:name include-entry.name
                                                          :path include-path}
                                                         include-entry.name])))
                            items)
         :resolve-child-node (fn [self item]
                                 (local path (and item item.path))
                                 (when path
                                     (CppModuleNode {:path path
                                                     :project-root self.project-root})))})

    (ModuleSemantics.apply-module-semantics node semantics)

    (set node.resolve-include-path resolve-include-path)
    node)

CppModuleNode
