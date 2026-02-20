(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local Utils (require :graph/view/utils))

(local KERNELS_RED (glm.vec4 0.8 0.25 0.2 1))
(local KERNELS_RED_ACCENT (glm.vec4 0.9 0.3 0.25 1))

(fn kernel-label [manager kernel]
  (local base (manager:kernel-label kernel))
  (local instance-count (length (manager:list-instances {:kernel-id kernel.id})))
  (Utils.truncate-with-ellipsis (.. base " [" (tostring instance-count) "]") 60))

(fn KernelsNode [opts]
  (local options (or opts {}))
  (local Kernels (require :kernels))
  (local manager (or options.kernels (and app app.kernels) (Kernels.get-default)))
  (assert manager "KernelsNode requires kernels manager")
  (local KernelsNodeView (require :graph/view/views/kernels))
  (local {:KernelNode KernelNode} (require :graph/nodes/kernel))

  (local node
    (GraphNode {:key "kernels"
                :label "kernels"
                :color KERNELS_RED
                :sub-color KERNELS_RED_ACCENT
                :size 8.0
                :view KernelsNodeView}))

  (set node.kernels manager)
  (set node.items-changed (Signal))

  (set node.collect-items
       (fn [self]
         (local items [])
         (each [_ kernel (ipairs (self.kernels:list-kernels))]
           (table.insert items [kernel (kernel-label self.kernels kernel)]))
         items))

  (set node.emit-items
       (fn [self]
         (local items (self:collect-items))
         (self.items-changed:emit items)
         items))

  (set node.create-kernel
       (fn [self opts]
         (local (kernel err) (self.kernels:create-kernel opts))
         (when err
           (error err))
         (self:emit-items)
         kernel))

  (set node.add-kernel-node
       (fn [self kernel]
         (local graph self.graph)
         (when (and graph kernel (not (= (tostring kernel.id) "0")))
           (local kernel-node (KernelNode {:kernel-id kernel.id
                                           :kernels self.kernels}))
           (graph:add-edge (GraphEdge {:source self
                                       :target kernel-node})))))

  (set node.actions
       [{:name "Refresh"
         :icon "refresh"
         :fn (fn [_button _event]
               (node:emit-items))}
        {:name "Create Kernel"
         :icon "add"
         :fn (fn [_button _event]
               (node:create-kernel {}))}])

  (var kernels-handler nil)
  (var instances-handler nil)
  (set kernels-handler
       (manager.kernels-changed:connect
         (fn [_]
           (node:emit-items))))
  (set instances-handler
       (manager.instances-changed:connect
         (fn [_]
           (node:emit-items))))

  (set node.drop
       (fn [self]
         (when kernels-handler
           (manager.kernels-changed:disconnect kernels-handler true)
           (set kernels-handler nil))
         (when instances-handler
           (manager.instances-changed:disconnect instances-handler true)
           (set instances-handler nil))
         (self.items-changed:clear)))

  node)

KernelsNode
