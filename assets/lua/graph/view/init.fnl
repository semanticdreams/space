(local glm (require :glm))
(local appdirs (require :appdirs))
(local Signal (require :signal))

(local Utils (require :graph/view/utils))
(local GraphViewEdge (require :graph/view/edge))
(local GraphViewRegistry (require :graph/view/registry))
(local GraphViewLayout (require :graph/view/layout))
(local GraphViewMovables (require :graph/view/movables))
(local GraphViewLabels (require :graph/view/labels))
(local GraphViewSelection (require :graph/view/selection))
(local GraphViewNodeViews (require :graph/view/node-views))
(local GraphViewPersistence (require :graph/view/persistence))
(local NodeBase (require :graph/node-base))
(local LayeredPoint (require :layered-point))

(local new-triangle-line GraphViewEdge.new-triangle-line)
(local ensure-glm-vec3 Utils.ensure-glm-vec3)
(local ensure-glm-vec4 Utils.ensure-glm-vec4)
(local node-id NodeBase.node-id)

(local {:ForceLayout ForceLayout} (require :force-layout))
(local Modifiers (require :input-modifiers))
(local LinkEntityStore (require :entities/link))

(fn expand-linked-frontier [graph keys]
    (local store (LinkEntityStore.get-default))
    (local next-frontier [])
    (each [_ key (ipairs keys)]
        (local entities (store:find-entities-for-key key))
        (each [_ entity (ipairs entities)]
            (local other-key
                (if (= (tostring entity.source-key) (tostring key))
                    entity.target-key
                    entity.source-key))
            (graph:load-by-key other-key)
            (table.insert next-frontier (tostring other-key))))
    next-frontier)

