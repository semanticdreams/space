(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphMapManager (require :graph/map-manager))
(local GraphMapSidebar (require :graph/map-sidebar))
(local BuildContext (require :build-context))

(local tests [])

(fn manager-active-map-id-updates-after-switch []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (assert (= manager.active-map-id "main") "Initial active-map-id should be main")
    (manager:create-map! "alpha" "Alpha")
    (manager:switch-map! "alpha")
    (assert (= manager.active-map-id "alpha") "active-map-id should update after switch")
    (assert (= manager.active-map-name "Alpha") "active-map-name should update after switch")
    (manager:switch-map! "main")
    (assert (= manager.active-map-id "main") "active-map-id should update after switch back")
    (manager:drop)
    (graph:drop))

(fn manager-rename-updates-active-map-name []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:rename-map! "main" "Renamed Map")
    (assert (= manager.active-map-name "Renamed Map") "active-map-name should update after rename")
    (manager:drop)
    (graph:drop))

(fn manager-active-map-status-returns-correct-values []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local status (manager:active-map-status))
    (assert status "active-map-status should return a table")
    (assert (= status.id "main") "active-map-status id should match")
    (assert (= (type status.name) :string) "active-map-status name should be a string")
    (assert (= (type status.node-count) :number) "active-map-status node-count should be a number")
    (assert (= (type status.edge-count) :number) "active-map-status edge-count should be a number")
    (manager:drop)
    (graph:drop))

(fn manager-next-map-id-increments-on-create []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local first-id manager.next-map-id)
    (manager:create-map! "second" "Second")
    (assert (> manager.next-map-id first-id) "next-map-id should increment after create")
    (manager:drop)
    (graph:drop))

(fn manager-delete-updates-active-info []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:create-map! "extra" "Extra")
    (manager:switch-map! "extra")
    (assert (= manager.active-map-name "Extra") "active-map-name should be Extra after switch")
    (manager:switch-map! "main")
    (manager:delete-map! "extra")
    (assert (= manager.active-map-id "main") "active-map-id should still be main after delete")
    (assert (= manager.active-map-name "Main") "active-map-name should still be Main")
    (manager:drop)
    (graph:drop))

(fn manager-switch-emits-correct-payload []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:create-map! "beta" "Beta")
    (var received-payload nil)
    (local handler (manager.maps-changed:connect (fn [p] (set received-payload p))))
    (manager:switch-map! "beta")
    (assert received-payload "Signal should fire on switch")
    (assert (= received-payload.previous-id "main") "previous-id should be main")
    (assert (= received-payload.active-id "beta") "active-id should be beta")
    (manager.maps-changed:disconnect handler true)
    (manager:drop)
    (graph:drop))

(fn manager-capture-state-preserves-map-names []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:create-map! "named" "Custom Name")
    (local state (manager:capture-state))
    (var found nil)
    (each [_ m (ipairs state.maps)]
        (when (= m.id "named")
            (set found m)))
    (assert found "Captured state should include created map")
    (assert (= found.name "Custom Name") "Captured state should preserve map name")
    (manager:drop)
    (graph:drop))

(fn manager-allows-delete-main-when-not-active []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:create-map! "second" "Second")
    (manager:switch-map! "second")
    (assert (= manager.active-map-id "second") "Active should be second")
    (manager:delete-map! "main")
    (assert (= manager.active-map-id "second") "Active should still be second after main deleted")
    (local maps (manager:list-maps))
    (assert (= (length maps) 1) "Only one map should remain")
    (assert (= (. maps 1 :id) "second") "Remaining map should be second")
    (manager:drop)
    (graph:drop))

(fn manager-rejects-unsafe-map-ids []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local bad-ids ["../escape" "sub/dir" "with.dot" ".." "."])
    (each [_ id (ipairs bad-ids)]
        (local (ok _err) (pcall (fn [] (manager:create-map! id id))))
        (assert (not ok) (.. "create-map! should reject unsafe id: " id)))
    (manager:drop)
    (graph:drop))

(fn make-hoverables-stub []
    (local stub {})
    (set stub.register (fn [_self _obj]))
    (set stub.unregister (fn [_self _obj]))
    stub)

