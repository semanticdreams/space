(local BuildContext (require :build-context))
(local HackerNewsStoryNode (require :graph/nodes/hackernews-story))

(fn make-ui-context []
  (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                 :hoverables (assert app.hoverables "test requires app.hoverables")}))

(local tests [{:name "hackernews story view guards missing future callbacks"
  :fn (fn []
          (local ctx (make-ui-context))
          (local client {:fetch-item (fn [_id]
                                         {:cancel (fn [] nil)})})
          (local node (HackerNewsStoryNode {:id 42
                                            :ensure-client (fn [] client)}))
          (node:mount {:ctx ctx :add-edge (fn [_self _edge] nil)})
          (local builder (node.view node))
          (local view (builder ctx))
          (local (ok err) (pcall (fn [] (view:fetch))))
          (assert ok err))}
 {:name "hackernews story view tolerates missing id"
  :fn (fn []
          (local (ok _err) (pcall (fn [] (HackerNewsStoryNode {}))))
          (assert (not ok) "Story node should require an id"))}
 {:name "hackernews story view adds user node for author"
 :fn (fn []
          (local ctx (make-ui-context))
          (local edges [])
          (local graph {:ctx ctx
                        :add-edge (fn [_self edge]
                                      (table.insert edges edge))})
          (local node (HackerNewsStoryNode {:id 7
                                            :item {:id 7
                                                   :by "dhouston"
                                                   :title "demo"}}))
          (node:mount graph)
          (local view ((node.view node) ctx))
          (assert view.actions "view should expose actions")
          (local by-action (. view.actions 1))
          (assert by-action "view should include by action")
          (assert (not (= by-action.enabled? false)) "by action should be enabled when author present")
          (view:add-user-node "dhouston")
          (assert (= (length edges) 1) "by action should add exactly one edge")
          (assert (. (. edges 1) :target) "edge should include a target node")
          (assert (= (. (. (. edges 1) :target) :id) "dhouston") "user node should use the author id")
          (when view.drop (view:drop)))}
 {:name "hackernews story view disables by action when author missing"
 :fn (fn []
          (local ctx (make-ui-context))
          (local graph {:ctx ctx
                        :add-edge (fn [_self _edge] nil)})
          (local node (HackerNewsStoryNode {:id 9
                                            :item {:id 9
                                                   :title "no author"}}))
          (node:mount graph)
          (local view ((node.view node) ctx))
          (local by-action (. view.actions 1))
          (assert by-action "view should still expose by action")
          (assert (= by-action.enabled? false) "by action should be disabled without an author")
          (when view.drop (view:drop)))}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hackernews-story-view"
                       :tests tests})))

{:name "hackernews-story-view"
 :tests tests
 :main main}
