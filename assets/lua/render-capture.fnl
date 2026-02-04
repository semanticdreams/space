(local fs (require :fs))
(local gl (require :gl))
(local ImageIO (require :image-io))

(fn resolve-size [opts]
  (local options (or opts {}))
  (local width (or options.width (and app app.viewport app.viewport.width)))
  (local height (or options.height (and app app.viewport app.viewport.height)))
  (assert width "render-capture requires :width or app.viewport.width")
  (assert height "render-capture requires :height or app.viewport.height")
  {:width width :height height})

(fn resolve-path [opts]
  (local options (or opts {}))
  (if options.path
      options.path
      (if (and options.dir options.name)
          (fs.join-path options.dir (.. options.name ".png"))
          nil)))

(fn capture-bytes [width height]
  (gl.glFinish)
  (local bytes (gl.glReadPixels 0 0 width height gl.GL_RGBA gl.GL_UNSIGNED_BYTE))
  (ImageIO.flip-vertical width height 4 bytes))

(fn capture [opts]
  (local options (or opts {}))
  (local mode (or options.mode "final"))
  (assert (= mode "final") (.. "render-capture mode unsupported: " (tostring mode)))
  (local {:width width :height height} (resolve-size options))
  (local bytes (capture-bytes width height))
  (local path (resolve-path options))
  (when path
    (local parent (fs.parent path))
    (when (and parent fs fs.create-dirs)
      (fs.create-dirs parent))
    (ImageIO.write-png path width height 4 bytes))
  (local include-bytes (if (= options.return-bytes nil) (not path) options.return-bytes))
  {:mode mode
   :width width
   :height height
   :path path
   :bytes (if include-bytes bytes nil)})

{:capture capture
 :capture-bytes capture-bytes}