(fn contains-label? [labels target]
    (var found? false)
    (each [_ label (ipairs (if labels labels []))]
        (when (= label target)
            (set found? true)))
    found?)

(fn approx [a b]
    (< (math.abs (- a b)) 0.001))

(fn layout-sidebar! [entity width height]
    (set entity.layout.size (glm.vec3 width height 0))
    (entity.layout:measurer)
    (entity.layout:layouter))

(fn finder-layout [entity]
    (local stack-layout (. entity.layout.children 1))
    (local flex-layout (. stack-layout.children 2))
    (. flex-layout.children (length flex-layout.children)))

(fn content-flex-layout [entity]
    (local stack-layout (. entity.layout.children 1))
    (. stack-layout.children 2))

(fn actions-layout [entity]
    (local flex-layout (content-flex-layout entity))
    (. flex-layout.children 2))

(local long-sidebar-node-label
       "A graph node label that is deliberately long enough to exceed the sidebar width by many characters")

(local long-finder-node-label
       "A finder node label that remains searchable in full but displays with an ellipsis")

(fn long-sidebar-node-loader [key]
    (Graph.GraphNode {:key key :label long-sidebar-node-label}))

(fn long-finder-node-loader [key]
    (Graph.GraphNode {:key key :label long-finder-node-label}))

(fn reveal-label-recorder [store]
    (fn [clicked-node _event]
        (set store.label clicked-node.label)))

(fn reveal-key-recorder [store]
    (fn [clicked-node _event]
        (set store.key clicked-node.key)))

(fn open-key-recorder [store]
    (fn [clicked-node _event]
        (set store.key clicked-node.key)))

(fn selected-count-reader [store]
    (fn [] store.count))

(fn generic-graph-node-loader [key]
    (Graph.GraphNode {:key key}))

(fn node-label-loader [key]
    (Graph.GraphNode {:key key :label (.. "Node " key)}))

(fn clickable-node-loader [key]
    (Graph.GraphNode {:key key :label "Clickable Node"}))

(fn register-start-loader [graph]
    (when (not (graph:has-key-loader-for-key "start"))
        (graph:register-key-loader "start"
            (fn [_key]
                (Graph.GraphNode {:key "start" :label "start"})))))

(fn sidebar-constructs-and-drops []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:create-map! "alpha" "Alpha")
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                              :hoverables (make-hoverables-stub)}))
    (local builder (GraphMapSidebar.GraphMapSidebar {:manager manager}))
    (local entity (builder ctx))
    (assert entity "Sidebar should return an entity")
    (assert entity.layout "Sidebar should have a layout")
    (assert entity.update "Sidebar should have update")
    (assert entity.drop "Sidebar should have drop")
    (entity:drop)
    (manager:drop)
    (graph:drop))

(fn sidebar-rebuilds-on-maps-changed []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                              :hoverables (make-hoverables-stub)}))
    (local builder (GraphMapSidebar.GraphMapSidebar {:manager manager}))
    (local entity (builder ctx))
    (assert entity.layout "Sidebar should have layout before rebuild")
    (manager:create-map! "gamma" "Gamma")
    (entity:update)
    (assert entity.layout "Sidebar should still have layout after maps-changed rebuild")
    (entity:drop)
    (manager:drop)
    (graph:drop))

(fn sidebar-exposes-map-labels-and-selected-count []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local selected-count {:count 2})
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                              :hoverables (make-hoverables-stub)}))
    (local builder (GraphMapSidebar.GraphMapSidebar
                      {:manager manager
                       :selected-count-provider (selected-count-reader selected-count)}))
    (local entity (builder ctx))
    (local labels (entity:visible-labels))
    (assert (contains-label? labels "Graph Maps") "Sidebar should label the graph maps dock")
    (assert (contains-label? labels "Switch Map") "Sidebar should include Switch Map label")
    (assert (contains-label? labels "Delete Map") "Sidebar should use Delete Map label")
    (assert (contains-label? labels "Selected: 2") "Sidebar should show selected count")
    (set selected-count.count 5)
    (entity:update)
    (assert (contains-label? (entity:visible-labels) "Selected: 5")
            "Sidebar should refresh selected count on update")
    (entity:drop)
    (manager:drop)
    (graph:drop))

