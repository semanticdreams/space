(local glm (require :glm))
(local Chart (require :chart))
(local BarSeries (require :bar-series))
(local LineSeries (require :line-series))
(local ScatterSeries (require :scatter-series))
(local BuildContext (require :build-context))
(local MathUtils (require :math-utils))

(local tests [])

(local approx (. MathUtils :approx))

(fn make-ui-context []
    (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                   :hoverables (assert app.hoverables "test requires app.hoverables")}))

(fn chart-renders-series-into-buffers []
    (local ctx (make-ui-context))
    (local chart ((Chart {:size (glm.vec3 9 5 0)
                          :series [(BarSeries {:data [2 4 3]})
                                   (LineSeries {:points [[0 1] [1 2] [2 1]]})
                                   (ScatterSeries {:points [[0.2 0.5] [1.5 1.2] [2.2 0.7]]
                                                   :size 9
                                                   :color (glm.vec4 1 0.9 0.6 1)})]}) ctx))
    (chart.layout:measurer)
    (set chart.layout.size chart.layout.measure)
    (chart.layout:layouter)
    (assert (approx chart.layout.measure.x 9))
    (assert (= (length chart.series) 3))
    (local bar-series (. chart.series 1))
    (assert (= (length bar-series.bars) 3))
    (local first-bar (. bar-series.bars 1))
    (assert (> first-bar.layout.size.y 0))
    (assert (> (ctx.triangle-vector:length) 0))
    (assert (= (length ctx.line-strips) 1))
    (assert (> (ctx.point-vector:length) 0))
    (local scatter (. chart.series 3))
    (local first-point (. scatter.points 1))
    (assert first-point.position)
    (chart:drop))

(fn bar-series-sits-above-background []
    (local ctx (make-ui-context))
    (local chart ((Chart {:size (glm.vec3 3 2 0)
                          :series [(BarSeries {:data [1]})]}) ctx))
    (chart.layout:measurer)
    (set chart.layout.depth-offset-index 2)
    (set chart.layout.size chart.layout.measure)
    (chart.layout:layouter)
    (local bar-series (. chart.series 1))
    (local first-bar (. bar-series.bars 1))
    (assert (= first-bar.layout.depth-offset-index (+ chart.layout.depth-offset-index 1)))
    (chart:drop))

(fn bar-series-supports-multiple-sets []
    (local ctx (make-ui-context))
    (local chart ((Chart {:size (glm.vec3 4 3 0)
                          :series [(BarSeries {:bar-sets [{:data [1 2]}
                                                          {:data [2 1]}]})]}) ctx))
    (chart.layout:measurer)
    (set chart.layout.size chart.layout.measure)
    (chart.layout:layouter)
    (local bar-series (. chart.series 1))
    (assert (= (length bar-series.bars) 4))
    (assert (= (length bar-series.bar-sets) 2))
    (local first (. bar-series.bar-sets 1))
    (local second (. bar-series.bar-sets 2))
    (local left-bar (. first.bars 1))
    (local right-bar (. second.bars 1))
    (assert right-bar)
    (assert left-bar)
    (assert (> (math.abs (- left-bar.layout.position.x right-bar.layout.position.x)) 1e-4))
    (assert (> left-bar.layout.size.x 0))
    (assert (> right-bar.layout.size.x 0))
    (chart:drop))

(table.insert tests {:name "Chart renders bar, line, and scatter series" :fn chart-renders-series-into-buffers})
(table.insert tests {:name "Bar series sits above background" :fn bar-series-sits-above-background})
(table.insert tests {:name "Bar series supports multiple sets" :fn bar-series-supports-multiple-sets})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "chart"
                       :tests tests})))

{:name "chart"
 :tests tests
 :main main}
