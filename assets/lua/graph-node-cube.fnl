(local glm (require :glm))
(local Cuboid (require :cuboid))
(local Rectangle (require :rectangle))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Stack (require :stack))
(local Padding (require :padding))
(local Aligned (require :aligned))

(local GraphViewUtils (require :graph/view/utils))
(local truncate-with-ellipsis GraphViewUtils.truncate-with-ellipsis)
(local wrap-text GraphViewUtils.wrap-text)
(local ensure-glm-vec4 GraphViewUtils.ensure-glm-vec4)

(fn resolve-menu-position [event]
  (local screen (and event event.screen))
  (if (and screen app.hud app.hud.screen-pos-ray)
      (do
        (local ray (app.hud:screen-pos-ray {:x (or screen.x 0)
                                            :y (or screen.y 0)}))
        (if (and ray ray.origin ray.direction)
            (do
              (local dz (or ray.direction.z 0))
              (local t (if (not (= dz 0))
                           (/ (- 0 ray.origin.z) dz)
                           0))
              (+ ray.origin (* ray.direction t)))
            (or (and event event.point) (glm.vec3 0 0 0))))
      (or (and event event.point) (glm.vec3 0 0 0))))

(fn lod-settings [lod]
  (if (= lod 0)
      {:text-length 24 :line-length 8 :scale 0.45}
      (= lod 1)
      {:text-length 16 :line-length 6 :scale 0.4}
      (= lod 2)
      {:text-length 12 :line-length 5 :scale 0.35}
      {:text-length 8 :line-length 4 :scale 0.3}))

(fn lod-target [distance]
  (if (< distance 140.0)
      0
      (< distance 260.0)
      1
      (< distance 420.0)
      2
      3))

(fn shade-color [color factor]
  (glm.vec4 (math.max 0 (math.min 1 (* color.x factor)))
            (math.max 0 (math.min 1 (* color.y factor)))
            (math.max 0 (math.min 1 (* color.z factor)))
            (or color.w 1)))

(fn make-face-builder [opts]
  (local options (or opts {}))
  (local base-color (or options.color (glm.vec4 0.18 0.22 0.28 1)))
  (local base-scale (or options.scale 0.45))
  (fn build [ctx]
    (var label-text nil)
    (local stack
      ((Stack {:children
               [(Rectangle {:color base-color})
                (Padding {:edge-insets [0.1 0.1]
                          :child (Aligned {:xalign :center
                                           :yalign :center
                                           :child (fn [child-ctx]
                                                    (set label-text
                                                         ((Text {:text (or options.text "")
                                                                 :style (TextStyle {:scale base-scale})}) child-ctx))
                                                    label-text)})})]})
       ctx))
    (assert label-text "GraphNodeCube face requires label text widget")

    (fn set-display-text [self value scale]
      (label-text:set-text (or value "") {:mark-measure-dirty? true})
      (set label-text.style.scale (or scale base-scale))
      (self.layout:mark-measure-dirty))

    (fn drop [self]
      (self.layout:drop)
      (stack:drop))

    {:layout stack.layout
     :drop drop
     :set-display-text set-display-text
     :label-text label-text}))