(fn sidebar-refreshes-active-map_counts_after_map_mutations []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test" generic-graph-node-loader)
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                               :hoverables (make-hoverables-stub)}))
    (local builder (GraphMapSidebar.GraphMapSidebar {:manager manager}))
    (local entity (builder ctx))
    (local active (manager:get-active-map))
    (active:load-by-key "test:a")
    (entity:update)
    (assert (contains-label? (entity:visible-labels) "Main *  1n/0e")
            "Sidebar should refresh active map node count after node-added")
    (local a (active:lookup "test:a"))
    (local b (Graph.GraphNode {:key "test:b"}))
    (active:add-edge (Graph.GraphEdge {:source a :target b}))
    (entity:update)
    (assert (contains-label? (entity:visible-labels) "Main *  2n/1e")
            "Sidebar should refresh active map edge count after edge-added")
    (active:remove-nodes [a])
    (entity:update)
    (assert (contains-label? (entity:visible-labels) "Main *  1n/0e")
            "Sidebar should refresh active map counts after node removal")
    (entity:drop)
    (manager:drop)
    (graph:drop))

(local text-utils (require :text-utils))

(fn button-label [btn]
    ;; Convert codepoints back to a string for comparison
    (when (and btn.text btn.text.get-codepoints)
        (local cps (btn.text:get-codepoints))
        (var s "")
        (each [_ cp (ipairs cps)]
            (set s (.. s (string.char cp))))
        s))

(fn find-clickable-by-label [target-text]
    (local clickables (assert app.clickables "graph map sidebar test requires app.clickables")) (var found nil)
    (each [_ obj (ipairs clickables.left-click-objects)]
        (when (and (not found) obj.on-click)
            (local label (button-label obj))
            (when (= label target-text)
                (set found obj))))
    found)

(fn sidebar-add-start-is-visible-and-idempotent []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (register-start-loader graph)
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                              :hoverables (make-hoverables-stub)}))
    (local entity ((GraphMapSidebar.GraphMapSidebar {:manager manager}) ctx))
    (entity:update)
    (assert (contains-label? (entity:visible-labels) "Add Start")
            "Sidebar should expose Add Start")
    (local button (find-clickable-by-label "Add Start"))
    (assert button "Add Start should be a clickable button")
    (local active (manager:get-active-map))
    (assert (= (active:lookup "start") nil) "start should begin absent")
    (button:on-click {})
    (entity:update)
    (assert (active:lookup "start") "Add Start should load start")
    (local count-after-first (active:node-count))
    (button:on-click {})
    (entity:update)
    (assert (= (active:node-count) count-after-first)
            "Add Start should not duplicate existing start")
    (entity:drop)
    (manager:drop)
    (graph:drop))

(fn sidebar-new-button-creates-map-without-crashing []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                               :hoverables (make-hoverables-stub)}))
    (local builder (GraphMapSidebar.GraphMapSidebar {:manager manager}))
    (local entity (builder ctx))
    (entity:update)
    (local new-button (find-clickable-by-label "New"))
    (assert new-button "Sidebar should render a New button")
    (local initial-map-count (length (manager:list-maps)))
    (local (ok err) (pcall (fn [] (new-button:on-click {}))))
    (assert ok (.. "New button click should not crash: " (tostring err)))
    (entity:drop)
    (manager:drop)
    (graph:drop))

(fn sidebar-map-rows-do-not-stretch-to-full-panel-height []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                               :hoverables (make-hoverables-stub)}))
    (local builder (GraphMapSidebar.GraphMapSidebar {:manager manager}))
    (local entity (builder ctx))
    (entity:update)
    (local panel-height 10.0)
    (set entity.layout.size (glm.vec3 3 panel-height 0))
    (entity.layout:measurer)
    (entity.layout:layouter)
    ;; After layout, root-layout.children[1] is the Stack layout.
    ;; Stack layout.children[1] = background, [2] = content Flex.
    (local root-children entity.layout.children)
    (assert (= (length root-children) 1) "Root layout should have 1 child: the Stack")
    (local stack-layout (. root-children 1))
    (local stack-children stack-layout.children)
    (assert (= (length stack-children) 2) "Stack should have 2 children: background + content Flex")
    (local flex-layout (. stack-children 2))
    (local flex-children flex-layout.children)
    ;; flex-children[1]=title, [2]=actions, [3]=switch-title, [4]=map row, [5]=separator, [6]=selected-count
    (assert (>= (length flex-children) 4) "Flex should have at least 4 content rows with 1 map")
    (local map-row-layout (. flex-children 4))
    (assert (< map-row-layout.size.y panel-height)
            "Map row should not stretch to full panel height")
    (entity:drop)
    (manager:drop)
    (graph:drop))

