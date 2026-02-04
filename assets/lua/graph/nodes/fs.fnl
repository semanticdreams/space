(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local FsNodeView (require :graph/view/views/fs))
(local Signal (require :signal))
(local fs (require :fs))
(local logging (require :logging))

(local M {})

(fn normalize-path [path]
    (if (= (type path) :table)
        (or path.path (tostring path))
        path))

(fn safe-lower [text]
    (if text
        (string.lower text)
        ""))

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

    (set node.drop
         (fn [self]
             (when self.items-changed
                 (self.items-changed:clear))))

    node)

M
