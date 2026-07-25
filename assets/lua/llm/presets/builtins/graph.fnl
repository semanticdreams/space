(local {: GraphEdge} (require :graph/edge))

(fn require-graph-map [app tool-name]
  (local runtime (and app app.active-world-runtime))
  (local g (or (and runtime
                    runtime.graph-map-manager
                    (runtime.graph-map-manager:get-active-map))
               (and runtime runtime.graph-map)
               app.graph-map))
  (assert g (.. tool-name " requires a graph-map"))
  g)

(fn lookup-node [graph id]
  (assert (= (type id) "string") "graph node id must be a string")
  (or (and graph.lookup (graph:lookup id))
      (and graph.load-by-key (graph:load-by-key id))))

(fn request-focus [app node]
  (local focus-node (and app.graph-view app.graph-view.focus-nodes
                         (. app.graph-view.focus-nodes node)))
  (when (and focus-node focus-node.request-focus)
    (focus-node:request-focus {:reason :mcp}))
  true)

(fn open-node-view [app node]
  (assert app.graph-view "open-node requires app.graph-view")
  (assert app.graph-view.views "open-node requires graph-view.views")
  (assert app.graph-view.views.open "open-node requires graph-view.views.open")
  (app.graph-view.views:open node)
  true)

(fn register-graph-presets [mgr]
  (mgr:register
    {:name "graph-node-tools"
     :group "graph"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :canvas :activity "graph"}]
     :tool-ids ["graph.add-node" "graph.load-node"]
     :system-prompt "Use graph node tools to create and load nodes in the knowledge graph."})

  (mgr:register
    {:name "graph-node-map-tools"
     :group "graph"
     :default-state :auto
     :risk :destructive
     :contexts [{:surface :canvas :activity "graph"}]
     :tool-ids ["graph.remove-nodes"]
           :system-prompt "Removing nodes from the graph map. This is non-destructive; backing objects are not deleted."})

  (mgr:register
    {:name "graph-edge-tools"
     :group "graph"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :canvas :activity "graph"}]
     :tool-ids ["graph.add-edge"]})

  (mgr:register
    {:name "graph-nav-tools"
     :group "graph"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :canvas :activity "graph"}]
     :tool-ids ["graph.focus-node" "graph.open-node" "graph.search-nodes"]
     :system-prompt "Use graph navigation tools to focus, open, and search nodes in the knowledge graph."})

  (mgr:register
    {:name "graph-identity-tools"
     :group "graph"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :canvas :activity "graph"}]
     :tool-ids ["graph.create-identity"]
     :system-prompt "Use identity tools to create identity nodes (entity-backed, exposed through the graph)."})

  (mgr:register
    {:name "graph-state-tools"
     :group "graph"
     :default-state :auto
     :risk :destructive
     :contexts [{:surface :canvas :activity "graph"}]
     :tool-ids ["graph.get-state" "graph.restore-state"]
     :system-prompt "Graph topology state operations can overwrite current node/edge keys and require approval."}))

(fn add-node-run [app]
  (fn [args]
    (local graph-map (require-graph-map app "space_graph_add_node"))
    (when (and args.kind (not= args.kind "string-entity"))
      (error (.. "space_graph_add_node unsupported kind: " (tostring args.kind))))
    (local StringEntityStore (require :entities/string))
    (local store (StringEntityStore.get-default))
    (local entity (store:create-entity {:value (or args.content args.label "")}))
    (local key (.. "string-entity:" (tostring entity.id)))
    (local node (graph-map:load-by-key key))
    (assert node (.. "space_graph_add_node failed to load created string entity: " key))
    key))

(fn load-node-run [app]
  (fn [args]
    (local graph-map (require-graph-map app "space_graph_load_node"))
    (local node (lookup-node graph-map args.id))
    (if node
        (do
          (when app.graph-view
            (request-focus app node))
          "loaded")
        (error (.. "Node not found: " args.id)))))

