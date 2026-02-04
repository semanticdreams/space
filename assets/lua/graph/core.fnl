(local Graph {})

(local glm (require :glm))
(local Edge (require :graph/edge))
(local NodeBase (require :graph/node-base))
(local StartNode (require :graph/nodes/start))
(local ClassNode (require :graph/nodes/class))
(local QuitNode (require :graph/nodes/quit))
(local Signal (require :signal))
(local LinkEntityStore (require :entities/link))

(local GraphNode NodeBase.GraphNode)
(local GraphEdge Edge.GraphEdge)
(local node-id NodeBase.node-id)

(fn create-graph [opts]
    (local options (or opts {}))
    (local nodes {})
    (local edges [])
    (local edge-map {})
    (local key-loaders {})
    (var node-seq 0)
    (local node-added (Signal))
    (local node-removed (Signal))
    (local node-replaced (Signal))
    (local edge-added (Signal))
    (local edge-removed (Signal))

    (var check-link-edges-for-node nil) ;; Forward declaration

    (local self {:nodes nodes
                 :edges edges
                 :edge-map edge-map
                 :with-start (if (= options.with-start nil) true options.with-start)
                 :node-added node-added
                 :node-removed node-removed
                 :node-replaced node-replaced
                 :edge-added edge-added
                 :edge-removed edge-removed})

    (fn ensure-key [node]
        (when (not node.key)
            (set node-seq (+ node-seq 1))
            (set node.key (.. "node-" node-seq))))

    (fn canonical-node [_self node context]
        (assert node (string.format "Graph missing node for %s" context))
        (ensure-key node)
        node)

    (fn edge-key [edge]
        (.. (node-id edge.source) "->" (node-id edge.target)))

    (fn lookup [_self key]
        (and key (. nodes key)))

    (fn replace-node [_self existing node]
        (when existing.unmount
            (existing:unmount))
        (when node.mount
            (node:mount self))
        (set (. nodes node.key) node)
        (each [_ edge (ipairs edges)]
            (when (= edge.source existing)
                (set edge.source node))
            (when (= edge.target existing)
                (set edge.target node)))
        (node-replaced:emit {:old existing :new node})
        node)

    (fn add-node [_self node node-opts]
        (when (not node)
            (error "Graph.add-node requires a node"))
        (local canonical (canonical-node self node "add-node"))
        (local existing (. nodes canonical.key))
	        (if existing
	            (if (= existing canonical)
	                existing
	                (replace-node self existing canonical))
	            (do
	                (when canonical.mount
	                    (canonical:mount self))
	                (set (. nodes canonical.key) canonical)
	                (node-added:emit {:node canonical :opts node-opts})
	                (when check-link-edges-for-node
	                    (check-link-edges-for-node canonical))
	                (when canonical.added
	                    (canonical:added self))
	                canonical)))

    (fn add-edge [_self edge edge-opts]
        (when (not edge)
            (error "Graph.add-edge requires an edge"))
        (assert edge.source "Graph.add-edge requires edge.source")
        (assert edge.target "Graph.add-edge requires edge.target")
        (set edge.source (canonical-node self edge.source "add-edge source"))
        (set edge.target (canonical-node self edge.target "add-edge target"))
        (local source (self:add-node edge.source))
        (local target (self:add-node edge.target))
        (set edge.source source)
        (set edge.target target)
        (local key (edge-key edge))
        (local existing (. edge-map key))
        (if existing
            (do
                (set (. edge-map key) edge)
                (for [i 1 (length edges)]
                    (when (= (. edges i) existing)
                        (set (. edges i) edge)))
                edge)
            (do
                (table.insert edges edge)
                (set (. edge-map key) edge)
                (edge-added:emit {:edge edge :opts edge-opts})
                edge)))

    (fn remove-nodes [_self nodes-to-remove]
        (local removal-set {})
        (local removed [])
        (each [_ node (ipairs (or nodes-to-remove []))]
            (when (and node node.key (= (. nodes node.key) node))
                (set (. removal-set node) true)
                (table.insert removed node)))
        (if (= (next removal-set) nil)
            0
            (do
                (local kept [])
                (local removed-edges [])
                (each [_ edge (ipairs edges)]
                    (if (or (rawget removal-set edge.source)
                            (rawget removal-set edge.target))
                        (table.insert removed-edges edge)
                        (table.insert kept edge)))
                (for [i (length edges) 1 -1]
                    (table.remove edges i))
                (each [_ edge (ipairs kept)]
                    (table.insert edges edge))
                (each [_ edge (ipairs removed-edges)]
                    (set (. edge-map (edge-key edge)) nil)
                    (edge-removed:emit {:edge edge}))
                (node-removed:emit {:nodes removed :removal-set removal-set})
                (each [_ node (ipairs removed)]
                    (set (. nodes node.key) nil)
                    (when node.unmount
                        (node:unmount))
                    (when node.drop
                        (node:drop)))
                (length removed))))

    (set self.add-node add-node)
    (set self.add-edge add-edge)
    (set self.remove-nodes remove-nodes)

    (set self.trigger
        (fn [self node]
            (local edges (node:get-edges))
            (each [_ e (ipairs edges)]
                (self:add-edge e))
            edges))

    (set self.edge-count (fn [_self] (length edges)))
    (set self.node-count (fn [_self] (length (icollect [_ _ (pairs nodes)] true))))
    (set self.lookup (fn [_self key] (lookup self key)))

    (fn key-scheme [key]
        (when (and key (= (type key) "string"))
            (local (start _end) (string.find key ":" 1 true))
            (if start
                (string.sub key 1 (- start 1))
                key)))

    (set self.register-key-loader
        (fn [_self scheme loader-fn]
            (assert scheme "register-key-loader requires a scheme")
            (assert (= (type scheme) "string") "register-key-loader requires string scheme")
            (assert (> (string.len scheme) 0) "register-key-loader requires non-empty scheme")
            (assert (not (string.find scheme ":" 1 true))
                    "register-key-loader scheme must not include ':'")
            (assert loader-fn "register-key-loader requires a loader function")
            (assert (= (type loader-fn) "function") "register-key-loader requires function loader")
            (assert (not (. key-loaders scheme))
                    (.. "register-key-loader duplicate scheme: " scheme))
            (set (. key-loaders scheme) loader-fn)))

    (set self.load-by-key
        (fn [_self key]
            (when (not key) (lua "return nil"))
            (assert (= (type key) "string") "load-by-key requires string key")
            (local existing (. nodes key))
            (when existing (lua "return existing"))
            (local scheme (key-scheme key))
            (local loader (. key-loaders scheme))
            (when (not loader) (lua "return nil"))
            (local node (loader key))
            (when node
                (assert (. node :key) "load-by-key loader must return node with key")
                (assert (= (. node :key) key)
                        (.. "load-by-key loader returned mismatched key: expected " key
                            " got " (tostring (. node :key))))
                (add-node self node))
            node))

    (set Graph.GraphNode GraphNode)
    (set Graph.GraphEdge GraphEdge)

    ;; Link entity integration
    (local link-store (or options.link-store (LinkEntityStore.get-default)))
    (local link-edge-map {}) ;; entity-id -> edge-key
    (local link-edge-loading {}) ;; entity-id -> true

    (fn add-link-edge-for-entity [entity entity-id]
        (var source-node (. nodes entity.source-key))
        (var target-node (. nodes entity.target-key))
        (when (not source-node)
            (set source-node (self:load-by-key entity.source-key)))
        (when (not target-node)
            (set target-node (self:load-by-key entity.target-key)))
        (when (and source-node target-node)
            (local label (or (and entity.metadata entity.metadata.name) ""))
            (local edge (GraphEdge {:source source-node
                                    :target target-node
                                    :color (glm.vec4 0.45 0.42 0.3 1)
                                    :label label}))
            (self:add-edge edge {:from-link-entity entity.id})
            (set (. link-edge-map entity-id) (edge-key edge))))

    (fn maybe-add-link-edge [entity]
        (if (not (and entity entity.source-key entity.target-key
                      (> (string.len entity.source-key) 0)
                      (> (string.len entity.target-key) 0)))
            nil
            (do
                (local entity-id (tostring entity.id))
                (when (. link-edge-map entity-id)
                    (lua "return nil"))
                (when (. link-edge-loading entity-id)
                    (lua "return nil"))
                (set (. link-edge-loading entity-id) true)
                (local (ok err)
                    (pcall (fn [] (add-link-edge-for-entity entity entity-id))))
                (set (. link-edge-loading entity-id) nil)
                (assert ok err))))

    (fn maybe-remove-link-edge [entity]
        (local entity-id (tostring (and entity entity.id)))
        (local stored-key (. link-edge-map entity-id))
        (when stored-key
            (local edge (. edge-map stored-key))
            (when edge
                ;; Remove edge from edges list and edge-map
                (for [i (length edges) 1 -1]
                    (when (= (. edges i) edge)
                        (table.remove edges i)))
                (set (. edge-map stored-key) nil)
                (edge-removed:emit {:edge edge}))
            (set (. link-edge-map entity-id) nil)))

    (set check-link-edges-for-node
        (fn [node]
            (when (and node node.key)
                (local all-keys (icollect [k _ (pairs nodes)] k))
                (local link-entities (link-store:find-edges-for-nodes all-keys))
                (each [_ entity (ipairs link-entities)]
                    (when (not (. link-edge-map (tostring entity.id)))
                        (maybe-add-link-edge entity))))))

    (var link-created-handler nil)
    (var link-updated-handler nil)
    (var link-deleted-handler nil)

    (set link-created-handler
        (link-store.link-entity-created:connect
            (fn [entity]
                (maybe-add-link-edge entity))))

    (set link-updated-handler
        (link-store.link-entity-updated:connect
            (fn [entity]
                (maybe-remove-link-edge entity)
                (maybe-add-link-edge entity))))

    (set link-deleted-handler
        (link-store.link-entity-deleted:connect
            (fn [entity]
                (maybe-remove-link-edge entity))))

    ;; Removed node-added listener as it is now called directly in add-node

    (fn disconnect-link-entity-handlers []
        (when link-created-handler
            (link-store.link-entity-created:disconnect link-created-handler true)
            (set link-created-handler nil))
        (when link-updated-handler
            (link-store.link-entity-updated:disconnect link-updated-handler true)
            (set link-updated-handler nil))
        (when link-deleted-handler
            (link-store.link-entity-deleted:disconnect link-deleted-handler true)
            (set link-deleted-handler nil)))

    (set self.drop
        (fn [_self]
            (each [_ node (pairs nodes)]
                (when node.unmount
                    (node:unmount))
                (when node.drop
                    (node:drop)))
            (for [i (length edges) 1 -1]
                (table.remove edges i))
            (each [k _ (pairs edge-map)]
                (set (. edge-map k) nil))
            (each [k _ (pairs nodes)]
                (set (. nodes k) nil))
            (node-added:clear)
            (node-removed:clear)
            (node-replaced:clear)
            (edge-added:clear)
            (edge-removed:clear)
            (disconnect-link-entity-handlers)))

    (when self.with-start
        (local start (StartNode))
        (set start.auto-focus? true)
        (self:add-node start {:auto-focus? true})
        (set self.start start))

    self)

(set Graph.GraphNode GraphNode)
(set Graph.GraphEdge GraphEdge)
(set Graph.StartNode StartNode)
(set Graph.ClassNode ClassNode)
(set Graph.QuitNode QuitNode)
(set Graph.create create-graph)
(setmetatable Graph {:__call (fn [_ opts] (create-graph opts))})

Graph
