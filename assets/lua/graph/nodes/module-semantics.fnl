(local {:GraphEdge GraphEdge} (require :graph/edge))
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

(fn make-parent-dir-node [self]
    (local parent (and fs.parent (fs.parent self.path)))
    (if parent
        (do
            (local CodeDirNode (require :graph/nodes/code-dir))
            (CodeDirNode {:path parent
                          :root (or self.project-root parent)
                          :label parent}))
        nil))

(fn apply-module-semantics [node opts]
    (local options (or opts {}))
    (local path (normalize-path (or options.path options.module-path)))
    (assert path "module semantics requires path")
    (local absolute-path (if (and path fs.absolute)
                             (fs.absolute path)
                             path))
    (local project-root (normalize-path (or options.project-root (default-project-root))))
    (set node.kind options.kind)
    (set node.path absolute-path)
    (set node.project-root project-root)
    (set node.items-changed (Signal))

    (set node.read-source
         (fn [self]
             (local (ok content) (pcall fs.read-file self.path))
             (if ok
                 content
                 (do
                     (logging.warn (.. "Module failed reading " self.path ": " content))
                     nil))))

    (set node.collect-items (or options.collect-items
                                (fn [_self] [])))

    (set node.emit-items
         (fn [self]
             (local items (self:collect-items))
             (self.items-changed:emit items)
             items))

    (set node.resolve-child-node options.resolve-child-node)

    (set node.open-entry
         (fn [self entry]
             (local graph self.graph)
             (local item (if (= (type entry) :table)
                             (or entry (. entry 1) entry)
                             entry))
             (local resolver self.resolve-child-node)
             (when (and graph resolver item)
                 (local child (resolver self item))
                 (when child
                     (graph:add-edge (GraphEdge {:source self
                                                 :target child}))
                     child))))

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
             (local parent-node (make-parent-dir-node self))
             (when parent-node
                 (table.insert actions 2
                               {:name "Open Parent Dir"
                                :fn (fn [_button _event]
                                        (local graph self.graph)
                                        (when graph
                                            (graph:add-edge (GraphEdge {:source self
                                                                        :target parent-node}))))}))
             (each [_ action (ipairs (or (and options options.extra-actions
                                              (options.extra-actions self)) []))]
                 (table.insert actions action))
             actions))

    (set node.drop
         (fn [self]
             (when self.items-changed
                 (self.items-changed:clear))))

    node)

{:normalize-path normalize-path
 :default-project-root default-project-root
 :display-label display-label
 :apply-module-semantics apply-module-semantics}
