(local glm (require :glm))
(local {: Layout} (require :layout))
(local SubApp (require :sub-app))

(fn SubAppView [opts]
  (local options (or opts {}))
  (local view-size (or options.size (glm.vec3 18 12 0)))
  (local name (or options.name "sub-app"))

  (fn build [ctx]
    (assert app.renderers "SubAppView requires app.renderers")
    (assert app.renderers.add-sub-app "SubAppView requires renderers:add-sub-app")
    (assert app.renderers.remove-sub-app "SubAppView requires renderers:remove-sub-app")
    (local sub-app (SubApp {:name name
                            :size (glm.vec2 view-size.x view-size.y)}))
    (app.renderers:add-sub-app sub-app)

    (fn measurer [self]
      (set self.measure (glm.vec3 view-size.x view-size.y 0)))

    (local units-per-pixel
      (or options.units-per-pixel
          (and ctx.pointer-target ctx.pointer-target.world-units-per-pixel)))
    (assert units-per-pixel "SubAppView requires :units-per-pixel or target.world-units-per-pixel")

    (fn layouter [self]
      (sub-app:set-size (/ self.size.x units-per-pixel)
                        (/ self.size.y units-per-pixel))
      (sub-app:update-quad self))

    (local layout
      (Layout {:name name
               :measurer measurer
               :layouter layouter}))

    (fn drop [_self]
      (app.renderers:remove-sub-app sub-app)
      (sub-app:drop)
      (layout:drop))

    {:layout layout
     :sub-app sub-app
     :drop drop})

  build)

(local exports {:SubAppView SubAppView})

(setmetatable exports {:__call (fn [_ ...]
                                 (SubAppView ...))})

exports