(fn GraphView [opts]
    (local options (or opts {}))
    (local graph options.graph)
    (assert graph "GraphView requires a graph")
    (local ctx options.ctx)
    (assert ctx "GraphView requires a build context with triangle-vector and points")
    (local points (or ctx.points (and ctx ctx.points)))
    (local vector (and ctx ctx.triangle-vector))
    (local selector options.selector)
    (local selected-nodes [])
    (local selected-nodes-changed (Signal))
    (local node-by-point {})
    (local pinned {})
    (local view-target options.view-target)
    (local view-context (or options.view-context
                            (and view-target view-target.build-context)
                            ctx))
    (local movables options.movables)
    (local clickables (and ctx ctx.clickables))
    (local focus (and ctx ctx.focus))
    (local focus-manager (and focus focus.manager))
    (var points-focus-scope
         (and focus (focus:create-scope {:name "graph-node-points"
                                         :directional-traversal-boundary? true})))
    (local focus-nodes {})
    (local node-by-focus {})
    (var selected-set {})
    (var focused-node nil)
    (var selection-handler nil)
    (var focus-focus-handler nil)
    (var focus-blur-handler nil)
    (var movables-handler nil)
    (var register-movable nil)
    (var drag-active? false)
    (var drag-node nil)
    (var expand-seq-timestamp 0)
    (var expand-seq-frontier [])
    (local expand-seq-timeout 800)
    (assert points "GraphView requires ctx.points")
    (assert vector "GraphView requires ctx.triangle-vector")
    (assert focus "GraphView requires ctx.focus")
    (local layout (ForceLayout))
    (layout:set-bounds (glm.vec3 -1000 -90 0) (glm.vec3 1000 510 0))
    (local data-dir (or options.data-dir
                        (and appdirs (appdirs.user-data-dir "space"))))
    (assert data-dir "GraphView requires a data-dir for persistence")
    (local persistence (or options.persistence
                           (GraphViewPersistence {:data-dir data-dir})))
    (local theme (and ctx ctx.theme))
    (local graph-theme (and theme theme.graph))
    (local resolved-label-color (or options.label-color (and graph-theme graph-theme.label-color)))
    (local resolved-edge-color (or options.edge-color (and graph-theme graph-theme.edge-color)))
    (local selection-border-color (or options.selection-border-color
                                      (and graph-theme graph-theme.selection-border-color)))
    (assert selection-border-color "GraphView requires theme graph.selection-border-color")
    (local focus-outline-color (or options.focus-outline-color
                                   (and theme theme.input theme.input.focus-outline)))
    (assert focus-outline-color "GraphView requires theme input focus-outline")
    (local resolved-selection-border-color (ensure-glm-vec4 selection-border-color))
    (local resolved-focus-outline-color (ensure-glm-vec4 focus-outline-color))
    (local selection-border-width 2.0)
    (local focus-border-width 1.5)
    (local point-depth-offset-step 1)
    (local point-base-depth-offset 2)
    (local focus-layer-index 1)
    (local selection-layer-index 2)
    (local base-layer-index 3)
    (local labels (GraphViewLabels {:ctx ctx
                                :camera options.camera
                                :label-color resolved-label-color
                                :label-depth-offset (or options.label-depth-offset 1.0)
                                :camera-debounce-distance (or options.camera-debounce-distance 10.0)}))
    (local views (GraphViewNodeViews {:ctx ctx
                                      :view-target view-target
                                      :view-context view-context}))
    (local selection (GraphViewSelection {:selector selector
                                      :node-by-point node-by-point
                                      :selected-nodes selected-nodes
                                      :selected-nodes-changed selected-nodes-changed
                                      :node-id node-id
                                      :on-change (fn [_nodes] nil)}))

    (local nodes {})
    (local nodes-by-index [])
    (local indices {})
    (local edge-map {})
    (local edges [])
    (local pending-edges []) ;; Edges waiting for nodes
    (local node-changed-handlers {})
    (local registry
          (GraphViewRegistry {:nodes nodes
                          :nodes-by-index nodes-by-index
                          :indices indices
                          :points {}
                          :edge-map edge-map
                          :edges edges
                          :node-by-point node-by-point
                          :pinned pinned}))

    (assert clickables "GraphView requires clickables for node view double click")

    (fn update-point-state [node]
        (local point (. registry.points node))
        (when point
            (local base-size (or point.size 0))
            (local selected? (rawget selected-set node))
            (local focused? (= focused-node node))
            (local selection-size (if selected?
                                      (+ base-size selection-border-width)
                                      0))
            (local focus-size (if focused?
                                  (+ base-size
                                     (if selected? selection-border-width 0)
                                     focus-border-width)
                                  0))
            (point:set-layer-size focus-layer-index focus-size)
            (point:set-layer-size selection-layer-index selection-size)))

    (fn update-selection-set [nodes]
        (local next {})
        (each [_ node (ipairs (or nodes []))]
            (set (. next node) true))
        (local previous selected-set)
        (set selected-set next)
        (each [node _ (pairs previous)]
            (when (not (rawget next node))
                (update-point-state node)))
        (each [node _ (pairs next)]
            (when (not (rawget previous node))
                (update-point-state node))))

    (fn handle-focus-change [payload]
        (local previous-focus (and payload payload.previous))
        (local current-focus (and payload payload.current))
        (local previous-node (and previous-focus (. node-by-focus previous-focus)))
        (local current-node (and current-focus (. node-by-focus current-focus)))
        (set focused-node current-node)
        (when previous-node
            (update-point-state previous-node))
        (when current-node
            (update-point-state current-node)))

    (fn assert-valid-position [pos context node _point]
        (local key (and node node.key))
        (fn finite-number? [v]
            (and (= (type v) :number)
                 (= v v)
                 (not (= v math.huge))
                 (not (= v (- math.huge)))))
        (when (or (not pos)
                  (not (finite-number? pos.x))
                  (not (finite-number? pos.y))
                  (not (finite-number? pos.z)))
            (error (string.format "GraphView received non-finite position in %s for %s"
                                  context
                                  (or key "unknown node"))))
        (local magnitude (glm.length pos))
        (when (> magnitude 1e6)
            (error (string.format "GraphView position magnitude %.3f exceeds threshold for %s (%s) in %s"
                                  magnitude
                                  (or key "unknown node")
                                  (node-id node)
                                  context))))

    (fn next-position []
        (local center (ensure-glm-vec3 layout.center-position (glm.vec3 0 0 0)))
        (glm.vec3 (+ center.x (* (math.random) 100))
                  (+ center.y (* (math.random) 100))
                  center.z))

    (fn assert-point [_self node context]
        (assert node (string.format "GraphView missing node for %s" context))
        (local point (. registry.points node))
        (assert point (string.format "GraphView missing point for node %s (%s)"
                                     (node-id node)
                                     context))
        (assert point.position
                (string.format "GraphView missing position for node %s (%s)"
                               (node-id node)
                               context))
        point)

    (fn get-position [_self node]
        (local point (assert-point nil node "get-position"))
        (assert-valid-position point.position "GraphView.get-position" node point)
        (glm.vec3 point.position.x point.position.y point.position.z))

    (fn get-position-raw [_self node]
        (local point (assert-point nil node "get-position-raw"))
        (assert-valid-position point.position "GraphView.get-position-raw" node point)
        point.position)

    (fn set-point-position [node position source]
        (local point (. registry.points node))
        (assert point (string.format "GraphView.set-point-position missing point for node %s"
                                     (node-id node)))
        (local context (or source "GraphView.set-point-position"))
        (assert-valid-position position context node point)
        (if point.set-position-values
            (point:set-position-values position.x position.y position.z)
            (point:set-position position))
        (when movables-handler
            (movables-handler:update-position node position)))

    (fn update-labels [nodes opts]
        (labels:update registry.points nodes opts))

    (fn refresh-label-positions [nodes]
        (labels:refresh-positions registry.points nodes))

    (local graph-layout
          (GraphViewLayout {:layout layout
                        :nodes-by-index nodes-by-index
                        :indices indices
                        :nodes nodes
                        :points registry.points
                        :edges edges
                        :edge-map edge-map
                        :pinned pinned
                        :make-line new-triangle-line
                        :ctx ctx
                        :edge-color resolved-edge-color
                        :edge-thickness (or options.edge-thickness 2.0)
                        :label-color (or resolved-label-color (glm.vec4 0.8 0.8 0.8 1))
                        :label-depth-offset (or options.label-depth-offset 1.0)
                        :set-point-position set-point-position
                        :update-labels update-labels
                        :refresh-label-positions refresh-label-positions
                        :get-position get-position
                        :get-position-raw get-position-raw}))

    (set movables-handler
         (GraphViewMovables {:ctx ctx
                         :movables movables
                         :persistence persistence
                         :pointer-target options.pointer-target
                         :on-position (fn [node position]
                                           (graph-layout:set-node-position node position {:skip-labels? true}))
                         :on-drag-start (fn [node _entry]
                                            (set drag-active? true)
                                            (set drag-node node))
                         :on-drag-end (fn [node _entry]
                                          (set drag-active? false)
                                          (set drag-node nil)
                                          (update-labels [node] {:force? true})
                                          (refresh-label-positions [node]))}))

    (set register-movable
         (fn [node point]
             (when movables-handler
                 (movables-handler:register node point))))

    (fn detach-node-signals [node]
        (local record (. node-changed-handlers node))
        (when record
            (when (and record record.signal record.handler)
                (record.signal:disconnect record.handler true))
            (set (. node-changed-handlers node) nil)))

    (fn attach-node-signals [node]
        (when (and node node.changed node.changed.connect (not (. node-changed-handlers node)))
            (local handler
                (node.changed:connect
                    (fn [_payload]
                        (when (. registry.points node)
                            (update-labels [node] {:force? true})))))
            (set (. node-changed-handlers node) {:signal node.changed
                                                 :handler handler})))

    (fn update [_self _delta]
        (local moved-nodes (graph-layout:update))
        (each [node point (pairs registry.points)]
            (when (and point point.position)
                (assert-valid-position point.position "GraphView.update.persist" node point)))
        (when (not drag-active?)
            (update-labels nil nil)
            (refresh-label-positions moved-nodes))
        (persistence:persist registry.points false))

    (var update-handler nil)

    (fn connect-updates []
        (when (and app.engine app.engine.events app.engine.events.updated (not update-handler))
            (set update-handler
                 (app.engine.events.updated:connect update))))

    (fn drop-node-artifacts [node]
        (detach-node-signals node)
        (labels:drop-node node)
        (views:drop-node node))

    ;; Forward declaration or reordering needed since handle-node-added calls handle-edge-added
    (fn handle-edge-added [payload]
        (local edge (and payload payload.edge))
        (local edge-opts (and payload payload.opts))
        (when edge
            (local source-ready? (registry:lookup (node-id edge.source)))
            (local target-ready? (registry:lookup (node-id edge.target)))
            
            (if (and source-ready? target-ready?)
                (do
                    (local run-force? (if (= (and edge-opts edge-opts.run-force?) nil)
                                          true
                                          edge-opts.run-force?))
                    (local (record added?)
                          (registry:add-edge edge
                              (fn []
                                  (graph-layout:add-edge edge))))
                    (when added?
                        (if run-force?
                            (graph-layout:start)
                            (graph-layout:update-lines))))
                (do
                    ;; Queue pending edge
                    (table.insert pending-edges {:edge edge :opts edge-opts}))))
        edge)

    (fn handle-node-added [payload]
        (local node (and payload payload.node))
        (local node-opts (and payload payload.opts))
        (when node
            (local existing (registry:lookup node.key))
            (when (not existing)
                (local run-force? (if (= (and node-opts node-opts.run-force?) nil)
                                      true
                                      node-opts.run-force?))
                (local position (ensure-glm-vec3 (or (persistence:saved-position node)
                                                     (and node-opts node-opts.position))
                                                 (next-position)))
                (assert-valid-position position "GraphView.add-node position" node)
                (local idx (graph-layout:add-node node position (and node-opts node-opts.pinned)))
                (assert (not (= idx nil)) "GraphView.add-node failed to allocate layout index")
                (local point (LayeredPoint {:points points
                                            :position position
                                            :pointer-target (or options.pointer-target
                                                                (and ctx ctx.pointer-target))
                                            :depth-offset-step point-depth-offset-step
                                            :base-depth-offset-index point-base-depth-offset
                                            :base-layer-index base-layer-index
                                            :layers [{:size 0
                                                      :color resolved-focus-outline-color}
                                                     {:size 0
                                                      :color resolved-selection-border-color}
                                                     {:size node.size
                                                      :color node.color}]}))
                (assert point (string.format "GraphView.add-node failed to create point for %s"
                                             (node-id node)))
                (local focus-node (focus:create-node {:name (.. "graph-node-" (node-id node))
                                                      :parent points-focus-scope}))
                (when (and focus-node focus)
                    (focus:attach-bounds
                        focus-node
                        {:get-bounds (fn [_self]
                                        (when point.position
                                            (local size (or point.size 0))
                                            (local half (* size 0.5))
                                            {:position (glm.vec3 (- point.position.x half)
                                                                 (- point.position.y half)
                                                                 (- point.position.z half))
                                             :size (glm.vec3 size size size)}))}))
                (when focus-node
                    (set focus-node.activate
                         (fn [_node opts]
                             (local mod (and opts opts.event opts.event.mod))
                             (if (Modifiers.alt-held? mod)
                                 (do
                                     (local ts (or (and opts opts.event opts.event.payload
                                                        opts.event.payload.timestamp) 0))
                                     (local continuing?
                                         (and (> (length expand-seq-frontier) 0)
                                              (> ts 0)
                                              (<= (- ts expand-seq-timestamp) expand-seq-timeout)))
                                     (local frontier
                                         (if continuing?
                                             expand-seq-frontier
                                             [(tostring node.key)]))
                                     (set expand-seq-frontier (expand-linked-frontier graph frontier))
                                     (set expand-seq-timestamp ts)
                                     true)
                                 (do (views:open node) true)))))
                (set (. focus-nodes node) focus-node)
                (set (. node-by-focus focus-node) node)
                (when (and focus-manager focus-node)
                    (local current-focused (focus-manager:get-focused-node))
                    (when (= current-focused focus-node)
                        (set focused-node node)
                        (update-point-state node))
                    (when (and (not current-focused)
                               (or (and node-opts node-opts.auto-focus?)
                                   (and node node.auto-focus?)))
                        (focus-node:request-focus)
                        (when node
                            (set node.auto-focus? false))))
                (set point.on-click
                     (fn [_self _event]
                         (focus-node:request-focus)))
                (set point.on-double-click
                     (fn [_self event]
                         (if (Modifiers.alt-held? (and event event.mod))
                             (expand-linked-frontier graph [(tostring node.key)])
                             (do
                                 (when focus-manager
                                     (focus-manager:arm-auto-focus {:event event}))
                                 (views:open node)
                                 (when focus-manager
                                     (focus-manager:clear-auto-focus))))))
                (clickables:register point)
                (clickables:register-double-click point)
                (registry:add-node node point idx (and node-opts node-opts.pinned))
                (register-movable node point)
                (when selector
                    (selector:add-selectables [point]))
                (if run-force?
                    (graph-layout:start)
                    (graph-layout:update-lines))
                (update-point-state node)
                (update-labels [node] {:force? true})
                (attach-node-signals node)
                
                ;; Process pending edges
                (local remaining-edges [])
                (each [_ pending (ipairs pending-edges)]
                    (local edge pending.edge)
                    (local source-ready? (registry:lookup (node-id edge.source)))
                    (local target-ready? (registry:lookup (node-id edge.target)))
                    (if (and source-ready? target-ready?)
                        (handle-edge-added pending)
                        (table.insert remaining-edges pending)))
                
                ;; Clear and refill pending edges to remove processed ones
                (for [i (length pending-edges) 1 -1]
                    (table.remove pending-edges i))
                (each [_ pending (ipairs remaining-edges)]
                    (table.insert pending-edges pending)))))

    ;; Removed handle-edge-added from here as it was moved above

    (fn handle-node-replaced [payload]
        (local existing (and payload payload.old))
        (local node (and payload payload.new))
        (when (and existing node)
            (when movables-handler
                (movables-handler:unregister existing))
            (local replacement (registry:replace existing node))
            (when replacement
                (when replacement.point
                    (set replacement.point.on-double-click
                         (fn [_self _event]
                             (views:open node)))
                    (set replacement.point.on-click
                         (fn [_self _event]
                             (local focus-node (. focus-nodes node))
                             (when focus-node
                                 (focus-node:request-focus)))))
                (register-movable node replacement.point))
            (labels:move-label existing node)
            (views:move-view existing node)
            (detach-node-signals existing)
            (attach-node-signals node)
            (local focus-node (. focus-nodes existing))
            (when focus-node
                (set (. focus-nodes existing) nil)
                (set (. focus-nodes node) focus-node)
                (set (. node-by-focus focus-node) node)
                (when (= focused-node existing)
                    (set focused-node node)))
            (each [i selected (ipairs selected-nodes)]
                (when (= selected existing)
                    (set (. selected-nodes i) node)))
            (selection:set-selection selected-nodes)))

    (fn handle-nodes-removed [payload]
        (local removal-set (and payload payload.removal-set))
        (local nodes-to-remove (and payload payload.nodes))
        (when (and nodes-to-remove (> (length nodes-to-remove) 0))
            (local (removed-count removal-set)
                  (registry:remove-nodes nodes-to-remove
                      {:before-remove (fn [node point]
                                           (drop-node-artifacts node)
                                           (when (and clickables point)
                                               (clickables:unregister point)
                                               (clickables:unregister-double-click point)
                                               (set point.on-double-click nil))
                                           (when selector
                                               (selector:remove-selectables [point]))
                                           (when movables-handler
                                               (movables-handler:unregister node)))
                       :on-drop-point (fn [point]
                                           (when (and point point.drop)
                                               (point:drop)))}))
            (when (> removed-count 0)
                (when selector
                    (for [i (length selector.selectables) 1 -1]
                        (table.remove selector.selectables i))
                    (each [_ point (pairs registry.points)]
                        (table.insert selector.selectables point))
                    (selector:set-selected []))
                (each [node _ (pairs removal-set)]
                    (local focus-node (. focus-nodes node))
                    (when focus-node
                        (focus-node:drop)
                        (set (. focus-nodes node) nil)
                        (set (. node-by-focus focus-node) nil))
                    (set (. selected-set node) nil)
                    (when (= focused-node node)
                        (set focused-node nil)))
                (selection:prune removal-set)
                (graph-layout:rebuild))))

    (fn handle-edge-removed [payload]
        (local edge (and payload payload.edge))
        (when edge
            (registry:remove-edges (fn [candidate] (= candidate edge)))
            (graph-layout:update-lines)))

    (var node-added-handler nil)
    (var node-removed-handler nil)
    (var node-replaced-handler nil)
    (var edge-added-handler nil)
    (var edge-removed-handler nil)
    (var stabilized-handler nil)

    (fn attach-graph []
        (when (and graph.node-added (not node-added-handler))
            (set node-added-handler
                 (graph.node-added:connect handle-node-added)))
        (when (and graph.node-removed (not node-removed-handler))
            (set node-removed-handler
                 (graph.node-removed:connect handle-nodes-removed)))
        (when (and graph.node-replaced (not node-replaced-handler))
            (set node-replaced-handler
                 (graph.node-replaced:connect handle-node-replaced)))
        (when (and graph.edge-added (not edge-added-handler))
            (set edge-added-handler
                 (graph.edge-added:connect handle-edge-added)))
        (when (and graph.edge-removed (not edge-removed-handler))
            (set edge-removed-handler
                 (graph.edge-removed:connect handle-edge-removed))))

    (fn detach-graph []
        (when (and graph.node-added node-added-handler)
            (graph.node-added:disconnect node-added-handler true)
            (set node-added-handler nil))
        (when (and graph.node-removed node-removed-handler)
            (graph.node-removed:disconnect node-removed-handler true)
            (set node-removed-handler nil))
        (when (and graph.node-replaced node-replaced-handler)
            (graph.node-replaced:disconnect node-replaced-handler true)
            (set node-replaced-handler nil))
        (when (and graph.edge-added edge-added-handler)
            (graph.edge-added:disconnect edge-added-handler true)
            (set edge-added-handler nil))
        (when (and graph.edge-removed edge-removed-handler)
            (graph.edge-removed:disconnect edge-removed-handler true)
            (set edge-removed-handler nil)))

    (when layout.stabilized
        (set stabilized-handler
             (layout.stabilized:connect (fn [] (persistence:schedule-save)))))

    (set selection-handler
         (selected-nodes-changed:connect (fn [nodes]
                                             (update-selection-set nodes))))
    (set focus-focus-handler
         (focus-manager.focus-focus:connect handle-focus-change))
    (set focus-blur-handler
         (focus-manager.focus-blur:connect handle-focus-change))

    (selection:attach)
    (selection:on-selection-changed)
    (update-selection-set selected-nodes)

    (attach-graph)
    (each [_ node (pairs graph.nodes)]
        (handle-node-added {:node node}))
    (each [_ edge (ipairs graph.edges)]
        (handle-edge-added {:edge edge}))
    (connect-updates)

    (local view {:graph graph
                 :ctx ctx
                 :layout layout
                 :points registry.points
                 :node-by-point node-by-point
                 :movables movables
                 :movable-targets (and movables-handler movables-handler.targets)
                 :nodes nodes
                 :nodes-by-index nodes-by-index
                 :indices indices
                 :edges edges
                 :edge-map edge-map
                 :selected-nodes selected-nodes
                 :selected-nodes-changed selected-nodes-changed
                 :focus-nodes focus-nodes
                 :node-by-focus node-by-focus
                 :labels labels
                 :views views
                 :pinned pinned
                 :persistence persistence
                 :selection selection
                 :graph-layout graph-layout})

    (set view.remove-nodes (fn [_self nodes-to-remove]
                               (graph:remove-nodes nodes-to-remove)))
    (set view.remove-selected-nodes (fn [_self]
                                        (graph:remove-nodes selected-nodes)))
    (set view.open-focused-node (fn [_self]
                                   (when focused-node
                                       (views:open focused-node)
                                       true)))
    (set view.update update)
    (set view.get-position get-position)
    (set view.start-layout (fn [_self] (graph-layout:start)))
    (set view.drop
         (fn [_self]
             (detach-graph)
             (selection:drop)
             (when (and selected-nodes-changed selection-handler)
                 (selected-nodes-changed:disconnect selection-handler true)
                 (set selection-handler nil))
             (when (and focus-manager focus-focus-handler)
                 (focus-manager.focus-focus:disconnect focus-focus-handler true)
                 (set focus-focus-handler nil))
             (when (and focus-manager focus-blur-handler)
                 (focus-manager.focus-blur:disconnect focus-blur-handler true)
                 (set focus-blur-handler nil))
             (each [node point (pairs registry.points)]
                 (when (and point point.position)
                     (assert-valid-position point.position "GraphView.drop.persist" node point)))
            (persistence:persist registry.points true)
             (when (and layout.stabilized stabilized-handler)
                 (layout.stabilized:disconnect stabilized-handler true)
                 (set stabilized-handler nil))
             (each [_ record (ipairs edges)]
                 (registry:drop-edge record))
             (for [i (length edges) 1 -1]
                 (table.remove edges i))
             (labels:drop-all)
            (when movables-handler
                (movables-handler:drop-all))
            (each [_ point (pairs registry.points)]
                (when clickables
                    (clickables:unregister point)
                    (clickables:unregister-double-click point)
                    (set point.on-double-click nil))
                (when selector
                    (selector:remove-selectables [point]))
                (set (. node-by-point point) nil)
                (when point.drop
                    (point:drop)))
            (each [node focus-node (pairs focus-nodes)]
                (when focus-node
                    (focus-node:drop))
                (set (. focus-nodes node) nil))
            (when points-focus-scope
                (points-focus-scope:drop)
                (set points-focus-scope nil))
             (each [focus-node _ (pairs node-by-focus)]
                 (set (. node-by-focus focus-node) nil))
             (each [node _ (pairs selected-set)]
                 (set (. selected-set node) nil))
             (set focused-node nil)
             (set drag-active? false)
             (set drag-node nil)
             (set view.movable-targets (and movables-handler movables-handler.targets))
             (each [_ node (pairs nodes)]
                 (drop-node-artifacts node))
             (views:drop-all)
             (layout:clear)
             (each [node _ (pairs pinned)]
                 (set (. pinned node) nil))
             (when (and app.engine app.engine.events app.engine.events.updated update-handler)
                 (app.engine.events.updated:disconnect update-handler true)
                 (set update-handler nil))))
    view)

GraphView
