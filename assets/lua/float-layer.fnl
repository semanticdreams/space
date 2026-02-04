(local glm (require :glm))
(local {: Layout} (require :layout))

(fn resolve-parent-transform [layout]
  (local position (or (and layout layout.position) (glm.vec3 0 0 0)))
  (local rotation (or (and layout layout.rotation) (glm.quat 1 0 0 0)))
  (local inverse (rotation:inverse))
  (values position rotation inverse))

(fn compute-local-position [layout position]
  (let [(parent-position _ parent-inverse) (resolve-parent-transform layout)]
    (parent-inverse:rotate (- position parent-position))))

(fn compute-local-rotation [layout rotation]
  (let [(_ parent-rotation parent-inverse) (resolve-parent-transform layout)]
    (* parent-inverse rotation)))

(fn find-child [children element]
  (var found nil)
  (var found-idx nil)
  (when (and element children)
    (each [idx metadata (ipairs children)]
      (when (and (not found) (= metadata.element element))
        (set found metadata)
        (set found-idx idx))))
  (values found found-idx))

(fn FloatLayer [opts]
  (fn build [ctx]
    (local options (or opts {}))
    (local layer {:children []
                  :layout nil
                  :build-context ctx})

    (fn measurer [self]
      (set self.measure (glm.vec3 0))
      (each [_ metadata (ipairs layer.children)]
        (local element (and metadata metadata.element))
        (local layout (and element element.layout))
        (when layout
          (layout:measurer)
          (for [axis 1 3]
            (when (> (. layout.measure axis) (. self.measure axis))
              (set (. self.measure axis) (. layout.measure axis)))))))

    (fn layouter [self]
      (let [(parent-position parent-rotation _parent-inverse) (resolve-parent-transform self)]
        (each [_ metadata (ipairs layer.children)]
          (local element (and metadata metadata.element))
          (local layout (and element element.layout))
          (when layout
            (local rotation (or metadata.rotation (glm.quat 1 0 0 0)))
            (local depth-offset-index
              (if (= metadata.depth-offset-index nil)
                  self.depth-offset-index
                  metadata.depth-offset-index))
            ; Use world-position if set (from resize/move), otherwise compute from local-offset
            (local new-pos
              (if metadata.world-position
                  metadata.world-position
                  (+ parent-position (parent-rotation:rotate (or metadata.position (glm.vec3 0 0 0))))))
            (set layout.size (or metadata.size layout.measure layout.size))
            (set layout.position new-pos)
            (set layout.rotation (* parent-rotation rotation))
            (set layout.depth-offset-index depth-offset-index)
            (set layout.clip-region self.clip-region)
            (when metadata.target
              (set metadata.target.position layout.position)
              (set metadata.target.size layout.size))
            (layout:layouter)))))

    (local layout
      (Layout {:name (or options.name "float-layer")
               :children []
               :measurer measurer
               :layouter layouter}))

    (fn attach-child [self element opts]
      (when (and element element.layout)
        (local options (or opts {}))
        (local position (or options.position element.layout.position (glm.vec3 0 0 0)))
        (local rotation (or options.rotation element.layout.rotation (glm.quat 1 0 0 0)))
        (local size (or options.size element.layout.size element.layout.measure (glm.vec3 0 0 0)))
        (local metadata {:element element
                         :position (compute-local-position self.layout position)
                         :rotation (compute-local-rotation self.layout rotation)
                         :size size
                         :depth-offset-index options.depth-offset-index})
        (table.insert self.children metadata)
        (self.layout:add-child element.layout)
        (self.layout:mark-measure-dirty)
        (self.layout:mark-layout-dirty)
        metadata))

    (fn add-child [self opts]
      (local options (or opts {}))
      (local builder (and options options.builder))
      (when (and builder self.build-context)
        (local builder-options {})
        (each [key value (pairs (or options.builder-options {}))]
          (set (. builder-options key) value))
        (local element (builder self.build-context builder-options))
        (attach-child self element options)
        element))

    (fn detach-child [self element]
      (let [(metadata idx) (find-child self.children element)]
        (when (and metadata idx)
          (self.layout:remove-child idx)
          (table.remove self.children idx)
          (self.layout:mark-measure-dirty)
          (self.layout:mark-layout-dirty)
          metadata)))

    (fn remove-child [self element]
      (local metadata (detach-child self element))
      (when (and metadata metadata.element metadata.element.drop)
        (metadata.element:drop))
      metadata)

    (fn ensure-target [_self metadata]
      (when (and metadata metadata.element metadata.element.layout)
        (if metadata.target
            metadata.target
            (do
              (local layout metadata.element.layout)
              (local target {:position (or layout.position (glm.vec3 0 0 0))
                             :size (or metadata.size layout.size layout.measure (glm.vec3 0 0 0))
                             :rotation (or layout.rotation (glm.quat 1 0 0 0))
                             :layout layout})
              (set target.set-position
                   (fn [self position]
                     (set self.position position)
                     (when (and metadata metadata.element metadata.element.layout)
                       (set metadata.world-position position)
                       (layout:set-position position))))
              (set target.set-size
                   (fn [self size]
                     (set self.size size)
                     (set metadata.size size)
                     (set layout.size size)
                     (layout:mark-layout-dirty)))
              (set metadata.target target)
              target))))

    (fn ensure-movable-target [self metadata]
      (ensure-target self metadata))

    (fn ensure-resize-target [self metadata]
      (ensure-target self metadata))

    (fn drop [self]
      (self.layout:drop)
      (each [_ metadata (ipairs self.children)]
        (when (and metadata metadata.element metadata.element.drop)
          (metadata.element:drop)))
      (set self.children []))

    (set layer.layout layout)
    (set layer.add-child add-child)
    (set layer.attach-child attach-child)
    (set layer.detach-child detach-child)
    (set layer.remove-child remove-child)
    (set layer.ensure-movable-target ensure-movable-target)
    (set layer.ensure-resize-target ensure-resize-target)
    (set layer.drop drop)
    layer))

FloatLayer
