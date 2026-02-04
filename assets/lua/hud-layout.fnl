(local glm (require :glm))
(local {: Layout} (require :layout))
(local Tiles (require :tiles))
(local FloatLayer (require :float-layer))
(local ControlPanel (require :hud-control-panel))
(local StatusPanel (require :hud-status-panel))

(local default-world-scale 0.05)

(fn hud-content-width [hud]
  (local target (or hud {}))
  (local units-per-pixel (or target.world-units-per-pixel default-world-scale))
  (local margin-px (or target.margin-px 0))
  (local margin (* units-per-pixel margin-px))
  (local half-width (or target.half-width 0))
  (math.max 0.001 (- (* half-width 2) (* margin 2))))

(fn hud-content-height [hud]
  (local target (or hud {}))
  (local units-per-pixel (or target.world-units-per-pixel default-world-scale))
  (local margin-px (or target.margin-px 0))
  (local margin (* units-per-pixel margin-px))
  (local half-height (or target.half-height 0))
  (math.max 0.001 (- (* half-height 2) (* margin 2))))

(fn FullWidth [opts]
  (assert opts.child "FullWidth requires :child")
  (fn build [ctx]
    (local child (opts.child ctx))
    (local hud (or opts.hud ctx.pointer-target))

    (fn resolve-width []
      (local width (hud-content-width hud))
      (if (and opts.min-width (< width opts.min-width))
          opts.min-width
          width))

    (fn measurer [self]
      (child.layout:measurer)
      (local child-measure child.layout.measure)
      (local width (resolve-width))
      (local height (. child-measure 2))
      (local depth (. child-measure 3))
      (set self.measure (glm.vec3 width height depth)))

    (fn layouter [self]
      (set self.size self.measure)
      (set child.layout.size self.size)
      (set child.layout.position self.position)
      (set child.layout.rotation self.rotation)
      (set child.layout.depth-offset-index self.depth-offset-index)
      (set child.layout.clip-region self.clip-region)
      (child.layout:layouter))

    (local layout
      (Layout {:name (or opts.name "full-width")
               : measurer : layouter
               :children [child.layout]}))

    (fn drop [self]
      (self.layout:drop)
      (child:drop))

    {: child : layout : drop}))

(fn make-overlay-root []
  (fn build [_ctx]
    (local overlay {:children []})

    (fn measurer [self]
      (set self.measure (glm.vec3 0))
      (each [_ metadata (ipairs overlay.children)]
        (local child (and metadata metadata.element))
        (local layout (and child child.layout))
        (when layout
          (layout:measurer)
          (for [axis 1 3]
            (when (> (. layout.measure axis) (. self.measure axis))
              (set (. self.measure axis) (. layout.measure axis)))))))

    (fn layouter [self]
      (each [_ metadata (ipairs overlay.children)]
        (local child (and metadata metadata.element))
        (local layout (and child child.layout))
        (when layout
          (set layout.size (or metadata.size layout.measure layout.size))
          (local offset (or metadata.position (glm.vec3 0 0 0)))
          (local rotation (or metadata.rotation (glm.quat 1 0 0 0)))
          (local depth-offset-index
            (if (= metadata.depth-offset-index nil)
                self.depth-offset-index
                metadata.depth-offset-index))
          (set layout.position (+ self.position (self.rotation:rotate offset)))
          (set layout.rotation (* self.rotation rotation))
          (set layout.depth-offset-index depth-offset-index)
          (set layout.clip-region self.clip-region)
          (layout:layouter))))

    (local layout
      (Layout {:name "hud-overlay"
               :children []
               :measurer measurer
               :layouter layouter}))

    (fn drop [_self]
      (layout:drop)
      (each [_ metadata (ipairs overlay.children)]
        (when (and metadata metadata.element metadata.element.drop)
          (metadata.element:drop)))
      (set overlay.children []))

    (set overlay.layout layout)
    (set overlay.drop drop)
    overlay))

