(local glm (require :glm))
(local gl (require :gl))

(local QuadRenderer (require :quad-renderer))
(local TextSsboRenderer (require :text-ssbo-renderer))
(local TextSsboBatcher (require :text-ssbo-batcher))

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
                   :text-scale 0.06
                   :background-color (glm.vec4 0.15 0.46 0.95 0.96)
                   :hover-background-color (glm.vec4 0.20 0.52 0.98 1)
                   :pressed-background-color (glm.vec4 0.10 0.36 0.85 1)}))
  (local inspect-button
    (ButtonWidget {:name "next-button-inspect"
                   :text "Inspect"
                   :variant :secondary
                   :focus focus-context
                   :text-scale 0.06
                   :background-color (glm.vec4 0.18 0.62 0.72 0.96)
                   :hover-background-color (glm.vec4 0.22 0.68 0.78 1)
                   :pressed-background-color (glm.vec4 0.12 0.50 0.62 1)}))
  (local ship-button
    (ButtonWidget {:name "next-button-ship"
                   :text "Ship"
                   :variant :secondary
                   :focus focus-context
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
                   :width 0.34
                   :height 0.16
                   :on-color (glm.vec4 0.22 0.80 0.56 1)
                   :off-color (glm.vec4 0.30 0.16 0.16 1)
                   :knob-color (glm.vec4 1 1 1 1)}))
  (local logs-toggle
    (ToggleWidget {:name "next-toggle-logs"
                   :text "Verbose logs"
                   :checked? false
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
  (local root-position
    (or renderer-options.root-position
        {:x -0.9 :y -0.82 :z 0 :rotation-z 0}))
  (root:set-local-position root-position.x
                           root-position.y
                           (or root-position.z 0)
                           (or root-position.rotation-z 0))
  {:root root
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
  (var projection (glm.mat4 1))
  (local view (glm.mat4 1))
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
      (if (= scenario :focused)
          (do
            (ui.run-button:on-hovered true)
            (ui.inspect-button:on-pressed true)
            (ui.search-input:set-focused true)
            (when (not (= (ui.search-input:get-text) "cpu > 0.7"))
              (ui.search-input:set-text "cpu > 0.7")))
          (if (= scenario :scrolled)
              (do
                (ui.virtual-list:set-scroll-y 6.4)
                (when (not (= (ui.search-input:get-text) "item"))
                  (ui.search-input:set-text "item"))
                (ui.search-input:set-focused false))
              nil))))

  (fn update-projection []
    (set projection (glm.mat4 1)))

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

  (fn set-root-transform [_self x y z rotation-z]
    (root:set-local-position (or x root.local-x)
                             (or y root.local-y)
                             (or z root.local-z)
                             (or rotation-z root.local-rotation-z)))

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
                          (quad-batcher:get-batches)
                          (quad-batcher:get-clip-vector)
                          (quad-batcher:get-clip-group-vector))
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
