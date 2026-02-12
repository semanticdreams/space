(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local FsNodeView (require :graph/view/views/fs))
(local CodeDirNode (require :graph/nodes/code-dir))
(local Signal (require :signal))
(local fs (require :fs))
(local logging (require :logging))
(local ExternalEditor (require :external-editor))

(local M {})

(fn normalize-path [path]
    (if (= (type path) :table)
        (or path.path (tostring path))
        path))

(fn safe-lower [text]
    (if text
        (string.lower text)
        ""))

(fn fnl-path? [path]
    (and path (string.match (safe-lower path) "%.fnl$")))

(fn cpp-path? [path]
    (and path
         (or (string.match (safe-lower path) "%.cpp$")
             (string.match (safe-lower path) "%.cc$")
             (string.match (safe-lower path) "%.cxx$")
             (string.match (safe-lower path) "%.h$")
             (string.match (safe-lower path) "%.hpp$")
             (string.match (safe-lower path) "%.hh$"))))

(fn M.resolve-path [self path]
    (normalize-path (or path self)))

(fn M.default-path []
    (if (and fs fs.cwd)
        (fs.cwd)
        "."))

(fn M.FsNode [opts]
    (assert (and fs fs.list-dir) "FsNode requires the fs module")
    (local options (or opts {}))
    (local path (M.resolve-path (or options.path (M.default-path))))
    (local label (or options.label path))
    (local base-key (.. "fs:" path))
    (local key
        (if options.key
            (do
                (local candidate (tostring options.key))
                (if (and candidate (string.find candidate path 1 true))
                    candidate
                    (.. candidate ":" path)))
            base-key))
    (local node (GraphNode {:key key
                                :label label
                                :color (glm.vec4 0.3 0.6 1.0 1)
                                :sub-color (glm.vec4 0.15 0.45 0.9 1)
                                :size 9.0
                                :view FsNodeView}))
    (set node.path path)
    (set node.resolve-path M.resolve-path)
    (set node.include-hidden? false)
    (set node.create-child-node
         (fn [_self new-path]
             (M.FsNode {:path new-path})))
    (set node.items-changed (Signal))

    (set node.list-directory
         (fn [self path]
             (local (ok entries) (pcall fs.list-dir path self.include-hidden?))
             (if ok
                 entries
                 (do
                     (logging.warn (.. "FsNode failed to list " path ": " entries))
                     []))))

    (set node.parent-path
         (fn [_self path]
             (if (not path)
                 nil
                 (do
                     (local parent (fs.parent path))
                     (if (or (= parent nil)
                             (= parent "")
                             (= parent path))
                         nil
                         parent)))))

    (set node.normalize-entry
         (fn [_self entry]
             {:name entry.name
              :path entry.path
              :is-dir (and entry.is-dir true)
              :is-file (and entry.is-file true)
              :is-up? (and entry.is-up? true)}))

    (set node.make-parent-entry
         (fn [self current]
             (local parent (self:parent-path current))
             (if parent
                 {:name ".."
                  :path parent
                  :is-dir true
                  :is-file false
                  :is-up? true}
                 nil)))

    (set node.entry-label
         (fn [_self entry]
             (if entry.is-dir
                 (.. entry.name "/")
                 entry.name)))

    (set node.sort-entries
         (fn [_self entries]
             (table.sort entries
                 (fn [a b]
                     (local a-dir (and a.is-dir (not a.is-up?)))
                     (local b-dir (and b.is-dir (not b.is-up?)))
                     (if (= a-dir b-dir)
                         (< (safe-lower a.name) (safe-lower b.name))
                         a-dir)))
             entries))

    (set node.build-items
         (fn [self current-path]
             (local entries [])
             (local listed (self:list-directory current-path))
             (each [_ entry (ipairs listed)]
                 (table.insert entries (self:normalize-entry entry)))
             (self:sort-entries entries)
             (local parent-entry (self:make-parent-entry current-path))
             (when parent-entry
                 (table.insert entries 1 parent-entry))
             (icollect [_ entry (ipairs entries)]
                 [entry (self:entry-label entry)])))

    (set node.emit-items
         (fn [self]
             (local items (self:build-items self.path))
             (when self.items-changed
                 (self.items-changed:emit items))
             items))

    (set node.open-entry
         (fn [self entry]
             (when entry
                 (local graph self.graph)
                 (assert graph "FsNode requires a mounted graph to add edges")
                 (assert entry.path "FsNode entries require a path")
                 (assert self.create-child-node "FsNode missing create-child-node")
                 (local resolved (self:resolve-path entry.path))
                 (local child (self:create-child-node resolved))
                 (graph:add-edge (GraphEdge {:source self
                                                 :target child})))))

    (set node.open-code-dir
         (fn [self]
             (local graph self.graph)
             (assert graph "FsNode requires a mounted graph to open code-dir")
             (local resolved-path (and self.path fs.absolute (fs.absolute self.path)))
             (assert resolved-path "FsNode requires a path to open code-dir")
             (local stat (and fs.stat (fs.stat resolved-path)))
             (when (and stat stat.exists stat.is-dir)
                 (local code-node (CodeDirNode {:path resolved-path
                                                :root resolved-path}))
                 (graph:add-edge (GraphEdge {:source self
                                             :target code-node}))
                 code-node)))

    (set node.create-module-node
         (fn [_self module-kind module-path]
             (if (= module-kind :fnl)
                 (do
                     (local FnlModuleNode (require :graph/nodes/fnl-module))
                     (local lua-root
                            (if (and app app.engine app.engine.get-asset-path)
                                (app.engine.get-asset-path "lua")
                                (and fs.cwd fs.join-path (fs.join-path (fs.cwd) "assets" "lua"))))
                     (FnlModuleNode {:path module-path
                                     :lua-root lua-root}))
                 (if (= module-kind :cpp)
                     (do
                         (local CppModuleNode (require :graph/nodes/cpp-module))
                         (CppModuleNode {:path module-path
                                         :project-root (if fs.cwd (fs.cwd) ".")}))
                     (if (= module-kind :text)
                         (do
                             (local TextModuleNode (require :graph/nodes/text-module))
                             (TextModuleNode {:path module-path
                                              :project-root (if fs.cwd (fs.cwd) ".")}))
                         nil)))))

    (set node.open-module-node
         (fn [self module-kind]
             (local graph self.graph)
             (assert graph "FsNode requires a mounted graph to open module nodes")
             (local resolved-path (and self.path fs.absolute (fs.absolute self.path)))
             (assert resolved-path "FsNode requires a path to open module nodes")
             (local module-node (self:create-module-node module-kind resolved-path))
             (when module-node
                 (graph:add-edge (GraphEdge {:source self
                                             :target module-node}))
                 module-node)))

    (set node.actions
         (fn [self]
             (local actions
                    [{:name "Refresh"
                      :icon "refresh"
                      :fn (fn [_button _event]
                              (self:emit-items))}
                     {:name "Show Hidden"
                      :icon "visibility"
                      :fn (fn [_button _event]
                              (set self.include-hidden? true)
                              (self:emit-items))}
                     {:name "Hide Hidden"
                      :icon "visibility_off"
                      :fn (fn [_button _event]
                              (set self.include-hidden? false)
                              (self:emit-items))}])
             (local resolved-path (and self.path fs.absolute (fs.absolute self.path)))
             (local stat (and resolved-path fs.stat (fs.stat resolved-path)))
             (when (and stat stat.exists stat.is-dir)
                 (table.insert actions 2
                               {:name "Open as Code Graph"
                                :icon "code"
                                :fn (fn [_button _event]
                                        (self:open-code-dir))}))
             (when (and stat stat.exists stat.is-file)
                 (table.insert actions 2
                               {:name "Edit"
                                :icon "edit"
                                :fn (fn [_button _event]
                                        (ExternalEditor.open-file resolved-path (fn [] nil)))}))
             (when (and stat stat.exists stat.is-file resolved-path (fnl-path? resolved-path))
                 (table.insert actions 2
                               {:name "Open as Fennel Module"
                                :icon "code"
                                :fn (fn [_button _event]
                                        (self:open-module-node :fnl))}))
             (when (and stat stat.exists stat.is-file resolved-path (cpp-path? resolved-path))
                 (table.insert actions 2
                               {:name "Open as C++ Module"
                                :icon "code"
                                :fn (fn [_button _event]
                                        (self:open-module-node :cpp))}))
             (when (and stat stat.exists stat.is-file resolved-path
                        (not (fnl-path? resolved-path))
                        (not (cpp-path? resolved-path)))
                 (table.insert actions 2
                               {:name "Open as Text Module"
                                :icon "code"
                                :fn (fn [_button _event]
                                        (self:open-module-node :text))}))
             actions))

    (set node.drop
         (fn [self]
             (when self.items-changed
                 (self.items-changed:clear))))

    node)

M
