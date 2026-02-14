(local os os)
(local glm (require :glm))
(local glm-mat4-trs (. glm :mat4-trs))
(local glm-mat4-world-to-render (. glm :mat4-world-to-render))

(var render-version-counter 0)
(var transform-version-counter 0)

(fn alloc-mat4 []
  (glm.mat4 1))

(fn mat4-copy! [out a]
  a)

(fn mat4-identity! [out]
  (glm.mat4 1))

(fn quat? [value]
  (and value
       (not (= (. value :w) nil))
       (not (= (. value :x) nil))
       (not (= (. value :y) nil))
       (not (= (. value :z) nil))))

(fn quat-equal? [a b]
  (and (= a.w b.w)
       (= a.x b.x)
       (= a.y b.y)
       (= a.z b.z)))

(fn resolve-rotation [rotation]
  (if (= rotation nil)
      (glm.quat 1 0 0 0)
      (do
        (assert (quat? rotation) "next-app layout rotation must be glm.quat")
        rotation)))

(fn mat4-from-translation-rotation! [out tx ty tz rotation]
  (glm-mat4-trs tx ty tz (resolve-rotation rotation)))

(fn mat4-mul! [out a b]
  (* a b))

(fn mat4-world-to-render! [out world sx sy sz]
  (glm-mat4-world-to-render world sx sy sz))

(local Node {})
(set Node.__index Node)

(fn ensure-root-state [root]
  (when (not root._measure-roots)
    (set root._measure-roots [])
    (set root._layout-roots [])
    (set root._transform-roots [])
    (set root._submit-nodes [])
    (set root._initialized false)))

(fn push-root-once [roots node key]
  (when (not (. node key))
    (set (. node key) true)
    (table.insert roots node)))

(fn push-submit-node [node]
  (local root node.root)
  (ensure-root-state root)
  (when (not node._submit-queued)
    (set node._submit-queued true)
    (table.insert root._submit-nodes node)))

(fn set-root-recursive [node root]
  (local stack [node])
  (while (> (length stack) 0)
    (local current (table.remove stack))
    (set current.root root)
    (each [_ child (ipairs current.children)]
      (table.insert stack child))))

(fn should-mark? [opts]
  (if (and opts (= (. opts :mark-dirty?) false))
      false
      true))

(fn bump-render-version [node]
  (set render-version-counter (+ render-version-counter 1))
  (set node._render-version render-version-counter)
  (push-submit-node node))

(fn mark-layout-dirty-upward [node]
  (local root node.root)
  (ensure-root-state root)
  (var current node)
  (var topmost-new nil)
  (var blocked-by-ancestor false)
  (while current
    (if current._layout-dirty
        (do
          (set blocked-by-ancestor true)
          (set current nil))
        (do
          (set current._layout-dirty true)
          (set topmost-new current)
          (set current current.parent))))
  (when (and topmost-new (not blocked-by-ancestor))
    (push-root-once root._layout-roots topmost-new "_layout-root-queued")))

(fn mark-measure-dirty-upward [node]
  (local root node.root)
  (ensure-root-state root)
  (var current node)
  (var topmost-new nil)
  (var blocked-by-ancestor false)
  (while current
    (if current._measure-dirty
        (do
          (set blocked-by-ancestor true)
          (set current nil))
        (do
          (set current._measure-dirty true)
          (set current._layout-dirty true)
          (set topmost-new current)
          (set current current.parent))))
  (when (and topmost-new (not blocked-by-ancestor))
    (push-root-once root._measure-roots topmost-new "_measure-root-queued")
    (push-root-once root._layout-roots topmost-new "_layout-root-queued")))

(fn mark-transform-dirty-root [node]
  (local root node.root)
  (ensure-root-state root)
  (var current node)
  (var blocked-by-ancestor false)
  (while current
    (if current._transform-dirty
        (do
          (set blocked-by-ancestor true)
          (set current nil))
        (set current current.parent)))
  (when (not blocked-by-ancestor)
    (set node._transform-dirty true)
    (push-root-once root._transform-roots node "_transform-root-queued")))

