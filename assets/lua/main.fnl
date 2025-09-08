(global fennel (require :fennel))

(set fennel.macro-path space.fennel_path)

(global pp (fn [x] (print (fennel.view x))))

(global read-file (fn [path]
  (let [file (io.open path "r")]
    (if file
        (let [content (file:read "*all")]
          (file:close)
          content)
        (error (.. "Could not open file: " path))))))

(global one (fn [val] (assert (= (length val) 1) val) (. val 1)))

(fn matches-filters? [target filters]
  (or
    (= filters nil)
    (each [k v (pairs filters)]
      (when (not (= (. target k) v))
        (lua "return false")))
    true))

(local {: LayoutRoot} (require :layout))
(local Rectangle (require :rectangle))

(local {: Flex : FlexChild} (require :flex))
(local Sized (require :sized))

(fn space.init []
  (set space.renderers ((require :renderers)))

  (local build-context {:triangle-vector space.renderers.scene-triangle-vector})

  (local layout-root (LayoutRoot))

  (local flex
    (Flex
      {:axis 2 :children
       [(FlexChild
          (Sized {:size (vec3 4 4 0)
                  :child (Rectangle {:color (vec4 1 0 0 1)})}))
        (FlexChild
          (Flex {:children [(FlexChild (Sized {:size (vec3 5 2 0) :child (Rectangle {:color (vec4 0 1 1 1)})}))
                            (FlexChild (Sized {:size (vec3 3 3 0) :child (Rectangle {:color (vec4 0 1 0 1)})}))]}))
        (FlexChild (Sized {:size (vec3 4 4 0) :child (Rectangle {:color (vec4 1 1 0 1)})}))
        ]}))

  (local e (flex build-context))
  (e.layout:set-root layout-root)
  (e.layout:set-position (vec3 -5 -5 0))
  (e.layout:mark-measure-dirty)

  (layout-root:update)
  )

(fn space.update [delta]
  (gl.glBindFramebuffer gl.GL_FRAMEBUFFER space.fbo)
  (gl.glDisable gl.GL_CULL_FACE)
  (gl.glEnable gl.GL_DEPTH_TEST)
  (gl.glDepthFunc gl.GL_LESS)
  (gl.glClearColor 0.1 0.2 0.3 1.0)
  (gl.glClear (bor gl.GL_COLOR_BUFFER_BIT gl.GL_DEPTH_BUFFER_BIT))
  (space.renderers:update)
  )

(fn space.drop []
  )
