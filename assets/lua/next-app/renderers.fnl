(local glm (require :glm))
(local gl (require :gl))

(local QuadRenderer (require :quad-renderer))
(local TextSsboRenderer (require :text-ssbo-renderer))
(local TextSsboBatcher (require :text-ssbo-batcher))
(local LightingViewState (require :lighting-view-state))

(local NextLayout (require :next-app/layout))
(local NextFlex (require :next-app/flex))
(local QuadBatcher (require :next-app/quad-batcher))
(local PanelWidget (require :next-app/panel-widget))
(local ButtonWidget (require :next-app/button-widget))
(local TextWidget (require :next-app/text-widget))
(local ToggleWidget (require :next-app/toggle-widget))
(local ProgressWidget (require :next-app/progress-widget))
(local InputWidget (require :next-app/input-widget))
(local ScrollWidget (require :next-app/scroll-widget))
(local VirtualListWidget (require :next-app/virtual-list-widget))
(local InteractionRouter (require :next-app/interaction-router))
(local CuboidWidget (require :next-app/cuboid-widget))
(local NextNode NextLayout.Node)

(local default-cuboid-camera-position (glm.vec3 1.7 1.3 3.0))
(local default-cuboid-camera-target (glm.vec3 0 0 0))
(local default-cuboid-camera-up (glm.vec3 0 1 0))
(local default-orthographic-lighting-direction (glm.vec3 0 0 1))

(fn identity-rotation []
  (glm.quat 1 0 0 0))

(fn assert-vec3 [value context]
  (assert value (.. context " requires glm.vec3"))
  (assert (and (not (= value.x nil))
               (not (= value.y nil))
               (not (= value.z nil)))
          (.. context " requires glm.vec3"))
  value)

(fn resolve-cuboid-camera [renderer-options]
  (local camera (or renderer-options.camera {}))
  {:position (assert-vec3 (or camera.position default-cuboid-camera-position)
                          "NextAppRenderers cuboid camera position")
   :target (assert-vec3 (or camera.target default-cuboid-camera-target)
                        "NextAppRenderers cuboid camera target")
   :up (assert-vec3 (or camera.up default-cuboid-camera-up)
                    "NextAppRenderers cuboid camera up")})

(fn make-rng [seed]
  (var state (or seed 1))
  (fn next-float []
    (set state (% (+ (* state 1664525) 1013904223) 4294967296))
    (/ state 4294967296.0))
  next-float)

(fn random-range [next-float min max]
  (+ min (* (next-float) (- max min))))

