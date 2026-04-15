(local _ (require :main))
(local glm (require :glm))
(local BuildContext (require :build-context))
(local LayoutStatsView (require :layout-stats-view))
(local RuntimeTimers (require :runtime-timers))

(local tests [])

(fn make-ui-context []
    (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                   :hoverables (assert app.hoverables "test requires app.hoverables")}))

(fn layout-stats-view-refreshes-and-stops-after-drop []
    (RuntimeTimers.clear)
    (local layout-root {:stats {:records [{:measure-dirt 2 :layout-dirt 3}
                                          {:measure-dirt 5 :layout-dirt 7}]}})
    (local ctx (make-ui-context))
    (local view
        ((LayoutStatsView {:layout-root layout-root
                           :max-frames 2
                           :size (glm.vec3 6 4 0)})
         ctx))
    (view.layout:measurer)
    (set view.layout.size view.layout.measure)
    (view.layout:layouter)

    (local bar-series (. view.series 1))
    (local measure-set (. bar-series.bar-sets 1))
    (local layout-set (. bar-series.bar-sets 2))
    (assert (= (. (. measure-set.points 1) :y) 2))
    (assert (= (. (. layout-set.points 1) :y) 3))
    (assert (= (. (. measure-set.points 2) :y) 5))
    (assert (= (. (. layout-set.points 2) :y) 7))

    (set layout-root.stats.records
         [{:measure-dirt 11 :layout-dirt 13}
          {:measure-dirt 17 :layout-dirt 19}])
    (app.engine.events.updated:emit 16)
    (assert (= (. (. measure-set.points 1) :y) 11))
    (assert (= (. (. layout-set.points 1) :y) 13))
    (assert (= (. (. measure-set.points 2) :y) 17))
    (assert (= (. (. layout-set.points 2) :y) 19))

    (view:drop)
    (set layout-root.stats.records
         [{:measure-dirt 23 :layout-dirt 29}
          {:measure-dirt 31 :layout-dirt 37}])
    (app.engine.events.updated:emit 16)
    (assert (= (. (. measure-set.points 1) :y) 11)
            "LayoutStatsView drop should stop background refresh")
    (assert (= (. (. layout-set.points 1) :y) 13)
            "LayoutStatsView drop should leave previous layout stats intact")
    (RuntimeTimers.clear))

(table.insert tests {:name "LayoutStatsView refreshes and stops after drop"
                     :fn layout-stats-view-refreshes-and-stops-after-drop})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "layout-stats-view"
                           :tests tests})))

{:name "layout-stats-view"
 :tests tests
 :main main}
