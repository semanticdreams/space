(local Lines (require :lines))
(local Points (require :points))
(local DrawBatcher (require :draw-batcher))

(local {:VectorBuffer VectorBuffer :VectorHandle VectorHandle} (require :vector-buffer))
(fn BuildContext [opts]
  (local options (or opts {}))
  (local triangle-vector (VectorBuffer))
  (local line-vector (VectorBuffer))
  (local point-vector (VectorBuffer))
  (local text-vectors {})
  (local image-batches {})
  (local mesh-batches [])
  (local line-strips [])
  (local triangle-batches (DrawBatcher {:stride 8}))
  (local text-draw-batchers {})
  (fn register-line-strip [vector]
    (table.insert line-strips vector)
    vector)
  (fn unregister-line-strip [vector]
    (for [i 1 (length line-strips)]
      (when (= (. line-strips i) vector)
        (table.remove line-strips i)
        (lua "break")))
    nil)
  (local ctx
    {:triangle-vector triangle-vector
     :line-vector line-vector
     :point-vector point-vector
     :text-vectors text-vectors
     :image-batches image-batches
     :mesh-batches mesh-batches
     :line-strips line-strips
     :pointer-target options.pointer-target
     :clickables options.clickables
     :hoverables options.hoverables
     :system-cursors options.system-cursors
     :icons options.icons
     :states options.states
     :object-selector options.object-selector
     :layout-root options.layout-root
     :movables options.movables
     :theme options.theme
     :get-text-vector (fn [self font]
	                        (when (not (. self.text-vectors font))
	                          (set (. self.text-vectors font) (VectorBuffer)))
	                        (when (not (. text-draw-batchers font))
	                          (set (. text-draw-batchers font) (DrawBatcher {:stride 10})))
	                        (. self.text-vectors font))})
  (set ctx.set-theme (fn [self theme]
                       (set self.theme theme)))
  (set ctx.register-line-strip (fn [_self vector]
                                 (register-line-strip vector)))
  (set ctx.unregister-line-strip (fn [_self vector]
                                   (unregister-line-strip vector)))
  (set ctx.lines (Lines {:line-vector line-vector
                         :register-line-strip register-line-strip
                         :unregister-line-strip unregister-line-strip}))
  (set ctx.points (Points {:point-vector point-vector}))
  (set ctx.track-triangle-handle
       (fn [_self handle clip-region model]
         (triangle-batches:track-handle handle clip-region model)))
  (set ctx.untrack-triangle-handle
       (fn [_self handle]
         (triangle-batches:untrack-handle handle)))
  (set ctx.get-triangle-batches
       (fn [_self]
         (triangle-batches:get-batches)))
  (set ctx.track-text-handle
       (fn [_self font handle clip-region model]
         (local batcher (. text-draw-batchers font))
         (when batcher
           (batcher:track-handle handle clip-region model))))
  (set ctx.untrack-text-handle
       (fn [_self font handle]
         (local batcher (. text-draw-batchers font))
         (when batcher
           (batcher:untrack-handle handle))))
  (set ctx.get-text-batches
       (fn [_self]
         (local batches {})
         (each [font vector (pairs text-vectors)]
           (local batcher (. text-draw-batchers font))
           (set (. batches font) (and batcher (batcher:get-batches))))
         batches))
  (set ctx.get-image-batch
       (fn [_self texture]
         (assert (and texture texture.id)
                 "Image batch requires a texture with an id")
         (local id texture.id)
	         (when (not (. image-batches id))
	           (set (. image-batches id)
	                {:texture texture
	                 :vector (VectorBuffer)
	                 :id id
	                 :draw-batcher (DrawBatcher {:stride 10})}))
         (. image-batches id)))
  (set ctx.register-mesh-batch
       (fn [_self batch]
         (table.insert mesh-batches batch)
         batch))
  (set ctx.unregister-mesh-batch
       (fn [_self batch]
         (for [i 1 (length mesh-batches)]
           (when (= (. mesh-batches i) batch)
             (table.remove mesh-batches i)
             (lua "break")))
         nil))
  (set ctx.get-mesh-batches
       (fn [_self]
         mesh-batches))
  (set ctx.track-image-handle
       (fn [_self batch handle clip-region model]
         (local batcher (and batch batch.draw-batcher))
         (when batcher
           (batcher:track-handle handle clip-region model))))
  (set ctx.untrack-image-handle
       (fn [_self batch handle]
         (local batcher (and batch batch.draw-batcher))
         (when batcher
           (batcher:untrack-handle handle))))
  (local focus-manager options.focus-manager)
  (local focus-scope options.focus-scope)
  (when (and focus-manager focus-scope)
    (local focus-parent (or options.focus-parent (focus-manager:get-root-scope)))
    (when (and (not focus-scope.parent) (not focus-scope.is-root?))
      (focus-manager:attach focus-scope focus-parent))
    (local ensure-scope-belongs
      (fn [scope]
        (assert scope "Focus context requires a scope")
        (assert (= scope.manager focus-manager)
                "Focus scope belongs to another manager")
        scope))
    (local ensure-node-belongs
      (fn [node]
        (assert node "Focus context requires a node")
        (assert (= node.manager focus-manager)
                "Focus node belongs to another manager")
        node))
    (local resolve-parent
      (fn [self parent]
        (if parent
            (ensure-scope-belongs parent)
            (ensure-scope-belongs self.scope))))
    (local focus-ctx {:manager focus-manager
                      :scope focus-scope})
    (set focus-ctx.get-scope (fn [self] self.scope))
    (set focus-ctx.set-scope
         (fn [self scope]
           (ensure-scope-belongs scope)
           (set self.scope scope)
           self))
    (set focus-ctx.attach
         (fn [self node parent]
           (ensure-node-belongs node)
           (focus-manager:attach node (resolve-parent self parent))
           node))
    (set focus-ctx.attach-at
         (fn [self node parent index]
           (ensure-node-belongs node)
           (focus-manager:attach-at node (resolve-parent self parent) index)
           node))
    (set focus-ctx.detach
         (fn [_self node]
           (ensure-node-belongs node)
           (focus-manager:detach node)
           node))
    (set focus-ctx.create-node
         (fn [self opts]
           (local node (focus-manager:create-node opts))
           (local parent (and opts opts.parent))
           (self:attach node parent)
           (when self._capture
             (table.insert self._capture node))
           node))
    (set focus-ctx.create-scope
         (fn [self opts]
           (local scope (focus-manager:create-scope opts))
           (local parent (and opts opts.parent))
           (self:attach scope parent)
           (when self._capture
             (table.insert self._capture scope))
           scope))
    (set focus-ctx.capture
         (fn [self f]
           (local nodes [])
           (set self._capture nodes)
           (local result (f))
           (set self._capture nil)
           (values result nodes)))
    (set focus-ctx.attach-bounds
         (fn [_self node opts]
           (ensure-node-belongs node)
           (local options (or opts {}))
           (local layout (and options.layout options.layout))
           (local get-bounds (and options.get-bounds options.get-bounds))
           (local position (and options.position options.position))
           (local size (and options.size options.size))
           (when layout
             (set node.layout layout))
           (if get-bounds
               (set node.get-focus-bounds get-bounds)
               (if layout
                   (set node.get-focus-bounds
                        (fn [_self]
                          {:position layout.position
                           :size layout.size}))
                   (do
                     (set node.get-focus-bounds nil)
                     (when position
                       (set node.position position))
                     (when size
                       (set node.size size)))))
           node))
    (set ctx.focus focus-ctx))
  ctx)

BuildContext
