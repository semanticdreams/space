(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local FsFileViewerNodeView (require :graph/view/views/fs-file-viewer))
(local ExternalEditor (require :external-editor))
(local fs (require :fs))
(local LazyTextSource (require :lazy-text-source))
(local LazyTextBuffer (require :lazy-text-buffer))

(fn noop [] nil)

(fn defaulted-table [value]
  (if (= value nil) {} value))

(fn defaulted-callback [value]
  (if (= value nil) noop value))

(fn assert-existing-file [path]
  (assert (and (= (type path) :string) (> (length path) 0))
          "FsFileViewerNode requires an existing file path")
  (local stat (and fs.stat (fs.stat path)))
  (assert (and stat stat.exists stat.is-file)
          "FsFileViewerNode requires an existing file path"))

(fn open-external [self callback]
  (ExternalEditor.open-file self.path (defaulted-callback callback))
  true)

(fn drop-node [_self] nil)

(fn FsFileViewerNode [opts]
  (local options (defaulted-table opts))
  (local path (and options.path fs.absolute (fs.absolute options.path)))
  (assert-existing-file path)
  (local base-key (.. "fs-file-viewer:" path))
  (local key (if (= options.key nil) base-key options.key))
  (local source (LazyTextSource.file path))
  (local buffer (LazyTextBuffer {:source source}))
  (local node (GraphNode {:key key
                          :label (.. "View " path)
                          :color (glm.vec4 0.3 0.55 0.85 1)
                          :sub-color (glm.vec4 0.15 0.35 0.65 1)
                          :size 8.0
                          :view FsFileViewerNodeView}))
  (set node.path path)
  (set node.source source)
  (set node.buffer buffer)
  (set node.open-external open-external)
  (set node.drop drop-node)

  node)

{:FsFileViewerNode FsFileViewerNode}