(fn sidebar-node-finder-lists-active-map-nodes []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test" node-label-loader)
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local active (manager:get-active-map))
    (active:load-by-key "test:a")
    (active:load-by-key "test:b")
    (manager:create-map! "empty" "Empty")
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                              :hoverables (make-hoverables-stub)}))
    (local entity ((GraphMapSidebar.GraphMapSidebar {:manager manager}) ctx))
    (entity:update)
    (assert (contains-label? (entity:visible-labels) "Find Node")
            "Sidebar should expose Find Node")
    (assert (contains-label? (entity:visible-labels) "Node test:a")
            "Finder should include first active-map node")
    (assert (contains-label? (entity:visible-labels) "Node test:b")
            "Finder should include second active-map node")
    (manager:switch-map! "empty")
    (entity:update)
    (assert (not (contains-label? (entity:visible-labels) "Node test:a"))
            "Finder should drop nodes from previous active map")
    (entity:drop)
    (manager:drop)
    (graph:drop))

(fn sidebar-node-finder-clicks-route_callbacks []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test" clickable-node-loader)
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local active (manager:get-active-map))
    (local node (active:load-by-key "test:click"))
    (local revealed {:key nil})
    (local opened {:key nil})
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                              :hoverables (make-hoverables-stub)}))
    (local entity
        ((GraphMapSidebar.GraphMapSidebar
            {:manager manager
             :node-reveal-handler (reveal-key-recorder revealed)
             :node-open-handler (open-key-recorder opened)})
         ctx))
    (entity:update)
    (local button (find-clickable-by-label "Clickable Node"))
    (assert button "Finder row should render a clickable button")
    (button:on-click {:button 1})
    (assert (= revealed.key node.key) "Single click should route reveal callback")
    (button:on-double-click {:button 1})
    (assert (= opened.key node.key) "Double click should route open callback")
    (entity:drop)
    (manager:drop)
    (graph:drop))

(fn sidebar-new-button-uses-integer-map-id-after-restored-float []
    (local graph (Graph {:with-start false}))
    (local manager
        (GraphMapManager.GraphMapManager
            {:graph graph
             :state {:active_map_id "main"
                     :next_map_id 2.0
                     :maps [{:id "main" :name "Main" :nodes [] :edges []}]}}))
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                              :hoverables (make-hoverables-stub)}))
    (local entity ((GraphMapSidebar.GraphMapSidebar {:manager manager}) ctx))
    (entity:update)
    (local new-button (find-clickable-by-label "New"))
    (assert new-button "Sidebar should render a New button")
    (local (ok err) (pcall (fn [] (new-button:on-click {}))))
    (assert ok (.. "New button should not crash with restored next_map_id=2.0: " (tostring err)))
    (assert (= manager.active-map-id "map-2")
            "New button should switch to map-2, not map-2.0")
    (entity:drop)
    (manager:drop)
    (graph:drop))

(fn sidebar-width-includes-static-action-controls []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                              :hoverables (make-hoverables-stub)}))
    (local entity ((GraphMapSidebar.GraphMapSidebar {:manager manager}) ctx))
    (entity:update)
    (entity.layout:measurer)
    (local action-row (actions-layout entity))
    (assert (>= entity.layout.measure.x action-row.measure.x)
            (.. "Sidebar measure width " (tostring entity.layout.measure.x)
                " should include static action-row intrinsic width "
                (tostring action-row.measure.x)))
    (layout-sidebar! entity entity.layout.measure.x 24.0)
    (assert (>= entity.layout.size.x action-row.size.x)
            (.. "Sidebar layout width " (tostring entity.layout.size.x)
                " should include static action-row layout width "
                (tostring action-row.size.x)))
    (entity:drop)
    (manager:drop)
    (graph:drop))

