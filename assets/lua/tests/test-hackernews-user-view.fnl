(local BuildContext (require :build-context))
(local HackerNewsUserNode (require :graph/nodes/hackernews-user))

(fn make-ctx []
    (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                   :hoverables (assert app.hoverables "test requires app.hoverables")}))

(fn make-user []
    {:id "jl"
     :created 1173923446
     :karma 2937
     :about "This is a test user"})

(fn make-future [value]
    {:on-complete (fn [cb]
                      (cb true value nil :test)
                      value)
     :cancel (fn [] nil)})

(fn build-view [opts]
    (local ctx (make-ctx))
    (local options (or opts {}))
    (local node (HackerNewsUserNode {:id "jl"
                                     :user options.user
                                     :ensure-client options.ensure-client}))
    (node:mount {:ctx ctx})
    ((node.view node) ctx))

(fn row-texts [view]
    (icollect [_ entry (ipairs view.rows)]
        entry.text))

(local tests [{:name "hackernews user view renders provided user"
  :fn (fn []
          (local user (make-user))
          (local view (build-view {:user user
                                   :ensure-client (fn [] nil)}))
          (local texts (row-texts view))
          (assert (= (. texts 1) "User jl") "view should include user header row")
          (assert (string.find (. texts 4) "test user")
                  "view should render about text")
          (when view.drop (view:drop)))}
 {:name "hackernews user view fetches when missing user"
  :fn (fn []
          (local user (make-user))
          (var fetched? false)
          (local client {:fetch-user (fn [id]
                                         (set fetched? id)
                                         (make-future user))})
          (local view (build-view {:ensure-client (fn [] client)}))
          (assert (= fetched? "jl") "node should request user by id")
          (local texts (row-texts view))
          (assert (string.find (. texts 3) "Karma: 2937")
                  "view should render fetched karma")
          (when view.drop (view:drop)))}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hackernews-user-view"
                       :tests tests})))

{:name "hackernews-user-view"
 :tests tests
 :main main}
