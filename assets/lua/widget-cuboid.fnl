(local glm (require :glm))
(local {: Layout} (require :layout))
(local {: get-button-theme-colors} (require :widget-theme-utils))
(local Cuboid (require :cuboid))
(local Rectangle (require :rectangle))
(local Sized (require :sized))

(local colors (require :colors))
(fn WidgetCuboid [opts]
  (local options (or opts {}))
  (assert options.child "WidgetCuboid requires :child builder")
  (local default-side-color (glm.vec4 0.16 0.16 0.16 1))
  (local depth-scale (or options.depth-scale 0.5))
  (local min-depth (or options.min-depth 0))

  (fn resolve-side-color [ctx]
    (if options.side-color
        options.side-color
        (let [colors (get-button-theme-colors ctx (or options.variant :tertiary))]
          (or (and colors colors.background) default-side-color))))

  (fn build [ctx runtime-opts]
    (local front (options.child ctx runtime-opts))
    (local side-color (resolve-side-color ctx))
    (var x-side-size (glm.vec3 0 0 0))
    (var y-side-size (glm.vec3 0 0 0))

    (local cuboid-builder
      (Cuboid {:children
               [(fn [_] front)
                (Rectangle {:color side-color})
                (Sized {:size x-side-size
                        :child (Rectangle {:color side-color})})
                (Sized {:size x-side-size
                        :child (Rectangle {:color side-color})})
                (Sized {:size y-side-size
                        :child (Rectangle {:color side-color})})
                (Sized {:size y-side-size
                        :child (Rectangle {:color side-color})})]}))
    (local cuboid (cuboid-builder ctx))

    (fn update-depth []
      (local width (or (and front.layout front.layout.measure (. front.layout.measure 1)) 0))
      (local depth (math.max min-depth (* width depth-scale)))
      (set x-side-size.x depth)
      (set x-side-size.y 0)
      (set x-side-size.z 0)
      (set y-side-size.x 0)
      (set y-side-size.y depth)
      (set y-side-size.z 0))

    (fn measurer [self]
      (when front.layout
        (front.layout:measurer))
      (update-depth)
      (cuboid.layout:measurer)
      (set self.measure cuboid.layout.measure))

    (fn layouter [self]
      (set cuboid.layout.size self.size)
      (set cuboid.layout.position self.position)
      (set cuboid.layout.rotation self.rotation)
      (set cuboid.layout.depth-offset-index self.depth-offset-index)
      (set cuboid.layout.clip-region self.clip-region)
      (cuboid.layout:layouter))

    (local layout
      (Layout {:name "widget-cuboid"
               :children [cuboid.layout]
               : measurer
               : layouter}))

    (fn drop [self]
      (self.layout:drop)
      (cuboid:drop))

    (set cuboid.__front_widget front)
    (local wrapper {:layout layout
                    :drop drop
                    :cuboid cuboid
                    :front front})
    (set front.__scene_wrapper wrapper)
    wrapper)

  build)

WidgetCuboid