(fn sidebar-width-stays-bounded-with-long-labels []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test" long-sidebar-node-loader)
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:rename-map! "main" "A graph map name that is deliberately long enough to exceed the sidebar width by many characters")
    (local active (manager:get-active-map))
    (active:load-by-key "test:long")
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                              :hoverables (make-hoverables-stub)}))
    (local entity ((GraphMapSidebar.GraphMapSidebar {:manager manager}) ctx))
    (entity:update)
    (entity.layout:measurer)
    (local action-row (actions-layout entity))
    (assert (>= entity.layout.measure.x 14.0)
            (.. "Sidebar measure should stay at/above preferred width, got " (tostring entity.layout.measure.x)))
    (assert (>= entity.layout.measure.x action-row.measure.x)
            "Sidebar measure should still include static action controls")
    (assert (< entity.layout.measure.x 30.0)
            (.. "Sidebar measure should remain bounded below raw long-label expansion, got "
                (tostring entity.layout.measure.x)))
    (layout-sidebar! entity entity.layout.measure.x 24.0)
    (assert (>= entity.layout.size.x 14.0)
            "Sidebar layout width should stay at/above preferred width")
    (assert (< entity.layout.size.x 30.0)
            "Sidebar layout width should remain bounded below raw long-label expansion")
    (entity:drop)
    (manager:drop)
    (graph:drop))

(fn sidebar-truncates-display-labels-and-preserves-finder-data []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test" long-finder-node-loader)
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (manager:rename-map! "main" "A graph map name that displays with an ellipsis in the sidebar row")
    (local active (manager:get-active-map))
    (local node (active:load-by-key "test:long"))
    (local reveal-store {:label nil})
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                              :hoverables (make-hoverables-stub)}))
    (local entity
        ((GraphMapSidebar.GraphMapSidebar
             {:manager manager
              :node-reveal-handler (reveal-label-recorder reveal-store)})
         ctx))
    (entity:update)
    (local labels (entity:visible-labels))
    (assert (contains-label? labels "A graph map name that di...")
            "Map row display label should be truncated with ellipsis")
    (assert (contains-label? labels "A finder node label tha...")
            "Finder row display label should be truncated with ellipsis")
    (local button (find-clickable-by-label "A finder node label tha..."))
    (assert button "Truncated finder row should be clickable")
    (button:on-click {:button 1})
    (assert (= reveal-store.label node.label)
            "Finder callback should receive node with full label")
    (entity:drop)
    (manager:drop)
    (graph:drop))

(fn sidebar-empty-finder-fills-resolved-content-width []
    (local graph (Graph {:with-start false}))
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                              :hoverables (make-hoverables-stub)}))
    (local entity ((GraphMapSidebar.GraphMapSidebar {:manager manager}) ctx))
    (entity:update)
    (entity.layout:measurer)
    (layout-sidebar! entity entity.layout.measure.x 24.0)
    (local layout (finder-layout entity))
    (assert (approx layout.size.x entity.layout.size.x)
            (.. "Finder area should fill resolved sidebar content width "
                (tostring entity.layout.size.x) ", got " (tostring layout.size.x)))
    (entity:drop)
    (manager:drop)
    (graph:drop))

(fn sidebar-node-finder-scrolls-within-allocated-height []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test" node-label-loader)
    (local manager (GraphMapManager.GraphMapManager {:graph graph}))
    (local active (manager:get-active-map))
    (for [idx 1 30]
        (active:load-by-key (.. "test:" idx)))
    (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                              :hoverables (make-hoverables-stub)}))
    (local entity ((GraphMapSidebar.GraphMapSidebar {:manager manager}) ctx))
    (entity:update)
    (local allocated-height 9.0)
    (layout-sidebar! entity 14.0 allocated-height)
    (local content-layout (content-flex-layout entity))
    (local finder (finder-layout entity))
    (local fixed-height (- content-layout.size.y finder.size.y))
    (local search-layout (. (. finder.children 1) :children 1))
    (local scroll-view-layout (. search-layout.children 2))
    (local scroll-area-layout (. scroll-view-layout.children 1))
    (local scroll-controller scroll-area-layout.scroll-controller)
    (assert (approx entity.layout.size.y allocated-height)
            (.. "GraphMapSidebar root should keep allocated height " allocated-height
                ", got " entity.layout.size.y))
    (assert (<= (+ finder.position.y finder.size.y) (+ entity.layout.position.y entity.layout.size.y 0.001))
            "Finder should remain inside the allocated sidebar height")
    (assert (> fixed-height 0)
            "Fixed graph-map management rows should keep positive height above the finder")
    (assert (<= scroll-view-layout.size.y (+ finder.size.y 0.001))
            "Finder scroll view should receive a bounded viewport height")
    (assert (and scroll-controller scroll-controller.state scroll-controller.state.scroll-enabled?)
            "Many finder rows should overflow the bounded viewport and enable scrolling")
    (entity:drop)
    (manager:drop)
    (graph:drop))