(fn remove-nodes-run [app]
  (fn [args]
    (local graph-map (require-graph-map app "space_graph_remove_nodes"))
    (local nodes [])
    (each [_ id (ipairs args.ids)]
      (local node (and graph-map.lookup (graph-map:lookup id)))
      (assert node (.. "Node not in active graph map: " id))
      (table.insert nodes node))
    (graph-map:remove-nodes nodes)
    (.. "removed " (# nodes) " nodes")))

(fn add-edge-run [app]
  (fn [args]
    (local graph-map (require-graph-map app "space_graph_add_edge"))
    (local source (lookup-node graph-map args.from))
    (local target (lookup-node graph-map args.to))
    (assert source (.. "Source node not found: " args.from))
    (assert target (.. "Target node not found: " args.to))
    (local edge (graph-map:add-edge (GraphEdge {:source source :target target :label args.label})))
    (or edge.label "created")))

(fn focus-node-run [app]
  (fn [args]
    (local graph-map (require-graph-map app "space_graph_focus_node"))
    (local node (lookup-node graph-map args.id))
    (assert node (.. "Node not found: " args.id))
    (request-focus app node)
    "focused"))

(fn open-node-run [app]
  (fn [args]
    (local graph-map (require-graph-map app "space_graph_open_node"))
    (local node (lookup-node graph-map args.id))
    (assert node (.. "Node not found: " args.id))
    (open-node-view app node)
    "opened"))

(fn search-nodes-run [app]
  (fn [args]
    (local graph-map (require-graph-map app "space_graph_search_nodes"))
    (local query (string.lower args.query))
    (local results [])
    (each [_ node (pairs graph-map.nodes)]
      (local label (string.lower (tostring (or node.label node.key ""))))
      (local kind (and node.metadata node.metadata.kind))
      (when (and (string.find label query 1 true)
                 (or (not args.kind) (= kind args.kind)))
        (table.insert results node)))
    (.. "found " (# results) " nodes")))

(fn create-identity-run [app]
  (fn [args]
    (local graph-map (require-graph-map app "space_graph_create_identity"))
    (local shared-graph graph-map.graph)
    (local node (shared-graph:create-identity args.name {:metadata {:role args.role}}))
    (when (and graph-map.load-by-key node)
      (graph-map:load-by-key node.key))
    (tostring node.key)))

(fn get-state-run [app]
  (fn [_args]
    (local graph-map (require-graph-map app "space_graph_get_state"))
    (graph-map:capture-state)))

(fn restore-state-run [app]
  (fn [args]
    (local graph-map (require-graph-map app "space_graph_restore_state"))
    (graph-map:restore-state args.state)
    "restored"))

(fn register-graph-adapters [adapters]
  (local empty-schema {:type "object" :properties {}})

  (adapters:register
    {:id "graph.add-node"
     :mcp-name "space_graph_add_node"
     :description "Create a string entity and add it to the active graph map."
     :inputSchema {:type "object"
                   :properties {:label {:type "string" :description "Node label"}
                                 :kind {:type "string" :description "Optional node kind; only string-entity is supported"}
                                 :content {:type "string" :description "Optional node content"}}
                   :required ["label"]}
     :make-run add-node-run})

  (adapters:register
    {:id "graph.load-node"
     :mcp-name "space_graph_load_node"
     :description "Load an existing node by ID into the active view."
     :inputSchema {:type "object" :properties {:id {:type "string" :description "Node ID to load"}} :required ["id"]}
     :make-run load-node-run})

  (adapters:register
    {:id "graph.remove-nodes"
     :mcp-name "space_graph_remove_nodes"
      :description "Remove nodes from the graph map. Backing objects are not deleted."
     :inputSchema {:type "object"
                   :properties {:ids {:type "array" :items {:type "string"} :description "Node IDs to remove"}}
                   :required ["ids"]}
     :make-run remove-nodes-run})

  (adapters:register
    {:id "graph.add-edge"
     :mcp-name "space_graph_add_edge"
     :description "Add an edge between two graph nodes."
     :inputSchema {:type "object"
                   :properties {:from {:type "string" :description "Source node ID"}
                                :to {:type "string" :description "Target node ID"}
                                :label {:type "string" :description "Edge label"}}
                   :required ["from" "to"]}
     :make-run add-edge-run})

  (adapters:register
    {:id "graph.focus-node"
     :mcp-name "space_graph_focus_node"
     :description "Focus the graph view on a specific node."
     :inputSchema {:type "object" :properties {:id {:type "string" :description "Node ID to focus"}} :required ["id"]}
     :make-run focus-node-run})

  (adapters:register
    {:id "graph.open-node"
     :mcp-name "space_graph_open_node"
     :description "Open a graph node for viewing or editing."
     :inputSchema {:type "object" :properties {:id {:type "string" :description "Node ID to open"}} :required ["id"]}
     :make-run open-node-run})

  (adapters:register
    {:id "graph.search-nodes"
     :mcp-name "space_graph_search_nodes"
     :description "Search for nodes in the graph by label or content."
     :inputSchema {:type "object"
                   :properties {:query {:type "string" :description "Search query"}
                                :kind {:type "string" :description "Optional kind filter"}}
                   :required ["query"]}
     :make-run search-nodes-run})

  (adapters:register
    {:id "graph.create-identity"
     :mcp-name "space_graph_create_identity"
     :description "Create an identity node (entity-backed, exposed through the graph)."
     :inputSchema {:type "object"
                   :properties {:name {:type "string" :description "Identity name"}
                                :role {:type "string" :description "Identity role"}}
                   :required ["name"]}
     :make-run create-identity-run})

  (adapters:register
    {:id "graph.get-state"
     :mcp-name "space_graph_get_state"
     :description "Get the graph topology state (node keys and edge connections) for backup purposes."
     :inputSchema empty-schema
     :make-run get-state-run})

  (adapters:register
    {:id "graph.restore-state"
     :mcp-name "space_graph_restore_state"
     :description "Restore graph topology state from a snapshot. This overwrites current node/edge topology."
     :inputSchema {:type "object"
                   :properties {:state {:type "object" :description "Graph state to restore"}}
                   :required ["state"]}
     :make-run restore-state-run})

  true)

(fn register [mgr]
  (local adapters (. mgr :tool-adapters))
  (when adapters
    (register-graph-adapters adapters))
  (register-graph-presets mgr)
  true)

{:register register}
