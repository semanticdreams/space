(local glm (require :glm))
(local {: ray-box-intersection} (require :ray-box))
(local make-depth-bucket-queue (require :bucket-queue))

(local position-epsilon 1e-5)

(local MathUtils (require :math-utils))
(local approx (fn [a b] (MathUtils.approx a b {:epsilon position-epsilon})))

(local fs (require :fs))
(local appdirs (require :appdirs))

(local clock os.clock)
(local max-stats-frames 100000)

(fn make-pass-timer []
  (var start nil)
  (var count 0)
  (var delta 0.0)

  (fn begin []
    (set count 0)
    (set start (clock)))

  (fn tick []
    (set count (+ count 1)))

  (fn finish []
    (if start
        (set delta (- (clock) start))
        (set delta 0.0))
    (set start nil)
    {:count count :delta delta})

  {:begin begin :tick tick :finish finish})

(fn vec3-equal? [a b]
  (if (and a b)
      (and (approx a.x b.x)
           (approx a.y b.y)
           (approx a.z b.z))
      (= a b)))

(fn quat-equal? [a b]
  (if (and a b)
      (and (approx a.x b.x)
           (approx a.y b.y)
           (approx a.z b.z)
           (approx a.w b.w))
      (= a b)))

(fn resolve-mark-flag [opts key default]
  (if (and opts (not (= (. opts key) nil)))
      (not (not (. opts key)))
      default))

(fn within-range [value max-value]
  (local max (or max-value 0))
  (and (>= (+ value position-epsilon) 0)
       (<= (- value position-epsilon) max)))

(fn point-within-bounds? [point bounds]
  (if (not bounds)
      true
      (let [position (or bounds.position (glm.vec3 0 0 0))
            rotation (or bounds.rotation (glm.quat 1 0 0 0))
            size (or bounds.size (glm.vec3 0 0 0))
            inverse (rotation:inverse)
            local-point (inverse:rotate (- point position))]
        (and (within-range local-point.x size.x)
             (within-range local-point.y size.y)
             (within-range local-point.z size.z)))))

(fn clip-allows-point? [clip point]
  (local bounds (and clip clip.bounds))
  (if bounds
      (point-within-bounds? point bounds)
      true))

