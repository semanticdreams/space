(local {: Grid} (require :grid))

(fn find-child [children element]
  (var found nil)
  (var found-idx nil)
  (when (and element children)
    (each [idx metadata (ipairs children)]
      (when (and (not found) (= metadata.element element))
        (set found metadata)
        (set found-idx idx))))
  (values found found-idx))

(fn Tiles [opts]
  (fn build [ctx]
    (local options (or opts {}))
    (local grid-builder
      (Grid {:rows (or options.rows 4)
             :columns (or options.columns 4)
             :xspacing (or options.xspacing 0.5)
             :yspacing (or options.yspacing 0.5)
             :children []}))
    (local grid (grid-builder ctx))
    (local tiles {:children grid.children
                  :layout grid.layout
                  :build-context ctx})

    (fn attach-child [self element opts]
      (when (and self element element.layout)
        (local options (or opts {}))
        (local metadata {:element element
                         :align-x options.align-x
                         :align-y options.align-y})
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

    (fn drop [self]
      (self.layout:drop)
      (each [_ metadata (ipairs self.children)]
        (when (and metadata metadata.element metadata.element.drop)
          (metadata.element:drop)))
      (set self.children []))

    (set tiles.attach-child attach-child)
    (set tiles.add-child add-child)
    (set tiles.detach-child detach-child)
    (set tiles.remove-child remove-child)
    (set tiles.drop drop)
    tiles))

Tiles
