(local glm (require :glm))

(local Signal (require :signal))
(local NextLayout (require :next-app/layout))
(local Node NextLayout.Node)
(local PanelWidget (require :next-app/panel-widget))
(local TextWidget (require :next-app/text-widget))

(fn ToggleWidget [opts]
  (local options (or opts {}))
  (local clickables options.clickables)
  (local hoverables options.hoverables)
  (local gap (or options.gap 0.08))
  (local width (or options.width 0.36))
  (local height (or options.height 0.16))
  (local knob-padding (or options.knob-padding 0.02))
  (var checked? (not (= options.checked? false)))

  (local on-color (or options.on-color (glm.vec4 0.20 0.72 0.45 1)))
  (local off-color (or options.off-color (glm.vec4 0.28 0.32 0.40 1)))
  (local knob-color (or options.knob-color (glm.vec4 0.95 0.95 0.98 1)))

  (local track (PanelWidget {:name (or options.track-name "next-toggle-track")
                             :padding [0 0]
                             :color (if checked? on-color off-color)}))
  (local knob (PanelWidget {:name (or options.knob-name "next-toggle-knob")
                            :padding [0 0]
                            :color knob-color}))
  (local label (and options.text
                    (TextWidget {:name (or options.label-name "next-toggle-label")
                                 :text options.text
                                 :scale (or options.text-scale 0.055)})))

  (var toggle nil)

  (fn set-track-color []
    (track:set-color (if checked? on-color off-color)))

  (fn measure-fn [self max-width max-height max-depth]
    (when label
      (label:run-measure max-width max-height max-depth))
    (local total-width (+ width (if label (+ gap label.measured-width) 0)))
    (local total-height (math.max height (if label label.measured-height 0)))
    (self:set-measure total-width total-height 0))

  (fn layout-fn [self resolved-width resolved-height depth]
    (self:set-size resolved-width resolved-height depth {:mark-dirty? false})

    (local y (/ (- resolved-height height) 2))
    (track:layout-set-frame 0 y -0.001 width height 0 (glm.quat 1 0 0 0))
    (track:run-layout track.width track.height track.depth)

    (local knob-size (math.max 0 (- height (* knob-padding 2))))
    (local knob-x (if checked?
                      (- width knob-size knob-padding)
                      knob-padding))
    (knob:layout-set-frame knob-x (+ y knob-padding) -0.002 knob-size knob-size 0 (glm.quat 1 0 0 0))
    (knob:run-layout knob.width knob.height knob.depth)

    (when label
      (local label-x (+ width gap))
      (local label-y (/ (- resolved-height label.measured-height) 2))
      (label:layout-set-frame label-x label-y 0 label.measured-width label.measured-height 0 (glm.quat 1 0 0 0))
      (label:run-layout label.width label.height label.depth)))

  (set toggle
       (Node.new {:name (or options.name "next-toggle")
                  :measure-fn measure-fn
                  :layout-fn layout-fn}))
  (toggle:add-child track)
  (toggle:add-child knob)
  (when label
    (toggle:add-child label))

  (local changed (Signal))
  (local clicked (Signal))

  (set toggle.changed changed)
  (set toggle.clicked clicked)
  (set toggle.track track)
  (set toggle.knob knob)
  (set toggle.label label)
  (set toggle.checked? checked?)

  (set toggle.set-checked
       (fn [self value]
         (local next (not (= value false)))
         (when (not (= checked? next))
           (set checked? next)
           (set self.checked? checked?)
           (set-track-color)
           (self:mark-layout-dirty)
           (changed:emit {:checked? checked?}))))

  (set toggle.toggle
       (fn [self]
         (self:set-checked (not checked?))))

  (set toggle.on-click
       (fn [self event]
         (self:toggle)
         (clicked:emit event)))

  (set toggle.emit-quads
       (fn [_self quad-batcher clip-matrix]
         (track:emit-quads quad-batcher clip-matrix)
         (knob:emit-quads quad-batcher clip-matrix)))

  (set toggle.drop
       (fn [self]
         (when (and clickables clickables.unregister)
           (assert clickables "ToggleWidget requires clickables for drop cleanup")
           (clickables:unregister self))
         (when (and hoverables hoverables.unregister)
           (assert hoverables "ToggleWidget requires hoverables for drop cleanup")
           (hoverables:unregister self))
         (self.changed:clear)
         (self.clicked:clear)))

  (when (and clickables clickables.register)
    (assert clickables "ToggleWidget requires clickables for toggle registration")
    (clickables:register toggle))
  (when (and hoverables hoverables.register)
    (assert hoverables "ToggleWidget requires hoverables for hover registration")
    (hoverables:register toggle))
  (set-track-color)
  toggle)

ToggleWidget