(fn make-hud-builder [opts]
  (local options (or opts {}))
  (local control-builder (or options.control-builder
                             (ControlPanel (or options.control-panel-opts {}))))
  (local status-builder (or options.status-builder
                            (StatusPanel (or options.status-panel-opts {}))))
  (local tiles-root (Tiles {:rows 4
                            :columns 4
                            :xspacing 0
                            :yspacing 0}))
  (local float-root (FloatLayer {}))
  (local overlay-root (make-overlay-root))
  (local control-wrapper (FullWidth {:name "control-panel-wrapper"
                                     :child control-builder}))
  (local status-wrapper (FullWidth {:name "status-panel-wrapper"
                                    :child status-builder}))
  (fn build [ctx]
    (local control (control-wrapper ctx))
    (local status (status-wrapper ctx))
    (local tiles (tiles-root ctx))
    (local float (float-root ctx))
    (local overlay (overlay-root ctx))
    (local hud (or ctx.pointer-target {}))

    (fn measurer [self]
      (control.layout:measurer)
      (status.layout:measurer)
      (tiles.layout:measurer)
      (float.layout:measurer)
      (overlay.layout:measurer)
      (local width (hud-content-width hud))
      (local height (hud-content-height hud))
      (local depth (math.max (. control.layout.measure 3)
                             (. status.layout.measure 3)
                             (. tiles.layout.measure 3)
                             (. float.layout.measure 3)
                             (. overlay.layout.measure 3)))
      (set self.measure (glm.vec3 width height depth)))

    (fn layouter [self]
      (set self.size self.measure)
      (local base-position self.position)
      (local height self.size.y)
      (local top-y (+ base-position.y height))
      (local control-height (. control.layout.measure 2))
      (local status-height (. status.layout.measure 2))

      (fn position-child [child y-base depth-offset]
        (set child.layout.position (glm.vec3 base-position.x y-base base-position.z))
        (set child.layout.rotation self.rotation)
        (set child.layout.clip-region self.clip-region)
        (set child.layout.depth-offset-index depth-offset)
        (child.layout:layouter))

      (local control-bottom (- top-y control-height))
      (local status-bottom base-position.y)
      (local flex-bottom (+ status-bottom status-height))
      (local flex-height (math.max 0 (- control-bottom flex-bottom)))
      (local flex-size (glm.vec3 self.size.x flex-height (. tiles.layout.measure 3)))

      (position-child control control-bottom (+ self.depth-offset-index 1))
      (position-child status status-bottom self.depth-offset-index)
      (set tiles.layout.size flex-size)
      (set tiles.layout.position (glm.vec3 base-position.x flex-bottom base-position.z))
      (set tiles.layout.rotation self.rotation)
      (set tiles.layout.clip-region self.clip-region)
      (set tiles.layout.depth-offset-index (+ self.depth-offset-index 1))
      (tiles.layout:layouter)
      (set float.layout.size flex-size)
      (set float.layout.position (glm.vec3 base-position.x flex-bottom base-position.z))
      (set float.layout.rotation self.rotation)
      (set float.layout.clip-region self.clip-region)
      (set float.layout.depth-offset-index (+ self.depth-offset-index 2))
      (float.layout:layouter)
      (set overlay.layout.size self.size)
      (set overlay.layout.position base-position)
      (set overlay.layout.rotation self.rotation)
      (set overlay.layout.clip-region self.clip-region)
      (set overlay.layout.depth-offset-index (+ self.depth-offset-index 5))
      (overlay.layout:layouter))

    (local layout
      (Layout {:name "hud-panels"
               :measurer measurer
               :layouter layouter
               :children [control.layout status.layout tiles.layout float.layout overlay.layout]}))

    (fn drop [self]
      (self.layout:drop)
      (control:drop)
      (status:drop)
      (tiles:drop)
      (float:drop)
      (overlay:drop))

    {:layout layout
     :tiles-root tiles
     :float-root float
     :overlay-root overlay
     :drop drop}))

{:FullWidth FullWidth
 :make-overlay-root make-overlay-root
 :make-hud-builder make-hud-builder}
