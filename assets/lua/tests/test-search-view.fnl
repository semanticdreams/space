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

(fn search-view-double-drop-errors []
    (local ctx (make-ui-context))
    (local view ((SearchView {:items [[{:key "a"} "alpha"]]
                              :name "double-drop-test"})
                 ctx))
    (view:drop)
    (local (ok err)
        (pcall (fn []
                 (view:drop))))
    (assert (not ok) "Dropping SearchView twice should error")
    (assert (string.find (tostring err) "SearchView dropped twice" 1 true)))

(fn search-view-drop-drops-owned-children []
    (local ctx (make-ui-context))
    (local view ((SearchView {:items [[{:key "a"} "alpha"]]
                              :name "drop-children-test"})
                 ctx))
    (assert view.list-view.scroll-view "SearchView test expects ListView to build a scroll-view")
    (view:drop)
    (local (input-ok input-err)
        (pcall (fn []
                 (view.input:drop))))
    (assert (not input-ok) "SearchView drop should already drop its input child")
    (assert (string.find (tostring input-err) "Input dropped twice" 1 true))
    (assert (= view.list-view.scroll-view nil) "SearchView drop should tear down ListView scroll-view")
    (assert (= view.list-view.content-layout nil) "SearchView drop should tear down ListView content layout"))

(fn search-view-public-api-errors-after-drop []
    (local ctx (make-ui-context))
    (local view ((SearchView {:items [[{:key "a"} "alpha"]]
                              :name "post-drop-api-test"})
                 ctx))
    (view:drop)
    (local (set-ok set-err)
        (pcall (fn []
                 (view:set-items [[{:key "b"} "beta"]]))))
    (assert (not set-ok) "SearchView set-items should error after drop")
    (assert (string.find (tostring set-err) "SearchView set_items after drop" 1 true))
    (local (update-ok update-err)
        (pcall (fn []
                 (view:update-list-view))))
    (assert (not update-ok) "SearchView update-list-view should error after drop")
    (assert (string.find (tostring update-err) "SearchView update_list_view after drop" 1 true)))

(table.insert tests {:name "SearchView filters items with query" :fn search-view-filters-items})
(table.insert tests {:name "SearchView default builder emits submitted" :fn search-view-default-builder-emits-submitted})
(table.insert tests {:name "SearchView double drop errors" :fn search-view-double-drop-errors})
(table.insert tests {:name "SearchView drop drops owned children" :fn search-view-drop-drops-owned-children})
(table.insert tests {:name "SearchView public API errors after drop" :fn search-view-public-api-errors-after-drop})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "search-view"
                       :tests tests})))

{:name "search-view"
 :tests tests
 :main main}
