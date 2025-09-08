(fn Layout [opts]
  (set opts.name (or opts.name "layout"))
  (set opts.root nil)
  (set opts.parent nil)
  (set opts.position (vec3 0))
  (set opts.rotation (quat 1 0 0 0))
  (set opts.measure (vec3 0))
  (set opts.size (vec3 0))
  (set opts.measure-dirty false)
  (set opts.layout-dirty false)
  (set opts.measurer (or opts.measurer (fn [])))
  (set opts.layouter (or opts.layouter (fn [])))

  (fn set-children [self children]
    (self:clear-children)
    (self:add-children children))

  (fn clear-children [self]
    (when self.children
      (each [i x (ipairs self.children)]
        (self:remove-child i))))

  (fn remove-child [self idx]
    (local child (. self.children idx))
    (set child.parent nil)
    (child:set-root nil)
    (table.remove self.children idx))

  (fn add-children [self children]
    (each [i x (ipairs children)]
      (self:add-child x)))

  (fn add-child [self child]
    (set child.parent self)
    (child:set-root self.root)
    (table.insert self.children child))

  (fn set-root [self root]
    (local stack [])
    (var node self)
    (while node
      (each [_ x (ipairs node.children)]
        (table.insert stack x))
      (set node.root root)
      (if
        root (do
               (when node.measure-dirty
                 (set (. root.measure-dirt node) true)
                 (set node.measure-dirty false))
               (when node.layout-dirty
                 (set (. root.layout-dirt node) true)
                 (set node.layout-dirty false)))
        node.root (do
                    (set (. node.root.measure-dirt node) nil)
                    (set (. node.root.layout-dirt node) nil)))
      (set node (table.remove stack))
      ))

  (fn mark-layout-dirty [self]
    (if
      self.root (set (. self.root.layout-dirt self) true)
      (set self.layout-dirty true)))

  (fn mark-measure-dirty [self]
    (if
      self.root (set (. self.root.measure-dirt self) true)
      (set self.measure-dirty true)))

  (fn set-position [self position]
    (set self.position position)
    (self:mark-layout-dirty))

  (fn set-rotation [self rotation]
    (set self.rotation rotation)
    (self:mark-layout-dirty))

  (fn drop [self]
    (self:clear-children)
    (when self.root
      (set (. self.root.measure-dirt self) nil)
      (set (. self.root.layout-dirt self) nil)))

  (local o {:name opts.name :root opts.root :parent opts.parent :children []
            :position opts.position :rotation opts.rotation
            :measure opts.measure :size opts.size
            :measure-dirty opts.measure-dirty
            :layout-dirty opts.layout-dirty
            :measurer opts.measurer :layouter opts.layouter
            : set-children : clear-children : remove-child : add-children : add-child
            : set-root : mark-layout-dirty : mark-measure-dirty
            : set-position : set-rotation : drop})
  (o:set-children (or opts.children []))
  o)

(fn LayoutRoot []
  (fn update [self]
    (each [k v (pairs self.measure-dirt)]
      (var n k)
      (while n.parent
        (set n n.parent))
      (n:measurer)
      (set (. self.measure-dirt k) nil)
      (set (. self.layout-dirt n) true))
    (each [k v (pairs self.layout-dirt)]
      (k:layouter)
      (set (. self.layout-dirt k) nil))
    )

  {: update :measure-dirt {} :layout-dirt {}}
  )

{: Layout : LayoutRoot}
