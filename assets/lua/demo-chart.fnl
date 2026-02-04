(local glm (require :glm))
(local Chart (require :chart))
(local BarSeries (require :bar-series))
(local DefaultDialog (require :default-dialog))
(local Padding (require :padding))

(local DemoChart {})

(fn DemoChart.new-dialog [opts]
  (local options (or opts {}))
  (local bar-series
    (BarSeries {:bar-sets [{:data [3.2 4.5 2.8 5.2 4.4]
                            :color (glm.vec4 0.32 0.72 1.0 0.9)}
                           {:data [2.4 3.3 3.5 4.1 3.9]
                            :color (glm.vec4 1.0 0.7 0.36 0.9)}]}))
  (local chart
    (Chart {:size (glm.vec3 10.5 6.2 0)
            :padding (glm.vec3 0.6 0.6 0)
            :series [bar-series]}))
  (DefaultDialog
    {:title "Telemetry Chart"
     :on-close options.on-close
     :child (Padding {:edge-insets [0.6 0.6]
                      :child chart})}))

DemoChart
