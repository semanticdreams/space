(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local FsFileViewerNodeView (require :graph/view/views/fs-file-viewer))
(local Signal (require :signal))
(local ExternalEditor (require :external-editor))
(local fs (require :fs))

(local default-window-size 65536)

(fn noop [] nil)

(fn defaulted-table [value]
  (if (= value nil) {} value))

(fn defaulted-window-size [value]
  (if (= value nil) default-window-size value))

(fn defaulted-offset [value]
  (if (= value nil) 0 value))

(fn defaulted-callback [value]
  (if (= value nil) noop value))

(fn assert-existing-file [path]
  (assert (and (= (type path) :string) (> (length path) 0))
          "FsFileViewerNode requires an existing file path")
  (local stat (and fs.stat (fs.stat path)))
  (assert (and stat stat.exists stat.is-file)
          "FsFileViewerNode requires an existing file path"))

(fn load-window [self offset]
  (local requested (defaulted-offset offset))
  (local window (fs.read-text-window self.path requested self.window-size))
  (set self.window window)
  (set self.offset (defaulted-offset window.offset))
  (self.window-changed:emit window)
  window)

(fn next-window [self]
  (if (not self.window)
      (self:load-window 0)
      (if (and (not self.window.eof)
               self.window.next-offset
               (not (= self.window.next-offset self.offset)))
          (do
            (table.insert self.previous-offsets self.offset)
            (self:load-window self.window.next-offset))
          self.window)))

(fn previous-window [self]
  (local count (length self.previous-offsets))
  (if (> count 0)
      (do
        (local previous-offset (. self.previous-offsets count))
        (tset self.previous-offsets count nil)
        (self:load-window previous-offset))
      self.window))

(fn refresh-window [self]
  (self:load-window (defaulted-offset self.offset)))

(fn open-external [self callback]
  (ExternalEditor.open-file self.path (defaulted-callback callback))
  true)

(fn drop-node [self]
  (when self.window-changed
    (self.window-changed:clear)))

(fn FsFileViewerNode [opts]
  (local options (defaulted-table opts))
  (local path (and options.path fs.absolute (fs.absolute options.path)))
  (assert-existing-file path)
  (local base-key (.. "fs-file-viewer:" path))
  (local key (if (= options.key nil) base-key options.key))
  (local node (GraphNode {:key key
                          :label (.. "View " path)
                          :color (glm.vec4 0.3 0.55 0.85 1)
                          :sub-color (glm.vec4 0.15 0.35 0.65 1)
                          :size 8.0
                          :view FsFileViewerNodeView}))
  (set node.path path)
  (set node.offset 0)
  (set node.window-size (defaulted-window-size options.window-size))
  (set node.window nil)
  (set node.previous-offsets [])
  (set node.window-changed (Signal))

  (set node.load-window load-window)
  (set node.next-window next-window)
  (set node.previous-window previous-window)
  (set node.refresh-window refresh-window)
  (set node.open-external open-external)
  (set node.drop drop-node)

  node)

{:FsFileViewerNode FsFileViewerNode
 :default-window-size default-window-size}
