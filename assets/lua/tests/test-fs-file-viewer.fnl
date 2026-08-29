(local fs (require :fs))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "fs-file-viewer"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "viewer-" (os.time) "-" temp-counter)))

(fn create-temp-dir []
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  dir)

(fn write-sample-file [dir]
  (local file (fs.join-path dir "sample.txt"))
  (fs.write-file file "abcdefghi")
  (fs.absolute file))

(fn create-sample-file []
  (local dir (create-temp-dir))
  (values dir (write-sample-file dir)))

(fn vector-allocate [_self _count] 1)
(fn vector-delete [_self _handle] nil)
(fn vector-set-glm-vec3 [_self _handle _offset _value] nil)
(fn vector-set-glm-vec4 [_self _handle _offset _value] nil)
(fn vector-set-glm-vec2 [_self _handle _offset _value] nil)
(fn vector-set-float [_self _handle _offset _value] nil)

(fn make-vector-buffer []
  {:allocate vector-allocate
   :delete vector-delete
   :set-glm-vec3 vector-set-glm-vec3
   :set-glm-vec4 vector-set-glm-vec4
   :set-glm-vec2 vector-set-glm-vec2
   :set-float vector-set-float})

(fn clickable-register [_self _obj] nil)
(fn clickable-unregister [_self _obj] nil)
(fn clickable-register-right-click [_self _obj] nil)
(fn clickable-unregister-right-click [_self _obj] nil)
(fn clickable-register-double-click [_self _obj] nil)
(fn clickable-unregister-double-click [_self _obj] nil)

(fn make-clickables-stub []
  {:register clickable-register
   :unregister clickable-unregister
   :register-right-click clickable-register-right-click
   :unregister-right-click clickable-unregister-right-click
   :register-double-click clickable-register-double-click
   :unregister-double-click clickable-unregister-double-click})

(fn hoverable-register [_self _obj] nil)
(fn hoverable-unregister [_self _obj] nil)

(fn make-hoverables-stub []
  {:register hoverable-register
   :unregister hoverable-unregister})

(fn ssbo-upsert-text [_batcher _key _opts] nil)
(fn ssbo-update-text-transform [_batcher _key _opts] nil)
(fn ssbo-remove-text [_batcher _key] nil)

(fn make-ssbo-batcher []
  {:upsert-text ssbo-upsert-text
   :update-text-transform ssbo-update-text-transform
   :remove-text ssbo-remove-text})

(fn ctx-get-text-ssbo-batcher [_self]
  (make-ssbo-batcher))

(fn make-test-font []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1 :lineHeight 1}}
               :glyph-map {}})
  (set font.metadata.atlas {:width 1 :height 1})
  (for [codepoint 1 65533]
    (tset font.glyph-map codepoint glyph))
  font)

(fn make-test-ctx []
  (local text-buffer (make-vector-buffer))
  (local font (make-test-font))
  (local ctx {:triangle-vector (make-vector-buffer)
              :clickables (make-clickables-stub)
              :hoverables (make-hoverables-stub)
              :theme {:font font
                      :text {:foreground [1 1 1 1] :scale 1}}})
  (set ctx.get-text-vector (fn [_self _font] text-buffer))
  (set ctx.get-text-ssbo-batcher ctx-get-text-ssbo-batcher)
  ctx)

(fn text-widget-string [widget]
  (table.concat
    (icollect [_ codepoint (ipairs (widget:get-codepoints))]
              (utf8.char codepoint))
    ""))

(fn string-contains? [text needle]
  (not (= (string.find text needle 1 true) nil)))

(fn assert-metadata [view offset bytes size]
  (local metadata (text-widget-string view.metadata-text))
  (assert (string-contains? metadata (.. "Offset " offset)) "metadata should include offset")
  (assert (string-contains? metadata (.. "Bytes " bytes)) "metadata should include bytes read")
  (assert (string-contains? metadata (.. "Size " size)) "metadata should include file size"))

(fn fs-file-viewer-node-reads-bounded-windows []
  (local {:FsFileViewerNode FsFileViewerNode} (require :graph/nodes/fs-file-viewer))
  (local (dir file) (create-sample-file))
  (local node (FsFileViewerNode {:path file :window-size 3}))
  (assert (= (. (node:load-window 0) :text) "abc"))
  (assert (= node.offset 0))
  (assert (= (. (node:next-window) :text) "def"))
  (assert (= node.offset 3))
  (assert (= (. (node:next-window) :text) "ghi"))
  (assert (= node.offset 6))
  (assert (= (. (node:previous-window) :text) "def"))
  (assert (= node.offset 3))
  (node:drop)
  (fs.remove-all dir))

(fn fs-file-viewer-key-loader-loads-existing-file []
  (local Graph (require :graph/init))
  (local GraphKeyLoaders (require :graph/key-loaders))
  (local (dir file) (create-sample-file))
  (local key (.. "fs-file-viewer:" file))
  (local graph (Graph {:with-start false}))
  (GraphKeyLoaders.register graph {})
  (local node (graph:load-by-key key))
  (assert node "fs-file-viewer loader should create a node for an existing file")
  (assert (= node.key key) "loaded viewer key should match")
  (assert (= node.path file) "loaded viewer path should match absolute path")
  (node:drop)
  (graph:drop)
  (fs.remove-all dir))

(fn exercise-view-controls [view opened file]
  (assert (= (text-widget-string view.content-text) "abc")
          "viewer should load initial window during build")
  (assert-metadata view 0 3 9)
  (view.next-button:on-click {})
  (assert (= (text-widget-string view.content-text) "def"))
  (assert-metadata view 3 3 9)
  (view.previous-button:on-click {})
  (assert (= (text-widget-string view.content-text) "abc"))
  (view.refresh-button:on-click {})
  (assert (= (text-widget-string view.content-text) "abc"))
  (view.content-button:on-double-click {})
  (view.edit-button:on-click {})
  (assert (= (. opened 1) file) "double-click should open the absolute path")
  (assert (= (. opened 2) file) "edit button should open the absolute path"))

(fn fs-file-viewer-view-controls-refresh-and-open-external []
  (local {:FsFileViewerNode FsFileViewerNode} (require :graph/nodes/fs-file-viewer))
  (local FsFileViewerNodeView (require :graph/view/views/fs-file-viewer))
  (local ExternalEditor (require :external-editor))
  (local (dir file) (create-sample-file))
  (local node (FsFileViewerNode {:path file :window-size 3}))
  (local original-open-file ExternalEditor.open-file)
  (local opened [])
  (var view nil)
  (set ExternalEditor.open-file
       (fn [path callback]
         (table.insert opened path)
         (callback)
         true))
  (local (ok result)
    (pcall
      (fn []
        (set view ((FsFileViewerNodeView node {}) (make-test-ctx)))
        (exercise-view-controls view opened file))))
  (set ExternalEditor.open-file original-open-file)
  (when view
    (view:drop))
  (node:drop)
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(table.insert tests {:name "fs-file-viewer node reads bounded windows"
                     :fn fs-file-viewer-node-reads-bounded-windows})
(table.insert tests {:name "fs-file-viewer key loader loads existing file"
                     :fn fs-file-viewer-key-loader-loads-existing-file})
(table.insert tests {:name "fs-file-viewer view controls refresh and open external"
                     :fn fs-file-viewer-view-controls-refresh-and-open-external})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "fs-file-viewer"
                       :tests tests})))

{:name "fs-file-viewer"
 :tests tests
 :main main}