(fn GraphNodeCube [opts]
  (local options (or opts {}))

  (fn build [ctx runtime-opts]
    (local runtime-options (or runtime-opts {}))
    (local node (or runtime-options.node options.node))
    (local node-key (tostring (or runtime-options.node-key
                                  options.node-key
                                  (and node node.key)
                                  "")))
    (local base-label (or runtime-options.label
                          options.label
                          (and node node.label)
                          node-key))
    (local get-menu-manager (or runtime-options.get-menu-manager
                                options.get-menu-manager
                                (fn []
                                  (or (and ctx ctx.menu-manager) app.menu-manager))))
    (local on-graph (or runtime-options.on-graph options.on-graph))
    (local clickables (assert (and ctx ctx.clickables)
                              "GraphNodeCube requires ctx.clickables"))

    (local node-color
      (ensure-glm-vec4 (or runtime-options.color
                           options.color
                           (and node node.color))
                       (glm.vec4 0.2 0.24 0.3 1)))
    (local front-back-color (shade-color node-color 1.0))
    (local side-color (shade-color node-color 0.8))
    (local top-bottom-color (shade-color node-color 0.65))
    (local front-builder (make-face-builder {:name "graph-node-cube-front"
                                             :text base-label
                                             :color front-back-color}))
    (local back-builder (make-face-builder {:name "graph-node-cube-back"
                                            :text base-label
                                            :color front-back-color}))
    (local right-builder (make-face-builder {:name "graph-node-cube-right"
                                             :text base-label
                                             :color side-color}))
    (local left-builder (make-face-builder {:name "graph-node-cube-left"
                                            :text base-label
                                            :color side-color}))
    (local top-builder (make-face-builder {:name "graph-node-cube-top"
                                           :text ""
                                           :color top-bottom-color}))
    (local bottom-builder (make-face-builder {:name "graph-node-cube-bottom"
                                              :text ""
                                              :color top-bottom-color}))
    (local cuboid
      ((Cuboid {:children [front-builder
                           back-builder
                           right-builder
                           left-builder
                           top-builder
                           bottom-builder]})
       ctx))

    (local front (. cuboid.faces 1))
    (local back (. cuboid.faces 2))
    (local right (. cuboid.faces 3))
    (local left (. cuboid.faces 4))
    (local top (. cuboid.faces 5))
    (local bottom (. cuboid.faces 6))
    (local labeled-faces [front back right left])

    (var current-lod nil)
    (var update-handler nil)

    (fn current-camera-position []
      (and app.camera app.camera.position))

    (fn cube-center []
      (local layout cuboid.layout)
      (local rotation (or (and layout layout.rotation) (glm.quat 1 0 0 0)))
      (local size (or (and layout layout.size) (and layout layout.measure) (glm.vec3 0 0 0)))
      (+ (or (and layout layout.position) (glm.vec3 0 0 0))
         (rotation:rotate (* size (glm.vec3 0.5 0.5 0.5)))))

    (fn apply-lod [lod]
      (local settings (lod-settings lod))
      (local truncated (truncate-with-ellipsis (or base-label "") settings.text-length))
      (local text (if settings.line-length
                      (wrap-text truncated settings.line-length)
                      truncated))
      (each [_ face (ipairs labeled-faces)]
        (when (and face face.set-display-text)
          (face:set-display-text text settings.scale)))
      (each [_ face (ipairs [top bottom])]
        (when (and face face.set-display-text)
          (face:set-display-text "" settings.scale)))
      (cuboid.layout:mark-measure-dirty)
      (cuboid.layout:mark-layout-dirty))

    (fn sync-lod [force?]
      (local camera-position (current-camera-position))
      (local next-lod
        (if camera-position
            (lod-target (glm.length (- (cube-center) camera-position)))
            0))
      (when (or force?
                (= current-lod nil)
                (not (= current-lod next-lod)))
        (set current-lod next-lod)
        (apply-lod next-lod)))

    (fn open-graph [self button event]
      (when on-graph
        (on-graph self button event {:node node
                                     :node-key node-key
                                     :label base-label
                                     :cube-position (cube-center)})))

    (local right-click-target
      {:pointer-target (or (and ctx ctx.pointer-target) app.scene)
       :intersect (fn [_self ray]
                    (cuboid.layout:intersect ray))
       :on-right-click
       (fn [_self event]
         (local manager (get-menu-manager))
         (when manager
           (manager:open {:actions [{:name "graph"
                                     :fn (fn [button click-event]
                                           (open-graph cuboid button (or click-event event)))}]
                          :position (resolve-menu-position event)}))
         true)})

    (clickables:register-right-click right-click-target)

    (when (and app.engine app.engine.events app.engine.events.updated)
      (set update-handler
           (app.engine.events.updated:connect
             (fn [_payload]
               (sync-lod false)))))
    (sync-lod true)

    (set cuboid.node node)
    (set cuboid.node-key node-key)
    (set cuboid.base-label base-label)
    (set cuboid.open-graph open-graph)

    (local original-drop cuboid.drop)
    (set cuboid.drop
         (fn [self]
           (clickables:unregister-right-click right-click-target)
           (when (and update-handler app.engine app.engine.events app.engine.events.updated)
             (app.engine.events.updated:disconnect update-handler true)
             (set update-handler nil))
           (original-drop self)))
    cuboid))

GraphNodeCube
