(local glm (require :glm))

(local NextLayout (require :next-app/layout))
(local Node NextLayout.Node)
(local PanelWidget (require :next-app/panel-widget))

(fn clamp01 [value]
  (math.max 0 (math.min 1 (or value 0))))

(fn ProgressWidget [opts]
  (local options (or opts {}))
  (local width (or options.width 0.7))
  (local height (or options.height 0.1))
  (local fill-color (or options.fill-color (glm.vec4 0.37 0.62 0.98 1)))
  (local bg-color (or options.background-color (glm.vec4 0.16 0.19 0.26 1)))
  (var value (clamp01 options.value))

  (local background (PanelWidget {:name (or options.background-name "next-progress-bg")
                                  :padding [0 0]
                                  :color bg-color}))
  (local fill (PanelWidget {:name (or options.fill-name "next-progress-fill")
                            :padding [0 0]
                            :color fill-color}))

  (var progress nil)

  (fn measure-fn [self _mw _mh _md]
    (self:set-measure width height 0))

  (fn layout-fn [self resolved-width resolved-height depth]
    (self:set-size resolved-width resolved-height depth {:mark-dirty? false})
    (background:layout-set-frame 0 0 -0.001 resolved-width resolved-height 0 (glm.quat 1 0 0 0))
    (background:run-layout background.width background.height background.depth)
    (local fill-width (* resolved-width value))
    (fill:layout-set-frame 0 0 -0.002 fill-width resolved-height 0 (glm.quat 1 0 0 0))
    (fill:run-layout fill.width fill.height fill.depth))

  (set progress
       (Node.new {:name (or options.name "next-progress")
                  :measure-fn measure-fn
                  :layout-fn layout-fn}))
  (progress:add-child background)
  (progress:add-child fill)

  (set progress.background background)
  (set progress.fill fill)
  (set progress.value value)

  (set progress.set-value
       (fn [self next-value]
         (set value (clamp01 next-value))
         (set self.value value)
         (self:mark-layout-dirty)))

  (set progress.emit-quads
       (fn [_self quad-batcher clip-matrix]
         (background:emit-quads quad-batcher clip-matrix)
         (fill:emit-quads quad-batcher clip-matrix)))

  progress)

ProgressWidget