(table.insert tests {:name "GraphMapManager active-map-id updates after switch" :fn manager-active-map-id-updates-after-switch})
(table.insert tests {:name "GraphMapManager rename updates active-map-name" :fn manager-rename-updates-active-map-name})
(table.insert tests {:name "GraphMapManager active-map-status returns correct values" :fn manager-active-map-status-returns-correct-values})
(table.insert tests {:name "GraphMapManager next-map-id increments on create" :fn manager-next-map-id-increments-on-create})
(table.insert tests {:name "GraphMapManager delete updates active info" :fn manager-delete-updates-active-info})
(table.insert tests {:name "GraphMapManager switch emits correct payload" :fn manager-switch-emits-correct-payload})
(table.insert tests {:name "GraphMapManager capture-state preserves map names" :fn manager-capture-state-preserves-map-names})
(table.insert tests {:name "GraphMapManager allows delete main when not active" :fn manager-allows-delete-main-when-not-active})
(table.insert tests {:name "GraphMapManager rejects unsafe map ids" :fn manager-rejects-unsafe-map-ids})
(table.insert tests {:name "GraphMap sidebar constructs and drops" :fn sidebar-constructs-and-drops})
(table.insert tests {:name "GraphMap sidebar rebuilds on maps-changed" :fn sidebar-rebuilds-on-maps-changed})
(table.insert tests {:name "GraphMap sidebar labels map actions and selected count" :fn sidebar-exposes-map-labels-and-selected-count})
(table.insert tests {:name "GraphMap sidebar refreshes active map counts after map mutations" :fn sidebar-refreshes-active-map_counts_after_map_mutations})
(table.insert tests {:name "GraphMap sidebar Add Start is visible and idempotent"
                     :fn sidebar-add-start-is-visible-and-idempotent})
(table.insert tests {:name "GraphMap sidebar New button creates map without crashing" :fn sidebar-new-button-creates-map-without-crashing})
(table.insert tests {:name "GraphMap sidebar map rows do not stretch to full panel height" :fn sidebar-map-rows-do-not-stretch-to-full-panel-height})
(table.insert tests {:name "GraphMap sidebar node finder lists active map nodes"
                     :fn sidebar-node-finder-lists-active-map-nodes})
(table.insert tests {:name "GraphMap sidebar node finder clicks route callbacks"
                      :fn sidebar-node-finder-clicks-route_callbacks})
(table.insert tests {:name "GraphMap sidebar New uses integer map id after restored float"
                     :fn sidebar-new-button-uses-integer-map-id-after-restored-float})
(table.insert tests {:name "GraphMap sidebar width includes static action controls"
                     :fn sidebar-width-includes-static-action-controls})
(table.insert tests {:name "GraphMap sidebar width stays bounded with long labels"
                     :fn sidebar-width-stays-bounded-with-long-labels})
(table.insert tests {:name "GraphMap sidebar truncates display labels and preserves finder data"
                     :fn sidebar-truncates-display-labels-and-preserves-finder-data})
(table.insert tests {:name "GraphMap sidebar empty finder fills resolved content width"
                      :fn sidebar-empty-finder-fills-resolved-content-width})
(table.insert tests {:name "GraphMap sidebar node finder scrolls within allocated height"
                     :fn sidebar-node-finder-scrolls-within-allocated-height})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "graph-map-sidebar" :tests tests})))

{:name "graph-map-sidebar"
 :tests tests
 :main main}
