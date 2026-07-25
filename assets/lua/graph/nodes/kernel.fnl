(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))

(local KERNEL_COLOR (glm.vec4 0.75 0.35 0.2 1))
(local KERNEL_ACCENT (glm.vec4 0.85 0.4 0.25 1))

(fn KernelNode [opts]
  (local options (or opts {}))
  (local kernel-id (assert options.kernel-id "KernelNode requires kernel-id"))
  (local Kernels (require :kernels))
  (local manager (or options.kernels (and app app.kernels) (Kernels.get-default)))
  (assert manager "KernelNode requires kernels manager")
  (local KernelNodeView (require :graph/view/views/kernel))
  (local {:KernelInstanceNode KernelInstanceNode} (require :graph/nodes/kernel-instance))

  (local kernel (manager:get-kernel kernel-id))
  (assert kernel (.. "Kernel not found: " (tostring kernel-id)))

  (local node
    (GraphNode {:key (.. "kernel:" (tostring kernel-id))
                :label (manager:kernel-label kernel)
                :color KERNEL_COLOR
                :sub-color KERNEL_ACCENT
                :size 8.0
                :view KernelNodeView}))

  (set node.kernel-id kernel-id)
  (set node.kernels manager)
  (set node.changed (Signal))

  (set node.get-kernel
       (fn [self]
         (self.kernels:get-kernel self.kernel-id)))

  (set node.get-instance
       (fn [self instance-id]
         (self.kernels:get-instance instance-id)))

  (set node.list-instances
       (fn [self]
         (self.kernels:list-instances {:kernel-id self.kernel-id})))

  (set node.update-name
       (fn [self value]
         (self.kernels:update-kernel self.kernel-id {:name value})))

  (set node.update-cmd
       (fn [self value]
         (self.kernels:update-kernel self.kernel-id {:cmd value})))

  (set node.update-cwd
       (fn [self value]
         (self.kernels:update-kernel self.kernel-id {:cwd value})))

  (set node.create-instance
       (fn [self]
         (self.kernels:run-kernel self.kernel-id)))

  (set node.stop-instance
       (fn [self instance-id]
         (self.kernels:stop-instance instance-id)))

  (set node.delete-kernel
       (fn [self]
         (self.kernels:delete-kernel self.kernel-id)))

  (set node.add-instance-node
       (fn [self instance]
         (local graph self.graph)
         (when (and graph instance instance.id)
           (local instance-node (KernelInstanceNode {:instance-id instance.id
                                                     :kernels self.kernels}))
           (graph:add-edge (GraphEdge {:source self
                                       :target instance-node})))))

  (set node.refresh
       (fn [self]
         (local current (self:get-kernel))
         (when current
           (set self.label (self.kernels:kernel-label current)))
         (self.changed:emit self)))

  (set node.actions
       [{:name "Run Kernel"
         :icon "play_arrow"
         :fn (fn [_button _event]
               (node:create-instance))}
        {:name "Delete Kernel"
         :icon "delete"
         :fn (fn [_button _event]
               (node:delete-kernel))}])

  (var kernel-handler nil)
  (var instances-handler nil)
  (set kernel-handler
       (manager.kernels-changed:connect
         (fn [_]
           (local current (node:get-kernel))
           (if current
               (node:refresh)
               (when (and node.graph node.graph.remove-nodes)
                  (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))
  (set instances-handler
       (manager.instances-changed:connect
         (fn [_]
           (node:refresh))))

  (set node.drop
       (fn [self]
         (when kernel-handler
           (manager.kernels-changed:disconnect kernel-handler true)
           (set kernel-handler nil))
         (when instances-handler
           (manager.instances-changed:disconnect instances-handler true)
           (set instances-handler nil))
         (self.changed:clear)))

  node)

{:KernelNode KernelNode}