(fn random-string [next-float len]
  (local chars "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
  (var out "")
  (for [_ 1 len]
    (local idx (+ 1 (math.floor (* (next-float) (# chars)))))
    (set out (.. out (string.sub chars idx idx))))
  out)

(fn random-int-range [next-float min max]
  (local span (+ 1 (- max min)))
  (+ min (math.floor (* (next-float) span))))

(fn random-multiline-text [next-float]
  (local line-count (random-int-range next-float 3 20))
  (var out "")
  (for [line 1 line-count]
    (local line-length (random-int-range next-float 3 28))
    (set out (.. out (random-string next-float line-length)))
    (when (< line line-count)
      (set out (.. out "\n"))))
  out)

(fn random-unit-axis [next-float]
  (local x (random-range next-float -1 1))
  (local y (random-range next-float -1 1))
  (local z (random-range next-float -1 1))
  (local mag (math.sqrt (+ (* x x) (* y y) (* z z))))
  (if (< mag 1e-6)
      (glm.vec3 0 0 1)
      (glm.vec3 (/ x mag) (/ y mag) (/ z mag))))

(fn random-face-color [next-float]
  (glm.vec4 (random-range next-float 0.20 0.82)
            (random-range next-float 0.20 0.82)
            (random-range next-float 0.20 0.82)
            0.95))

(fn fixed-ten-lines [prefix]
  (.. prefix " 01\n"
      prefix " 02\n"
      prefix " 03\n"
      prefix " 04\n"
      prefix " 05\n"
      prefix " 06\n"
      prefix " 07\n"
      prefix " 08\n"
      prefix " 09\n"
      prefix " 10"))

(fn build-face [name text color opts]
  (local text-scale (or (and opts opts.text-scale) 0.03))
  (local text-padding (or (and opts opts.text-padding) [0.02 0.02]))
  (local text-depth-offset (or (and opts opts.text-depth-offset) 0.001))
  (local panel (PanelWidget {:name (.. name "-panel")
                             :padding [0 0]
                             :color color}))
  (local label
    (if text
        (TextWidget {:name (.. name "-text")
                     :text text
                     :scale text-scale})
        nil))
  (local pad-x (or (. text-padding 1) 0))
  (local pad-y (or (. text-padding 2) 0))
  (local face
    (NextNode.new
      {:name name
       :measure-fn (fn [self max-width max-height max-depth]
                     (panel:run-measure max-width max-height max-depth)
                     (var measured-width panel.measured-width)
                     (var measured-height panel.measured-height)
                     (when label
                       (label:run-measure max-width max-height max-depth)
                       (set measured-width (math.max measured-width
                                                    (+ label.measured-width (* pad-x 2))))
                       (set measured-height (math.max measured-height
                                                     (+ label.measured-height (* pad-y 2)))))
                     (self:set-measure measured-width measured-height 0))
       :layout-fn (fn [self width height depth]
                    (self:set-size width height depth {:mark-dirty? false})
                    (panel:layout-set-frame 0 0 0 width height 0 (identity-rotation))
                    (panel:run-layout panel.width panel.height panel.depth)
                    (when label
                      (local label-y (math.max pad-y (- height pad-y label.measured-height)))
                      (label:layout-set-frame pad-x
                                              label-y
                                              text-depth-offset
                                              (math.max 0 (- width (* pad-x 2)))
                                              (math.max 0 (- height (* pad-y 2)))
                                              0
                                              (identity-rotation))
                      (label:run-layout label.width label.height label.depth)))}))
  (face:add-child panel)
  (when label
    (face:add-child label))
  (set face.emit-quads
       (fn [_self quad-batcher clip-matrix]
         (panel:emit-quads quad-batcher clip-matrix)))
  (set face.emit-ssbo
       (fn [_self text-batcher clip-matrix]
         (when label
           (label:emit-ssbo text-batcher clip-matrix))))
  face)

(fn resolve-entry-size [entry node]
  (if (= entry.use-measured-size true)
      (do
        (local measured-w (math.max 0.01 node.measured-width))
        (local measured-h (math.max 0.01 node.measured-height))
        (local measured-d (math.max 0.01 node.measured-depth))
        (local measured-max (math.max measured-w measured-h measured-d))
        (local target-max (or entry.measured-target-max
                              (or entry.measured-fit-max measured-max)))
        (local scale
          (if (> measured-max 0)
              (/ target-max measured-max)
              1.0))
        {:w (* measured-w scale)
         :h (* measured-h scale)
         :d (* measured-d scale)})
      {:w entry.w :h entry.h :d entry.d}))

(fn resolve-entry-position [entry size]
  (if (= entry.center-on-origin true)
      {:x (- 0 (/ size.w 2))
       :y (- 0 (/ size.h 2))
       :z (- 0 (/ size.d 2))}
      {:x entry.x :y entry.y :z entry.z}))

(fn build-cuboid-cloud [renderer-options]
  (local count (or renderer-options.cuboid-count 100))
  (if (<= count 0)
      []
      (do
        (local next-float (make-rng (or renderer-options.cuboid-seed 1337)))
        (local base-rot-y (glm.quat 0.72 (glm.vec3 0 1 0)))
        (local base-rot-x (glm.quat -0.52 (glm.vec3 1 0 0)))
        (if (= count 1)
            (do
              (local cuboid (CuboidWidget {:name "next-cuboid-1"
                                           :children [(build-face "next-cuboid-front-1" (fixed-ten-lines "FRONT") (glm.vec4 1.0 0.1 0.1 1.0)
                                                                  {:text-padding [0.03 0.03]})
                                                      (build-face "next-cuboid-back-1" (fixed-ten-lines "BACK") (glm.vec4 0.1 1.0 0.1 1.0)
                                                                  {:text-padding [0.03 0.03]})
                                                      (build-face "next-cuboid-left-1" (fixed-ten-lines "LEFT") (glm.vec4 0.1 0.4 1.0 1.0)
                                                                  {:text-padding [0.03 0.03]})
                                                      (build-face "next-cuboid-right-1" (fixed-ten-lines "RIGHT") (glm.vec4 1.0 0.2 0.9 1.0)
                                                                  {:text-padding [0.03 0.03]})
                                                      (build-face "next-cuboid-top-1" nil (glm.vec4 1.0 1.0 0.2 1))
                                                      (build-face "next-cuboid-bottom-1" nil (glm.vec4 0.4 0.9 1.0 1))]}))
              [{:node cuboid
                :x 0
                :y 0
                :z 0
                :use-measured-size true
                :measured-target-max 1.20
                :center-on-origin true
                :rotation (glm.quat 1 0 0 0)}])
            (do
              (local columns (math.max 1 (math.floor (+ 0.5 (math.sqrt count)))))
              (local rows (math.max 1 (math.ceil (/ count columns))))
              (local min-x -1.52)
              (local max-x 1.52)
              (local min-y -0.88)
              (local max-y 0.88)
              (local span-x (- max-x min-x))
              (local span-y (- max-y min-y))
              (local cell-w (/ span-x columns))
              (local cell-h (/ span-y rows))
              (local cuboids [])
              (for [i 1 count]
                (local front-text (random-multiline-text next-float))
                (local back-text (random-multiline-text next-float))
                (local left-text (random-multiline-text next-float))
                (local right-text (random-multiline-text next-float))
                (local front-color (random-face-color next-float))
                (local back-color (random-face-color next-float))
                (local left-color (random-face-color next-float))
                (local right-color (random-face-color next-float))
                (local top-color (random-face-color next-float))
                (local bottom-color (random-face-color next-float))
                (local cuboid
                  (CuboidWidget {:name (.. "next-cuboid-" i)
                                 :children [(build-face (.. "next-cuboid-front-" i) front-text front-color
                                                        {:text-padding [0.01 0.01]})
                                            (build-face (.. "next-cuboid-back-" i) back-text back-color
                                                        {:text-padding [0.01 0.01]})
                                            (build-face (.. "next-cuboid-left-" i) left-text left-color
                                                        {:text-padding [0.01 0.01]})
                                            (build-face (.. "next-cuboid-right-" i) right-text right-color
                                                        {:text-padding [0.01 0.01]})
                                            (build-face (.. "next-cuboid-top-" i) nil top-color)
                                            (build-face (.. "next-cuboid-bottom-" i) nil bottom-color)]}))
                (local col (% (- i 1) columns))
                (local row (math.floor (/ (- i 1) columns)))
                (local grid-x (+ min-x (* (+ col 0.5) cell-w)))
                (local grid-y (- max-y (* (+ row 0.5) cell-h)))
                (local x (+ grid-x (random-range next-float (* -0.28 cell-w) (* 0.28 cell-w))))
                (local y (+ grid-y (random-range next-float (* -0.28 cell-h) (* 0.28 cell-h))))
                (local z (random-range next-float -0.16 0.22))
                (local twist (glm.quat (random-range next-float -0.28 0.28) (glm.vec3 0 0 1)))
                (table.insert cuboids
                              {:node cuboid
                               :x x
                               :y y
                               :z z
                               :use-measured-size true
                               :rotation (* twist (* base-rot-y base-rot-x))}))
              cuboids)))))

(fn build-ui-root [renderer-options]
  (local router (InteractionRouter.new))
  (var focus-context nil)
  (when (= renderer-options.enable-focus true)
    (local {: FocusManager} (require :focus))
    (local manager (FocusManager {:root-name "next-app-focus"}))
    (local root-scope (manager:get-root-scope))
    (local scope (manager:create-scope {:name "next-app-scope"}))
    (manager:attach scope root-scope)
    (set focus-context {:manager manager
                        :create-node (fn [_self opts]
                                       (local node (manager:create-node opts))
                                       (manager:attach node scope)
                                       node)
                        :attach-bounds (fn [_self node opts]
                                         (when (and node opts opts.get-focus-bounds)
                                           (set node.get-focus-bounds opts.get-focus-bounds)))})
    (set router.focus-manager manager))

  (local title
    (TextWidget {:name "next-app-title"
                 :text (or renderer-options.title "Next App")
                 :scale (or renderer-options.title-scale 0.11)}))
  (local subtitle
    (TextWidget {:name "next-app-subtitle"
                 :text (or renderer-options.subtitle "New widgets on next-layout")
                 :scale (or renderer-options.subtitle-scale 0.07)}))
  (local note
    (TextWidget {:name "next-app-note"
                 :text (or renderer-options.note "Panel + Flex + Button + Toggle + Progress + SSBO text")
                 :scale (or renderer-options.note-scale 0.055)}))

  (local run-button
    (ButtonWidget {:name "next-button-run"
                   :text "Run"
                   :variant :secondary
                   :focus focus-context
                   :clickables router
                   :hoverables router
                   :text-scale 0.06
                   :background-color (glm.vec4 0.15 0.46 0.95 0.96)
                   :hover-background-color (glm.vec4 0.20 0.52 0.98 1)
                   :pressed-background-color (glm.vec4 0.10 0.36 0.85 1)}))
  (local inspect-button
    (ButtonWidget {:name "next-button-inspect"
                   :text "Inspect"
                   :variant :secondary
                   :focus focus-context
                   :clickables router
                   :hoverables router
                   :text-scale 0.06
                   :background-color (glm.vec4 0.18 0.62 0.72 0.96)
                   :hover-background-color (glm.vec4 0.22 0.68 0.78 1)
                   :pressed-background-color (glm.vec4 0.12 0.50 0.62 1)}))
  (local ship-button
    (ButtonWidget {:name "next-button-ship"
                   :text "Ship"
                   :variant :secondary
                   :focus focus-context
                   :clickables router
                   :hoverables router
                   :text-scale 0.06
                   :background-color (glm.vec4 0.62 0.30 0.86 0.96)
                   :hover-background-color (glm.vec4 0.69 0.36 0.91 1)
                   :pressed-background-color (glm.vec4 0.52 0.24 0.72 1)}))

  (local button-row
    (NextFlex.Flex {:name "next-button-row"
                    :axis :x
                    :gap 0.06
                    :children [(NextFlex.FlexChild run-button 1)
                               (NextFlex.FlexChild inspect-button 1)
                               (NextFlex.FlexChild ship-button 1)]}))

  (local perf-toggle
    (ToggleWidget {:name "next-toggle-perf"
                   :text "Perf mode"
                   :checked? true
                   :clickables router
                   :hoverables router
                   :width 0.34
                   :height 0.16
                   :on-color (glm.vec4 0.22 0.80 0.56 1)
                   :off-color (glm.vec4 0.30 0.16 0.16 1)
                   :knob-color (glm.vec4 1 1 1 1)}))
  (local logs-toggle
    (ToggleWidget {:name "next-toggle-logs"
                   :text "Verbose logs"
                   :checked? false
                   :clickables router
                   :hoverables router
                   :width 0.34
                   :height 0.16
                   :on-color (glm.vec4 0.22 0.80 0.56 1)
                   :off-color (glm.vec4 0.30 0.16 0.16 1)
                   :knob-color (glm.vec4 1 1 1 1)}))
  (local toggle-row
    (NextFlex.Flex {:name "next-toggle-row"
                    :axis :x
                    :gap 0.18
                    :children [(NextFlex.FlexChild perf-toggle 0)
                               (NextFlex.FlexChild logs-toggle 0)]}))

  (local perf-label
    (TextWidget {:name "next-perf-label"
                 :text "Frame budget"
                 :scale 0.05}))
  (local perf-progress
    (ProgressWidget {:name "next-perf-progress"
                     :value 0.62
                     :width 0.74
                     :height 0.11
                     :fill-color (glm.vec4 0.48 0.74 1.00 1)
                     :background-color (glm.vec4 0.12 0.14 0.20 1)}))
  (local perf-row
    (NextFlex.Flex {:name "next-progress-row"
                    :axis :x
                    :gap 0.08
                    :align-cross :center
                    :children [(NextFlex.FlexChild perf-label 0)
                               (NextFlex.FlexChild perf-progress 1)]}))

  (local search-input
    (InputWidget {:name "next-input-search"
                  :focus focus-context
                  :placeholder "Search items"
                  :text (or renderer-options.input-text "")
                  :width 0.95
                  :height 0.16
                  :text-scale 0.048}))

  (local virtual-list
    (VirtualListWidget {:name "next-virtual-list"
                        :item-count (or renderer-options.item-count 180)
                        :item-height 0.08
                        :width 0.95
                        :height 0.36
                        :item-builder (fn [idx]
                                        (PanelWidget {:name (.. "next-row-" idx)
                                                      :padding [0.02 0.015]
                                                      :color (if (= (% idx 2) 0)
                                                                 (glm.vec4 0.13 0.17 0.26 0.95)
                                                                 (glm.vec4 0.10 0.14 0.22 0.95))
                                                      :child (TextWidget {:text (.. "Item " idx)
                                                                          :scale 0.041})}))}))

  (local scroll
    (ScrollWidget {:name "next-scroll"
                   :width 0.95
                   :height 0.36
                   :child virtual-list}))

  (local io-column
    (NextFlex.Flex {:name "next-io-column"
                    :axis :y
                    :gap 0.06
                    :children [(NextFlex.FlexChild search-input 0)
                               (NextFlex.FlexChild scroll 0)]}))

  (local content
    (NextFlex.Flex {:name "next-content"
                    :axis :y
                    :gap 0.08
                    :children [(NextFlex.FlexChild title 0)
                               (NextFlex.FlexChild subtitle 0)
                               (NextFlex.FlexChild note 0)
                               (NextFlex.FlexChild button-row 0)
                               (NextFlex.FlexChild toggle-row 0)
                               (NextFlex.FlexChild perf-row 0)
                               (NextFlex.FlexChild io-column 0)]}))

  (local card
    (PanelWidget {:name "next-card"
                  :padding [0.08 0.08]
                  :color (glm.vec4 0.11 0.14 0.22 0.92)
                  :child content}))

  (local footer-text
    (TextWidget {:name "next-footer-text"
                 :text (or renderer-options.footer "Snapshot Demo")
                 :scale (or renderer-options.footer-scale 0.06)}))
  (local footer
    (PanelWidget {:name "next-footer"
                  :padding [0.05 0.04]
                  :color (glm.vec4 0.07 0.10 0.16 0.88)
                  :child footer-text}))

  (local root
    (NextFlex.Flex {:name "next-ui-root"
                    :axis :y
                    :gap 0.08
                    :children [(NextFlex.FlexChild card 1)
                               (NextFlex.FlexChild footer 0)]}))
  (local cuboids (build-cuboid-cloud renderer-options))
  (local cloud-root
    (NextLayout.Node.new {:name "next-cuboid-cloud"
                          :measure-fn (fn [self _mw _mh _md]
                                        (self:set-measure 0 0 0))
                          :layout-fn (fn [self width height depth]
                                       (self:set-size width height depth {:mark-dirty? false})
                                       (each [_ entry (ipairs cuboids)]
                                         (local node entry.node)
                                         (local size (resolve-entry-size entry node))
                                         (local pos (resolve-entry-position entry size))
                                         (node:layout-set-frame pos.x
                                                                pos.y
                                                                pos.z
                                                                size.w
                                                                size.h
                                                                size.d
                                                                entry.rotation)
                                         (node:run-layout node.width node.height node.depth)))}))
  (each [_ entry (ipairs cuboids)]
    (cloud-root:add-child entry.node))
  (local show-ui? false)
  (local scene-root
    (NextLayout.Node.new {:name "next-scene-root"
                          :measure-fn (fn [self max-width max-height _max-depth]
                                        (self:set-measure max-width max-height 0))
                          :layout-fn (fn [self width height depth]
                                       (self:set-size width height depth {:mark-dirty? false})
                                       (when show-ui?
                                         (root:layout-set-frame 0 0 0 width height 0 (identity-rotation))
                                         (root:run-layout root.width root.height root.depth))
                                       (cloud-root:layout-set-frame 0 0 0 width height depth (identity-rotation))
                                       (cloud-root:run-layout cloud-root.width cloud-root.height cloud-root.depth))}))
  (scene-root:add-child cloud-root)
  (when show-ui?
    (scene-root:add-child root))
  (local root-position
    (or renderer-options.root-position
        {:x 0 :y 0 :z 0 :rotation (glm.quat 1 0 0 0)}))
  (scene-root:set-local-position root-position.x
                                 root-position.y
                                 (or root-position.z 0)
                                 (or root-position.rotation (glm.quat 1 0 0 0)))
  {:root scene-root
   :router router
   :focus-context focus-context
   :run-button run-button
   :inspect-button inspect-button
   :ship-button ship-button
   :search-input search-input
   :virtual-list virtual-list})

(fn NextAppRenderers [opts]
  (local options (or opts {}))
  (local renderer-options (or options.renderer-options {}))
  (local quad-renderer (QuadRenderer))
  (local text-renderer (TextSsboRenderer))
  (local text-batcher (TextSsboBatcher {}))
  (local quad-batcher (QuadBatcher {:instance-stride quad-renderer.instance-stride}))
  (local explicit-lighting-view-state
    (and renderer-options.lighting-view-state
         (LightingViewState.normalize-state renderer-options.lighting-view-state
                                            "NextAppRenderers lighting view state")))
  (var projection (glm.mat4 1))
  (var view (glm.mat4 1))
  (var lighting-view-state nil)
  (var viewport-width (or (and options.size options.size.x) 300))
  (var viewport-height (or (and options.size options.size.y) 200))
  (local ui (build-ui-root renderer-options))
  (local root ui.root)
  (local emitted-subtree-version (setmetatable {} {:__mode "k"}))
  (local emitted-transform-version (setmetatable {} {:__mode "k"}))
  (var clip-cache {})
  (var scenario-applied false)
  (var last-submit-stats {:traversal-seconds 0
                          :submit-seconds 0
                          :write-seconds 0
                          :write-count 0
                          :upsert-count 0
                          :gl-upload-seconds 0
                          :draw-cpu-seconds 0
                          :gpu-upload-seconds 0
                          :gpu-draw-seconds 0})

  (fn apply-scenario []
    (when (not scenario-applied)
      (set scenario-applied true)
      (local scenario (or renderer-options.scenario :default))
      (when (and (= renderer-options.cuboid-only? true)
                 app
                 app.lights)
        (app.lights:set-ambient (glm.vec3 1 1 1))
        (app.lights:set-directional [])
        (app.lights:set-point [])
        (app.lights:set-spot []))
      (if (= scenario :focused)
          (do
            (when ui.run-button
              (ui.run-button:on-hovered true))
            (when ui.inspect-button
              (ui.inspect-button:on-pressed true))
            (when ui.search-input
              (ui.search-input:set-focused true)
              (when (not (= (ui.search-input:get-text) "cpu > 0.7"))
                (ui.search-input:set-text "cpu > 0.7"))))
          (if (= scenario :scrolled)
              (do
                (when ui.virtual-list
                  (ui.virtual-list:set-scroll-y 6.4))
                (when ui.search-input
                  (when (not (= (ui.search-input:get-text) "item"))
                    (ui.search-input:set-text "item"))
                  (ui.search-input:set-focused false)))
              nil))))

  (fn update-projection []
    (if (= renderer-options.cuboid-only? true)
        (do
          (local camera (resolve-cuboid-camera renderer-options))
          (local aspect (if (= viewport-height 0) 1 (/ viewport-width viewport-height)))
          (set projection (glm.perspective (math.rad 52) aspect 0.01 20.0))
          (set view (glm.lookAt camera.position
                                camera.target
                                camera.up))
          (set lighting-view-state
               (or explicit-lighting-view-state
                   (LightingViewState.perspective camera.position))))
        (do
          (set projection (glm.mat4 1))
          (set view (glm.mat4 1))
          (set lighting-view-state
               (or explicit-lighting-view-state
                   (LightingViewState.orthographic default-orthographic-lighting-direction))))))

  (fn emit-subtree [node inherited-clip-matrix force-reemit]
    (local subtree-version (or node._subtree-render-version 0))
    (local transform-version (or node._transform-version 0))
    (local should-reemit
      (or force-reemit
          (not (= (. emitted-subtree-version node) subtree-version))
          (not (= (. emitted-transform-version node) transform-version))))
    (when should-reemit
      (var active-clip-matrix inherited-clip-matrix)
      (when (and node node.get-clip-matrix)
        (set active-clip-matrix (node:get-clip-matrix inherited-clip-matrix)))
      (when (and node node.emit-quads)
        (node:emit-quads quad-batcher active-clip-matrix))
      (when (and node node.emit-ssbo)
        (node:emit-ssbo text-batcher active-clip-matrix))
      (each [_ child (ipairs node.children)]
        (emit-subtree child active-clip-matrix should-reemit))
      (set (. emitted-subtree-version node) subtree-version)
      (set (. emitted-transform-version node) transform-version)))

  (fn resolve-node-clip [node]
    (local cached (. clip-cache node))
    (if (not (= cached nil))
        cached
        (do
          (local inherited
            (if node.parent
                (resolve-node-clip node.parent)
                nil))
          (local resolved
            (if (and node node.get-clip-matrix)
                (node:get-clip-matrix inherited)
                inherited))
          (set (. clip-cache node) resolved)
          resolved)))

  (fn emit-node [node]
    (local clip-matrix (resolve-node-clip node))
    (when (and node node.emit-quads)
      (node:emit-quads quad-batcher clip-matrix))
    (when (and node node.emit-ssbo)
      (node:emit-ssbo text-batcher clip-matrix)))

  (fn set-size [_self w h]
    (set viewport-width (or w viewport-width))
    (set viewport-height (or h viewport-height))
    (update-projection))

  (fn set-root-transform [_self x y z rotation]
    (root:set-local-position (or x root.local-x)
                             (or y root.local-y)
                             (or z root.local-z)
                             (or rotation root.local-rotation)))

  (fn prerender [_self]
    (local submit-start (os.clock))
    (apply-scenario)
    (NextLayout.run-frame root
                          (or renderer-options.root-width 1.8)
                          (or renderer-options.root-height 1.64)
                          0)
    (quad-batcher:begin-frame)
    (text-batcher:begin-frame)
    (set clip-cache {})
    (local traversal-start (os.clock))
    (if NextLayout.collect-submit-nodes
        (each [_ node (ipairs (NextLayout.collect-submit-nodes root))]
          (emit-node node))
        (emit-subtree root nil false))
    (local traversal-seconds (- (os.clock) traversal-start))
    (quad-batcher:end-frame)
    (text-batcher:end-frame)
    (local quad-stats (quad-batcher:get-last-stats))
    (local text-stats (text-batcher:get-last-stats))
    (quad-renderer:render (quad-batcher:get-vector)
                          projection
                          view
                          lighting-view-state
                          (quad-batcher:get-batches)
                          (quad-batcher:get-clip-vector)
                          (quad-batcher:get-clip-group-vector)
                          true)
    (gl.glDisable gl.GL_DEPTH_TEST)
    (text-batcher:render text-renderer projection view)
    (gl.glEnable gl.GL_DEPTH_TEST)
    (local submit-seconds (- (os.clock) submit-start))
    (local quad-upload-seconds (or (quad-renderer:get-last-upload-seconds) 0))
    (local text-upload-seconds (or (text-renderer:get-last-upload-seconds) 0))
    (local quad-draw-seconds (or (quad-renderer:get-last-draw-seconds) 0))
    (local text-draw-seconds (or (text-renderer:get-last-draw-seconds) 0))
    (local quad-gpu-upload-seconds (or (quad-renderer:get-last-gpu-upload-seconds) 0))
    (local text-gpu-upload-seconds (or (text-renderer:get-last-gpu-upload-seconds) 0))
    (local quad-gpu-draw-seconds (or (quad-renderer:get-last-gpu-draw-seconds) 0))
    (local text-gpu-draw-seconds (or (text-renderer:get-last-gpu-draw-seconds) 0))
    (set last-submit-stats {:traversal-seconds traversal-seconds
                            :submit-seconds submit-seconds
                            :write-seconds (+ quad-stats.write-seconds text-stats.write-seconds)
                            :write-count (+ quad-stats.write-count text-stats.write-count)
                            :upsert-count (+ quad-stats.upsert-count text-stats.upsert-count)
                            :quad-write-count quad-stats.write-count
                            :quad-upsert-count quad-stats.upsert-count
                            :text-write-count text-stats.write-count
                            :text-upsert-count text-stats.upsert-count
                            :gl-upload-seconds (+ quad-upload-seconds text-upload-seconds)
                            :draw-cpu-seconds (+ quad-draw-seconds text-draw-seconds)
                            :gpu-upload-seconds (+ quad-gpu-upload-seconds text-gpu-upload-seconds)
                            :gpu-draw-seconds (+ quad-gpu-draw-seconds text-gpu-draw-seconds)}))

  (fn drop [_self]
    (text-batcher:clear)
    (quad-batcher:drop)
    (when ui.router
      (ui.router:drop))
    (when (and ui.focus-context ui.focus-context.manager)
      (ui.focus-context.manager:drop)))

  (update-projection)

  {:set-size set-size
   :set-root-transform set-root-transform
   :prerender prerender
   :get-last-submit-stats (fn [_self] last-submit-stats)
   :drop drop})

NextAppRenderers