(fn set-measure [self w h d]
  (set self.measured-width (or w 0))
  (set self.measured-height (or h 0))
  (set self.measured-depth (or d 0)))

(fn set-size [self w h d opts]
  (local next-w (or w 0))
  (local next-h (or h 0))
  (local next-d (or d 0))
  (local changed?
    (or (not (= self.width next-w))
        (not (= self.height next-h))
        (not (= self.depth next-d))))
  (set self.width next-w)
  (set self.height next-h)
  (set self.depth next-d)
  (when changed?
    (bump-render-version self))
  (when (and changed? (should-mark? opts))
    (mark-layout-dirty-upward self)
    (mark-transform-dirty-root self)))

(fn set-local-position [self x y z rotation opts]
  (local next-x (or x 0))
  (local next-y (or y 0))
  (local next-z (or z 0))
  (local next-rotation (resolve-rotation rotation))
  (local changed?
    (or (not (= self.local-x next-x))
        (not (= self.local-y next-y))
        (not (= self.local-z next-z))
        (not (quat-equal? self.local-rotation next-rotation))))
  (set self.local-x next-x)
  (set self.local-y next-y)
  (set self.local-z next-z)
  (set self.local-rotation next-rotation)
  (when changed?
    (set self.local-matrix
         (mat4-from-translation-rotation! self.local-matrix
                                          self.local-x
                                          self.local-y
                                          self.local-z
                                          self.local-rotation))
    (bump-render-version self))
  (when (and changed? (should-mark? opts))
    (mark-transform-dirty-root self)))

(fn set-frame [self x y z w h d rotation opts]
  (set-size self w h d opts)
  (set-local-position self x y z rotation opts))

(fn layout-set-frame [self x y z w h d rotation]
  (local next-w (or w 0))
  (local next-h (or h 0))
  (local next-d (or d 0))
  (local next-x (or x 0))
  (local next-y (or y 0))
  (local next-z (or z 0))
  (local next-rotation (resolve-rotation rotation))
  (local size-changed
    (or (not (= self.width next-w))
        (not (= self.height next-h))
        (not (= self.depth next-d))))
  (local transform-changed
    (or (not (= self.local-x next-x))
        (not (= self.local-y next-y))
        (not (= self.local-z next-z))
        (not (quat-equal? self.local-rotation next-rotation))))
  (set self.width next-w)
  (set self.height next-h)
  (set self.depth next-d)
  (set self.local-x next-x)
  (set self.local-y next-y)
  (set self.local-z next-z)
  (set self.local-rotation next-rotation)
  (when transform-changed
    (set self.local-matrix
         (mat4-from-translation-rotation! self.local-matrix
                                          self.local-x
                                          self.local-y
                                          self.local-z
                                          self.local-rotation)))
  (when (or size-changed transform-changed)
    (bump-render-version self))
  (if transform-changed
      (mark-transform-dirty-root self)
      (when size-changed
        (set self.render-matrix
             (mat4-world-to-render! self.render-matrix
                                    self.world-matrix
                                    self.width
                                    self.height
                                    (if (= self.depth 0) 1 self.depth)))))
  self)

(fn add-child [self child]
  (assert child "next-app layout add-child requires child")
  (assert (= child.parent nil) "next-app layout child already has parent")
  (set child.parent self)
  (table.insert self.children child)
  (set-root-recursive child self.root)
  (bump-render-version self)
  (mark-measure-dirty-upward self)
  (mark-transform-dirty-root child)
  child)

(fn clear-children [self]
  (when (> (length self.children) 0)
    (each [_ child (ipairs self.children)]
      (set child.parent nil)
      (set-root-recursive child child))
    (set self.children [])
    (bump-render-version self)
    (mark-measure-dirty-upward self)
    (mark-transform-dirty-root self)))

(fn mark-measure-dirty [self]
  (mark-measure-dirty-upward self))