(fn layout-world-corners [layout]
  (fn finite-number? [value]
    (and (= (type value) :number)
         (= value value)
         (not (= value math.huge))
         (not (= value (- math.huge)))))
  (fn assert-finite-vec3 [vec label]
    (when (or (not vec)
              (not (finite-number? vec.x))
              (not (finite-number? vec.y))
              (not (finite-number? vec.z)))
      (error (.. "Layout received non-finite " label))))
  (fn assert-finite-quat [quat label]
    (when (or (not quat)
              (not (finite-number? quat.x))
              (not (finite-number? quat.y))
              (not (finite-number? quat.z))
              (not (finite-number? quat.w)))
      (error (.. "Layout received non-finite " label))))
  (local size (or layout.size (glm.vec3 0 0 0)))
  (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
  (local position (or layout.position (glm.vec3 0 0 0)))
  (assert-finite-vec3 size "size")
  (assert-finite-quat rotation "rotation")
  (assert-finite-vec3 position "position")
  (local points [])
  (for [ix 0 1]
    (for [iy 0 1]
      (for [iz 0 1]
        (local local-point (glm.vec3 (if (= ix 0) 0 size.x)
                                 (if (= iy 0) 0 size.y)
                                 (if (= iz 0) 0 size.z)))
        (local rotated (rotation:rotate local-point))
        (table.insert points (+ position rotated)))))
  points)

(fn layout-clip-relationship [layout]
  (local clip (and layout layout.clip-region))
  (local bounds (and clip clip.bounds))
  (if (not bounds)
      :inside
      (let [corners (layout-world-corners layout)
            clip-position (or bounds.position (glm.vec3 0 0 0))
            clip-rotation (or bounds.rotation (glm.quat 1 0 0 0))
            clip-size (or bounds.size (glm.vec3 0 0 0))
            inverse (clip-rotation:inverse)
            min-corner (glm.vec3 500000 500000 500000)
            max-corner (glm.vec3 -500000 -500000 -500000)]
        (fn finite-number? [value]
          (and (= (type value) :number)
               (= value value)
               (not (= value math.huge))
               (not (= value (- math.huge)))))
        (fn assert-finite-vec3 [vec label]
          (when (or (not vec)
                    (not (finite-number? vec.x))
                    (not (finite-number? vec.y))
                    (not (finite-number? vec.z)))
            (error (.. "Layout clip bounds has non-finite " label))))
        (assert-finite-vec3 clip-position "position")
        (assert-finite-vec3 clip-size "size")
        (each [_ point (ipairs corners)]
          (local local-point (inverse:rotate (- point clip-position)))
          (assert-finite-vec3 local-point "local-point")
          (for [axis 1 3]
            (local value (. local-point axis))
            (when (< value (. min-corner axis))
              (set (. min-corner axis) value))
            (when (> value (. max-corner axis))
              (set (. max-corner axis) value))))
        (local epsilon position-epsilon)
        (var outside? false)
        (var fully-inside? true)
        (for [axis 1 3]
          (local axis-min (. min-corner axis))
          (local axis-max (. max-corner axis))
          (local axis-size (. clip-size axis))
          (when (> axis-min (+ axis-size epsilon))
            (set outside? true))
          (when (< axis-max (- epsilon))
            (set outside? true))
          (when (< axis-min (- epsilon))
            (set fully-inside? false))
          (when (> axis-max (+ axis-size epsilon))
            (set fully-inside? false)))
        (if outside?
            :outside
            (if fully-inside? :inside :partial)))))

(fn Layout [opts]
  (set opts.name (or opts.name "layout"))
  (set opts.root nil)
  (set opts.parent nil)
  (set opts.depth nil)
  (set opts.position (glm.vec3 0))
  (set opts.rotation (glm.quat 1 0 0 0))
  (set opts.measure (glm.vec3 0))
  (set opts.size (glm.vec3 0))
  (set opts.depth-offset-index 0)
  (set opts.clip-region (or opts.clip-region nil))
  (set opts.measure-dirty false)
  (set opts.layout-dirty false)
  (set opts.measurer (or opts.measurer (fn [])))
  (local base-layouter (or opts.layouter (fn [])))
  (local base-measurer opts.measurer)
  (set opts.layouter nil)
  (set opts.culled? false)
  (set opts.parent-culled? false)
  (set opts.clip-visibility :inside)
  (set opts.last-effective-state false)

  (fn effective-culled? [self]
    (or self.culled? self.parent-culled?))

  (fn propagate-culling [self]
    (local effective (self:effective-culled?))
    (when self.children
      (each [_ child (ipairs self.children)]
        (when child
          (child:set-parent-culled effective)))))

  (fn set-self-culled [self culled?]
    (if (= culled? self.culled?)
        nil
        (do
          (set self.culled? culled?)
          (propagate-culling self))))

  (fn set-parent-culled [self culled?]
    (if (= culled? self.parent-culled?)
        nil
        (do
          (set self.parent-culled? culled?)
          (propagate-culling self))))

  (fn compute-clip-visibility [self]
    (layout-clip-relationship self))

  (fn get-ancestor-names [self]
    (local names [])
    (var node self.parent)
    (while node
      (table.insert names 1 node.name)
      (set node node.parent))
    names)

  (fn find-ancestor-field [self field]
    (assert field "Layout find-ancestor-field requires a field")
    (var node self)
    (var value nil)
    (while (and node (not value))
      (set value (rawget node field))
      (set node node.parent))
    value)

  (fn run-measurer [self skip-dirt-clear?]
    (local root self.root)
    (when (and root root.measure-dirt (not skip-dirt-clear?))
      (root.measure-dirt:remove self))
    (base-measurer self))

  (fn run-layouter [self skip-dirt-clear?]
    (local root self.root)
    (when (and root root.layout-dirt (not skip-dirt-clear?))
      (root.layout-dirt:remove self))
    (local previous-effective (or self.last-effective-state false))
    (local own-visibility (self:compute-clip-visibility))
    (local effective-visibility (if self.parent-culled?
                                     :culled
                                     own-visibility))
      (set self.clip-visibility effective-visibility)
      (if (= own-visibility :outside)
          (self:set-self-culled true)
          (self:set-self-culled false))
      (local new-effective (self:effective-culled?))
      (set self.last-effective-state new-effective)
      (when (or (not new-effective)
                (not (= new-effective previous-effective)))
        (base-layouter self)))

  (fn set-children [self children]
    (self:clear-children)
    (self:add-children children))

  (fn clear-children [self]
    (when self.children
      (while (> (length self.children) 0)
        (self:remove-child (length self.children)))))

  (fn remove-child [self idx]
    (local child (. self.children idx))
    (set child.parent nil)
    (child:set-root nil)
    (child:set-parent-culled false)
    (table.remove self.children idx))

  (fn add-children [self children]
    (each [i x (ipairs children)]
      (self:add-child x)))

  (fn add-child [self child]
    (set child.parent self)
    (child:set-root self.root)
    (set child.depth-offset-index self.depth-offset-index)
    (set child.clip-region self.clip-region)
    (child:set-parent-culled (self:effective-culled?))
    (table.insert self.children child))

  (fn set-root [self root]
    (local stack [])
    (var node self)
    (while node
      (each [_ x (ipairs node.children)]
        (table.insert stack x))
      (local old-root node.root)
      (set node.root root)
      (if root
          (set node.depth (if node.parent
                              (+ (or node.parent.depth 0) 1)
                              0))
          (set node.depth nil))
      (if
        root (do
               (when node.measure-dirty
                 (root.measure-dirt:enqueue node node.depth)
                 (set node.measure-dirty false))
               (when node.layout-dirty
                 (root.layout-dirt:enqueue node node.depth)
                 (set node.layout-dirty false)))
        old-root (do
                   (old-root.measure-dirt:remove node)
                   (old-root.layout-dirt:remove node)))
      (set node (table.remove stack))
      ))

  (fn assert-not-in-pass [self]
    (when (and self.root self.root.in-pass)
      (error (.. self.name " cannot mark dirt during layout pass"))))

  (fn mark-layout-dirty [self]
    (self:assert-not-in-pass)
    (if
      self.root (self.root.layout-dirt:enqueue self self.depth)
      (set self.layout-dirty true)))

  (fn mark-measure-dirty [self]
    (self:assert-not-in-pass)
    (if
      self.root (self.root.measure-dirt:enqueue self self.depth)
      (set self.measure-dirty true)))

  (fn set-position [self position]
    (if (vec3-equal? self.position position)
        nil
        (do
          (set self.position position)
          (self:mark-layout-dirty))))

  (fn set-rotation [self rotation]
    (if (quat-equal? self.rotation rotation)
        nil
        (do
          (set self.rotation rotation)
          (self:mark-layout-dirty))))

  (fn drop [self]
    (self:clear-children)
    (when self.root
      (self.root.measure-dirt:remove self)
      (self.root.layout-dirt:remove self)))

  (fn intersect [self ray]
    (let [(hit point distance)
          (ray-box-intersection ray {:position self.position
                                     :rotation self.rotation
                                     :size self.size})]
      (if (and hit (clip-allows-point? self.clip-region point))
          (values true point distance)
          (values false nil nil))))

  (local o {:name opts.name :root opts.root :parent opts.parent :children []
            :position opts.position :rotation opts.rotation
            :measure opts.measure :size opts.size
            :depth opts.depth
            :measure-dirty opts.measure-dirty
            :layout-dirty opts.layout-dirty
            :depth-offset-index opts.depth-offset-index
            :clip-region opts.clip-region
            :culled? opts.culled?
            :parent-culled? opts.parent-culled?
            :clip-visibility opts.clip-visibility
            :last-effective-state opts.last-effective-state
            :measurer run-measurer :layouter nil
            :set-children set-children :clear-children clear-children
            :remove-child remove-child :add-children add-children
            :add-child add-child
            :set-root set-root :mark-layout-dirty mark-layout-dirty
            :mark-measure-dirty mark-measure-dirty
            :set-position set-position :set-rotation set-rotation
            :drop drop :intersect intersect
            :get-ancestor-names get-ancestor-names
            :find-ancestor-field find-ancestor-field
            :assert-not-in-pass assert-not-in-pass
            :set-self-culled set-self-culled
            :set-parent-culled set-parent-culled
            :effective-culled? effective-culled?
            :compute-clip-visibility compute-clip-visibility})
  (set o.layouter run-layouter)
  (o:set-children (or opts.children []))
  o)

(fn table-size [tbl]
  (var count 0)
  (each [_ _ (pairs tbl)]
    (set count (+ count 1)))
  count)

(fn LayoutRoot [opts]
  (local options (or opts {}))
  (local log-dirt? (or options.log-dirt? false))
  (assert appdirs "appdirs module is required for layout logging")
  (local log-dir (appdirs.user-log-dir "space"))
  (local log-path (if (and app.engine fs.join-path)
	                      (fs.join-path log-dir "dirt.log")
	                      (.. log-dir "/dirt.log")))
  (local stats {:records [] :max-records max-stats-frames})
  (local measure-timer (make-pass-timer))
  (local layout-timer (make-pass-timer))
  (local measure-queue (make-depth-bucket-queue {:label "measure"}))
  (local layout-queue (make-depth-bucket-queue {:label "layout"}))

  (when log-dirt?
    (when (and fs fs.parent fs.create-dirs)
      (pcall (fn [] (fs.create-dirs (fs.parent log-path)))))
    (local handle (io.open log-path "w"))
    (when handle
      (handle:close)))

  (fn record-stats [entry]
    (table.insert stats.records entry)
    (local max-records (or stats.max-records max-stats-frames))
    (local extra (- (length stats.records) max-records))
    (when (> extra 0)
      (for [i 1 extra]
        (table.remove stats.records 1))))

  (fn lineage-lines [iter-fn]
    (local lines [])
    (iter-fn
     (fn [node]
       (local lineage (node:get-ancestor-names))
       (table.insert lineage node.name)
       (table.insert lines (table.concat lineage " > "))))
    (table.sort lines)
    lines)

  (fn log-dirt [self frame-id]
    (when (and log-dirt? (< frame-id 2))
      (local lines [(.. "[layout-root dirt] frame=" frame-id)])
      (fn emit [label iter-fn]
        (table.insert lines (.. "  " label ":"))
        (local entries (lineage-lines iter-fn))
        (if (> (length entries) 0)
            (each [_ line (ipairs entries)]
              (table.insert lines (.. "    " line)))
            (table.insert lines "    (empty)")))
      (emit "measure-dirt" (fn [f]
                             (self.measure-dirt:iterate
                              (fn [node _depth] (f node)))))
      (emit "layout-dirt" (fn [f]
            (self.layout-dirt:iterate (fn [node _depth] (f node)))))
      (local handle (io.open log-path "a"))
      (when handle
        (each [_ line (ipairs lines)]
          (handle:write line "\n"))
        (handle:close))))

  (fn update [self]
    (local frame-id (or (and app.engine app.engine.frame-id) 0))
    (set self.in-pass true)
    (log-dirt self frame-id)
    (measure-timer.begin)
    (self.measure-dirt:iterate
     (fn [node _depth]
       (var n node)
       (while n.parent
         (set n n.parent))
       (n:measurer true)
       (measure-timer.tick)
       (self.layout-dirt:enqueue n n.depth)))
    (self.measure-dirt:clear)
    (local measure-pass (measure-timer.finish))

    (layout-timer.begin)
    (self.layout-dirt:iterate
     (fn [node _depth]
       (node:layouter true)
       (layout-timer.tick)))
    (self.layout-dirt:clear)
    (local layout-pass (layout-timer.finish))

    (when (or (> measure-pass.count 0) (> layout-pass.count 0))
      (record-stats {:frame-id frame-id
                     :measure-dirt measure-pass.count
                     :layout-delta layout-pass.delta
                     :measure-delta measure-pass.delta
                     :layout-dirt layout-pass.count}))
    (set self.in-pass false))

  (local root {:update update :measure-dirt measure-queue :layout-dirt layout-queue
               :stats stats :log-dirt? log-dirt? :in-pass false})
  root)

{: Layout : LayoutRoot : resolve-mark-flag}
