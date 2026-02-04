(local SearchView (require :search-view))
(local BuildContext (require :build-context))

(local tests [])

(fn make-ui-context []
    (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                   :hoverables (assert app.hoverables "test requires app.hoverables")}))

(fn search-view-filters-items []
    (local ctx (make-ui-context))
    (local builder
        (SearchView {:items [[{:key "a"} "alpha"]
                             [{:key "b"} "beta"]]
                     :name "filter-test"}))
    (local view (builder ctx))
    (assert (= (length view.list-view.items) 2)
            "SearchView should keep initial items")
    (assert (= view.list-view.scroll? true)
            "SearchView should enable scrolling on list view")
    (assert (= view.list-view.scrollbar-policy :as-needed)
            "SearchView should use as-needed scrollbars")
    (view.input.model:set-text "alp")
    (assert (= (length view.list-view.items) 1)
            "SearchView should filter items by query")
    (local first (. view.list-view.items 1))
    (assert (= (. first 2) "alpha")
            "Filtered list should keep matching label")
    (view:drop))

(fn search-view-default-builder-emits-submitted []
    (local ctx (make-ui-context))
    (local builder (SearchView {:items [[{:key "a"} "alpha"]]
                                :name "submit-test"}))
    (local view (builder ctx))
    (local captured [])
    (view.submitted:connect (fn [item]
        (table.insert captured item)))
    (local button (. view.list-view.item-widgets 1))
    (button.clicked:emit nil)
    (assert (= (length captured) 1)
            "SearchView should emit submitted when default button clicked")
    (assert (= (. (. captured 1) 2) "alpha")
            "Submitted payload should include the selected item")
    (view:drop))

(table.insert tests {:name "SearchView filters items with query" :fn search-view-filters-items})
(table.insert tests {:name "SearchView default builder emits submitted" :fn search-view-default-builder-emits-submitted})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "search-view"
                       :tests tests})))

{:name "search-view"
 :tests tests
 :main main}