(fn mark-layout-dirty [self]
  (mark-layout-dirty-upward self)
  (mark-transform-dirty-root self))

(fn mark-transform-dirty [self]
  (mark-transform-dirty-root self))

(fn mark-render-dirty [self]
  (bump-render-version self))

(fn run-measure-subtree [self max-width max-height max-depth]
  (set self._measure-dirty false)
  (if self.measure-fn
      (self.measure-fn self max-width max-height max-depth)
      (if (> (length self.children) 0)
          (do
            (var max-w 0)
            (var max-h 0)
            (var max-d 0)
            (each [_ child (ipairs self.children)]
              (child:run-measure-subtree max-width max-height max-depth)
              (when (> child.measured-width max-w)
                (set max-w child.measured-width))
              (when (> child.measured-height max-h)
                (set max-h child.measured-height))
              (when (> child.measured-depth max-d)
                (set max-d child.measured-depth)))
            (self:set-measure max-w max-h max-d))
          (self:set-measure self.width self.height self.depth)))
  self)

(fn run-layout-subtree [self width height depth]
  (set self._layout-dirty false)
  (when (not (= width nil))
    (set-size self width height depth {:mark-dirty? false}))
  (if self.layout-fn
      (self.layout-fn self self.width self.height self.depth)
      (each [_ child (ipairs self.children)]
        (child:run-layout-subtree child.measured-width child.measured-height child.measured-depth)))
  self)

(fn transform-pass [self parent-world parent-changed]
  (local inherited-change (if (= parent-changed nil) true parent-changed))
  (local changed (or inherited-change self._transform-dirty))
  (when changed
    (set transform-version-counter (+ transform-version-counter 1))
    (set self._transform-version transform-version-counter)
    (set self._subtree-render-version self._transform-version)
    (set self._transform-dirty false)
    (if parent-world
        (set self.world-matrix (* parent-world self.local-matrix))
        (set self.world-matrix self.local-matrix))
    (set self.render-matrix
         (mat4-world-to-render! self.render-matrix
                                self.world-matrix
                                self.width
                                self.height
                                (if (= self.depth 0) 1 self.depth)))
    (push-submit-node self))
  (each [_ child (ipairs self.children)]
    (when (or changed child._transform-dirty)
      (child:transform-pass self.world-matrix changed)))
  self)

(fn Node.new [opts]
  (local options (or opts {}))
  (local self (setmetatable
                {:name (or options.name "next-layout-node")
                 :children []
                 :parent nil
                 :root nil
                 :measure-fn options.measure-fn
                 :layout-fn options.layout-fn
                 :userdata options.userdata
                 :measured-width 0
                 :measured-height 0
                 :measured-depth 0
                 :width 0
                 :height 0
                 :depth 0
                 :local-x 0
                 :local-y 0
                 :local-z 0
                 :local-rotation (glm.quat 1 0 0 0)
                 :local-matrix (alloc-mat4)
                 :world-matrix (alloc-mat4)
                 :render-matrix (alloc-mat4)
                 :_measure-dirty false
                 :_layout-dirty false
                 :_transform-dirty false
                 :_measure-root-queued false
                 :_layout-root-queued false
                 :_transform-root-queued false
                 :_submit-queued false
                 :_render-version 0
                 :_subtree-render-version 0
                 :_transform-version 0}
                Node))
  (set self.root self)
  (ensure-root-state self)
  (set-size self options.width options.height options.depth {:mark-dirty? false})
  (set-local-position self options.x options.y options.z options.rotation {:mark-dirty? false})
  (when options.children
    (each [_ child (ipairs options.children)]
      (self:add-child child)))
  self)

