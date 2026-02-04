(local NodeBase (require :graph/node-base))

(local node-id NodeBase.node-id)

(fn GraphViewRegistry [opts]
    (local options (or opts {}))
    (local reg {:nodes (or options.nodes {})
                :nodes-by-index (or options.nodes-by-index [])
                :indices (or options.indices {})
                :points (or options.points {})
                :edge-map (or options.edge-map {})
                :edges (or options.edges [])
                :node-by-point (or options.node-by-point {})
                :pinned (or options.pinned {})
                :node-seq (or options.node-seq 0)})
    (local nodes reg.nodes)
    (local nodes-by-index reg.nodes-by-index)
    (local indices reg.indices)
    (local points reg.points)
    (local edge-map reg.edge-map)
    (local edges reg.edges)
    (local node-by-point reg.node-by-point)
    (local pinned reg.pinned)
    (local edge-key (or options.edge-key
                        (fn [edge]
                            (.. (node-id edge.source) "->" (node-id edge.target)))))
    (var drop-edge nil)
    (var remove-edges nil)

    (fn ensure-key [_self node]
        (when (not node.key)
            (set reg.node-seq (+ reg.node-seq 1))
            (set node.key (.. "node-" reg.node-seq))))

    (fn canonical-node [_self node context]
        (assert node (string.format "Graph missing node for %s" context))
        (ensure-key reg node)
        node)

    (fn lookup [_self key]
        (and key (. nodes key)))

    (fn index-of [_self node]
        (. indices node))

    (fn point-of [_self node]
        (. points node))

    (fn add-node [_self node point idx pinned?]
        (assert node "GraphViewRegistry.add-node requires node")
        (assert point (string.format "GraphViewRegistry.add-node missing point for %s"
                                     (node-id node)))
        (assert (not (= idx nil))
                (string.format "GraphViewRegistry.add-node requires index for %s"
                               (node-id node)))
        (set (. nodes node.key) node)
        (set (. nodes-by-index (+ idx 1)) node)
        (set (. indices node) idx)
        (set (. points node) point)
        (set (. node-by-point point) node)
        (when pinned?
            (set (. pinned node) true))
        node)

    (fn replace [_self existing node]
        (assert existing "GraphViewRegistry.replace requires an existing node")
        (assert node "GraphViewRegistry.replace requires a replacement node")
        (assert (= existing.key node.key)
                (string.format "GraphViewRegistry.replace key mismatch: %s vs %s"
                               (or existing.key "<none>")
                               (or node.key "<none>")))
        (local idx (. indices existing))
        (assert idx (string.format "GraphViewRegistry.replace missing index for %s"
                                   (node-id existing)))
        (local point (. points existing))
        (assert point (string.format "GraphViewRegistry.replace missing point for %s"
                                     (node-id existing)))
        (set (. nodes node.key) node)
        (set (. nodes-by-index (+ idx 1)) node)
        (set (. indices node) idx)
        (set (. indices existing) nil)
        (set (. points node) point)
        (set (. points existing) nil)
        (set (. node-by-point point) node)
        (when (. pinned existing)
            (set (. pinned node) true)
            (set (. pinned existing) nil))
        (each [_ record (ipairs edges)]
            (when record.edge
                (when (= record.edge.source existing)
                    (set record.edge.source node))
                (when (= record.edge.target existing)
                    (set record.edge.target node))))
        {:point point :idx idx})

    (set drop-edge
         (fn [_self record]
             (when record
                 (local key (and record.edge (edge-key record.edge)))
                 (when key
                     (set (. edge-map key) nil))
                 (when record.label-span
                     (record.label-span:drop)
                     (set record.label-span nil))
                 (when record.line
                     (record.line:drop)))))

    (set remove-edges
         (fn [_self predicate]
             (local keep [])
             (each [_ record (ipairs edges)]
                 (if (predicate record.edge)
                     (drop-edge reg record)
                     (table.insert keep record)))
             (for [i (length edges) 1 -1]
                 (table.remove edges i))
             (each [_ record (ipairs keep)]
                 (table.insert edges record))))

    (fn add-edge [_self edge create-record]
        (assert edge "GraphViewRegistry.add-edge requires an edge")
        (local key (edge-key edge))
        (local existing (. edge-map key))
        (if existing
            (do
                (set existing.edge edge)
                (values existing false))
            (do
                (local record (create-record))
                (assert record (string.format "GraphViewRegistry.add-edge failed to create record for %s"
                                              key))
                (var in-edges? false)
                (each [_ entry (ipairs edges)]
                    (when (= entry record)
                        (set in-edges? true)))
                (when (not in-edges?)
                    (table.insert edges record))
                (set (. edge-map key) record)
                (values record true)))
        )

    (fn remove-nodes [_self nodes-to-remove opts]
        (local options (or opts {}))
        (local before-remove (or options.before-remove (fn [_node _point] nil)))
        (local on-drop-point (or options.on-drop-point (fn [_point] nil)))
        (local removal-set {})
        (local missing [])
        (each [_ node (ipairs (or nodes-to-remove []))]
            (if (and node (rawget _self.indices node))
                (tset removal-set node true)
                (when node
                    (table.insert missing (node-id node)))))
        (when (> (length missing) 0)
            (error (string.format "GraphViewRegistry.remove-nodes received unregistered nodes: %s"
                                  (table.concat missing ", "))))
        (if (= (next removal-set) nil)
            (values 0 removal-set)
            (do
                (_self.remove-edges _self
                    (fn [edge]
                        (and edge
                             (or (rawget removal-set edge.source)
                                 (rawget removal-set edge.target)))))
                (var removed-count 0)
                (each [node _ (pairs removal-set)]
                    (local point (rawget _self.points node))
                    (before-remove node point)
                    (set removed-count (+ removed-count 1))
                    (when point
                        (set (. _self.node-by-point point) nil)
                        (on-drop-point point)
                        (set (. _self.points node) nil))
                    (set (. _self.pinned node) nil)
                    (local idx (rawget _self.indices node))
                    (assert idx (string.format "GraphViewRegistry.remove-nodes missing index for node %s"
                                               (node-id node)))
                    (set (. _self.nodes-by-index (+ idx 1)) nil)
                    (set (. _self.indices node) nil)
                    (when node.key
                        (set (. _self.nodes node.key) nil)))
                (each [node point (pairs _self.points)]
                    (when (or (not node)
                              (not node.key)
                              (not (= (. _self.nodes node.key) node)))
                        (set (. _self.points node) nil)))
                (values removed-count removal-set)))
        )

    (tset reg :ensure-key ensure-key)
    (tset reg :canonical-node canonical-node)
    (tset reg :lookup lookup)
    (tset reg :index-of index-of)
    (tset reg :point-of point-of)
    (tset reg :add-node add-node)
    (tset reg :replace replace)
    (tset reg :add-edge add-edge)
    (tset reg :drop-edge drop-edge)
    (tset reg :remove-edges remove-edges)
    (tset reg :remove-nodes remove-nodes)
    (tset reg :edge-key edge-key)

    reg)

GraphViewRegistry