(set Node.set-measure set-measure)
(set Node.set-size set-size)
(set Node.set-local-position set-local-position)
(set Node.set-frame set-frame)
(set Node.layout-set-frame layout-set-frame)
(set Node.add-child add-child)
(set Node.clear-children clear-children)
(set Node.mark-measure-dirty mark-measure-dirty)
(set Node.mark-layout-dirty mark-layout-dirty)
(set Node.mark-transform-dirty mark-transform-dirty)
(set Node.mark-render-dirty mark-render-dirty)
(set Node.run-measure-subtree run-measure-subtree)
(set Node.run-layout-subtree run-layout-subtree)
(set Node.run-measure run-measure-subtree)
(set Node.run-layout run-layout-subtree)
(set Node.transform-pass transform-pass)

(fn process-measure [root width height depth]
  (local queue root._measure-roots)
  (set root._measure-roots [])
  (var processed 0)
  (each [_ node (ipairs queue)]
    (set node._measure-root-queued false)
    (when node._measure-dirty
      (set processed (+ processed 1))
      (if node.parent
          (node:run-measure-subtree node.parent.width node.parent.height node.parent.depth)
          (node:run-measure-subtree width height depth))))
  processed)

(fn process-layout [root width height depth]
  (local queue root._layout-roots)
  (set root._layout-roots [])
  (var processed 0)
  (each [_ node (ipairs queue)]
    (set node._layout-root-queued false)
    (when node._layout-dirty
      (set processed (+ processed 1))
      (if node.parent
          (node:run-layout-subtree node.width node.height node.depth)
          (node:run-layout-subtree width height depth))))
  processed)

(fn process-transform [root]
  (local queue root._transform-roots)
  (set root._transform-roots [])
  (var processed 0)
  (each [_ node (ipairs queue)]
    (set node._transform-root-queued false)
    (when node._transform-dirty
      (set processed (+ processed 1))
      (if node.parent
          (node:transform-pass node.parent.world-matrix false)
          (node:transform-pass nil true))))
  processed)

(fn begin-submit-collection [root]
  (each [_ node (ipairs root._submit-nodes)]
    (set node._submit-queued false))
  (set root._submit-nodes []))

(fn collect-submit-nodes [root]
  (local top (or root.root root))
  (ensure-root-state top)
  top._submit-nodes)

(fn run-frame-internal [root width height depth collect-stats?]
  (assert root "next-app layout run-frame requires root")
  (local top (or root.root root))
  (ensure-root-state top)
  (begin-submit-collection top)
  (when (not top._initialized)
    (mark-measure-dirty-upward top)
    (mark-transform-dirty-root top)
    (set top._initialized true))

  (if collect-stats?
      (do
        (local measure-start (os.clock))
        (local measure-count (process-measure top width height depth))
        (local measure-seconds (- (os.clock) measure-start))

        (local layout-start (os.clock))
        (local layout-count (process-layout top width height depth))
        (local layout-seconds (- (os.clock) layout-start))

        (local transform-start (os.clock))
        (local transform-count (process-transform top))
        (local transform-seconds (- (os.clock) transform-start))

        (local stats {:measure-seconds measure-seconds
                      :layout-seconds layout-seconds
                      :transform-seconds transform-seconds
                      :measure-rounds (if (> measure-count 0) 1 0)
                      :layout-rounds (if (> layout-count 0) 1 0)
                      :transform-rounds (if (> transform-count 0) 1 0)
                      :measure-nodes measure-count
                      :layout-nodes layout-count
                      :transform-nodes transform-count
                      :submit-nodes (length top._submit-nodes)})
        (set top._last-frame-stats stats)
        stats)
      (do
        (process-measure top width height depth)
        (process-layout top width height depth)
        (process-transform top)
        top)))

(fn run-frame [root width height depth]
  (run-frame-internal root width height depth false))

(fn run-frame-profile [root width height depth]
  (run-frame-internal root width height depth true))

{:Node Node
 :run-frame run-frame
 :run-frame-profile run-frame-profile
 :collect-submit-nodes collect-submit-nodes
 :mat4-identity! mat4-identity!
 :mat4-copy! mat4-copy!
 :mat4-mul! mat4-mul!
 :mat4-from-translation-rotation! mat4-from-translation-rotation!
 :mat4-world-to-render! mat4-world-to-render!}
