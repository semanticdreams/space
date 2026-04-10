(local glm (require :glm))
(local {: Layout} (require :layout))
(local DrawingDocument (require :drawing/document))
(local Rectangle (require :rectangle))
(local Padding (require :padding))
(local Stack (require :stack))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Input (require :input))
(local Text (require :text))

(fn section-title [label]
  (Text {:text label}))

(fn title-child [label]
  (FlexChild (fn [inner-ctx]
               ((section-title label) inner-ctx))
             0))

(fn color-array= [a b]
  (and a b
       (= (or (. a 1) a.x 0) (or (. b 1) b.x 0))
       (= (or (. a 2) a.y 0) (or (. b 2) b.y 0))
       (= (or (. a 3) a.z 0) (or (. b 3) b.z 0))
       (= (or (. a 4) a.w 0) (or (. b 4) b.w 0))))

(fn trim-name [value]
  (if (not (= (type value) :string))
      ""
      (let [trimmed (string.match value "^%s*(.-)%s*$")]
        (or trimmed ""))))

(fn action-button [label opts]
  (local options (or opts {}))
  (Button {:text label
           :padding [0.4 0.25]
           :focusable? false
           :background-color (or options.background-color (glm.vec4 0.2 0.22 0.28 0.95))
           :hover-background-color (or options.hover-background-color (glm.vec4 0.24 0.27 0.34 0.98))
           :pressed-background-color (or options.pressed-background-color (glm.vec4 0.16 0.18 0.24 0.98))
           :foreground-color (or options.foreground-color (glm.vec4 0.95 0.95 0.97 1.0))
           :enabled? (if (= options.enabled? nil) true options.enabled?)
           :on-click options.on-click}))

(fn panel-shell [content-builder background-color]
  (Stack {:children [(fn [_ctx] ((Rectangle {:color background-color}) _ctx))
                     (Padding {:edge-insets [0.45 0.45]
                               :child content-builder})]}))

(fn tool-button [label active? on-click]
  (action-button label {:on-click on-click
                        :enabled? (not active?)
                        :background-color (if active?
                                              (glm.vec4 0.49 0.28 0.08 0.96)
                                              (glm.vec4 0.2 0.22 0.28 0.95))
                        :hover-background-color (if active?
                                                    (glm.vec4 0.49 0.28 0.08 0.96)
                                                    (glm.vec4 0.24 0.27 0.34 0.98))
                        :pressed-background-color (if active?
                                                      (glm.vec4 0.49 0.28 0.08 0.96)
                                                      (glm.vec4 0.16 0.18 0.24 0.98))}))

(fn state-button [label active? on-click]
  (action-button label {:on-click on-click
                        :background-color (if active?
                                              (glm.vec4 0.49 0.28 0.08 0.96)
                                              (glm.vec4 0.2 0.22 0.28 0.95))
                        :hover-background-color (if active?
                                                    (glm.vec4 0.54 0.31 0.09 0.98)
                                                    (glm.vec4 0.24 0.27 0.34 0.98))
                        :pressed-background-color (if active?
                                                      (glm.vec4 0.43 0.24 0.07 0.98)
                                                      (glm.vec4 0.16 0.18 0.24 0.98))}))

(fn DrawingSidebarView [opts]
  (local options (or opts {}))
  (local controller (assert options.controller "DrawingSidebarView requires :controller"))
  (local rail-width (or options.rail-width 6.4))
  (local panel-width (or options.panel-width 22.0))

  (fn build [ctx]
    (var root-layout nil)
    (local children {})
    (var child-entities [])
    (var pending-rebuild? true)
    (var changed-handler nil)
    (var shell-changed-handler nil)
    (var rename-layer-id nil)
    (var rename-layer-name nil)
    (var rename-buffer "")

    (fn drop-children []
      (each [_ entity (ipairs child-entities)]
        (when (and entity entity.drop)
          (entity:drop)))
      (set child-entities [])
      (when root-layout
        (root-layout:clear-children)))

    (fn remember-child [entity]
      (table.insert child-entities entity)
      entity)

    (fn sync-rename-buffer! []
      (local layer (controller:active-layer))
      (local layer-id (and layer layer.id))
      (local layer-name (or (and layer layer.name) ""))
      (when (or (not (= rename-layer-id layer-id))
                (not (= rename-layer-name layer-name)))
        (set rename-layer-id layer-id)
        (set rename-layer-name layer-name)
        (set rename-buffer layer-name))
      layer)

    (fn apply-rename! []
      (local next-name (trim-name rename-buffer))
          (if (= next-name "")
              false
              (if (controller:rename-active-layer next-name)
                  (do
                    (set rename-layer-name next-name)
                    (set rename-buffer next-name)
                    true)
                  false)))

    (fn build-layer-row [layer]
      (local active? (= layer.id controller.state.ui.active_layer_id))
      (Flex {:axis 1
             :xspacing 0.25
             :yalign :center
             :children [(FlexChild (fn [child-ctx]
                                     ((tool-button (if active?
                                                       (.. "* " layer.name)
                                                       layer.name)
                                                   active?
                                                   (fn [_button _event]
                                                     (controller:set-active-layer layer.id)))
                                      child-ctx))
                                  1)
                        (FlexChild (fn [child-ctx]
                                     ((action-button "up" {:on-click (fn [_button _event]
                                                                       (controller:set-active-layer layer.id)
                                                                       (controller:move-active-layer -1))
                                                           :enabled? (> (or (DrawingDocument.layer-index controller.state.document layer.id) 1) 1)
                                                           :background-color (glm.vec4 0.18 0.2 0.24 0.95)})
                                      child-ctx))
                                  0)
                        (FlexChild (fn [child-ctx]
                                     ((action-button "dn" {:on-click (fn [_button _event]
                                                                       (controller:set-active-layer layer.id)
                                                                       (controller:move-active-layer 1))
                                                           :enabled? (< (or (DrawingDocument.layer-index controller.state.document layer.id) 1)
                                                                        (length controller.state.document.layers))
                                                           :background-color (glm.vec4 0.18 0.2 0.24 0.95)})
                                      child-ctx))
                                  0)
                        (FlexChild (fn [child-ctx]
                                     ((action-button "x" {:on-click (fn [_button _event]
                                                                      (controller:set-active-layer layer.id)
                                                                      (controller:delete-active-layer))
                                                          :enabled? (> (controller:layer-count) 1)
                                                          :background-color (glm.vec4 0.34 0.16 0.16 0.95)
                                                          :hover-background-color (glm.vec4 0.42 0.19 0.19 0.98)
                                                          :pressed-background-color (glm.vec4 0.28 0.13 0.13 0.98)})
                                      child-ctx))
                                  0)]}))

    (fn build-color-button [label value key selected?]
      (action-button label
                     {:background-color (glm.vec4 (or (. value 1) 0.4)
                                                  (or (. value 2) 0.4)
                                                  (or (. value 3) 0.4)
                                                  0.95)
                      :hover-background-color (glm.vec4 (math.min 1.0 (+ (or (. value 1) 0.4) 0.08))
                                                        (math.min 1.0 (+ (or (. value 2) 0.4) 0.08))
                                                        (math.min 1.0 (+ (or (. value 3) 0.4) 0.08))
                                                        0.98)
                      :foreground-color (glm.vec4 0.08 0.08 0.1 1.0)
                      :enabled? (not selected?)
                      :on-click (fn [_button _event]
                                  (local changes {})
                                  (set (. changes key) value)
                                  (controller:set-defaults! changes))}))

    (fn build-defaults-section []
      (local defaults controller.state.ui.defaults)
      (local stroke-options [["W" [0.96 0.96 0.98 1.0]]
                             ["R" [0.9 0.28 0.24 1.0]]
                             ["Y" [0.95 0.8 0.24 1.0]]
                             ["G" [0.34 0.73 0.4 1.0]]
                             ["B" [0.33 0.6 0.96 1.0]]])
      (local fill-options [["Off" [0 0 0 0]]
                           ["Blue" [0.33 0.6 0.96 0.22]]
                           ["Gold" [0.95 0.8 0.24 0.22]]
                           ["Mint" [0.34 0.73 0.4 0.22]]])
      (local thickness-options [["1" 1.0] ["3" 3.0] ["6" 6.0]])
      (local opacity-options [["100" 1.0] ["65" 0.65] ["35" 0.35]])
      (Flex {:axis 2
             :spacing 0.25
             :children [(title-child "Defaults")
                        (FlexChild
                          (fn [inner-ctx]
                            ((Flex {:axis 1
                                    :xspacing 0.2
                                    :children (icollect [_ entry (ipairs stroke-options)]
                                                        (let [label (. entry 1)
                                                              color (. entry 2)
                                                              current defaults.stroke_color
                                                              selected? (color-array= color current)]
                                                          (FlexChild (fn [row-ctx] ((build-color-button label color :stroke_color selected?) row-ctx)) 1)))})
                             inner-ctx))
                          0)
                        (FlexChild
                          (fn [inner-ctx]
                            ((Flex {:axis 1
                                    :xspacing 0.2
                                    :children (icollect [_ entry (ipairs fill-options)]
                                                        (let [label (. entry 1)
                                                              color (. entry 2)
                                                              current defaults.fill_color
                                                              selected? (color-array= color current)]
                                                          (FlexChild (fn [row-ctx] ((build-color-button label color :fill_color selected?) row-ctx)) 1)))})
                             inner-ctx))
                          0)
                        (FlexChild
                          (fn [inner-ctx]
                            ((Flex {:axis 1
                                    :xspacing 0.2
                                    :children (icollect [_ entry (ipairs thickness-options)]
                                                        (let [label (. entry 1)
                                                              thickness (. entry 2)]
                                                          (FlexChild
                                                            (fn [row-ctx]
                                                              ((tool-button label
                                                                            (= defaults.thickness thickness)
                                                                            (fn [_button _event]
                                                                              (controller:set-defaults! {:thickness thickness})))
                                                               row-ctx))
                                                            1)))})
                             inner-ctx))
                          0)
                        (FlexChild
                          (fn [inner-ctx]
                            ((Flex {:axis 1
                                    :xspacing 0.2
                                    :children (icollect [_ entry (ipairs opacity-options)]
                                                        (let [label (. entry 1)
                                                              opacity (. entry 2)]
                                                          (FlexChild
                                                            (fn [row-ctx]
                                                              ((tool-button label
                                                                            (= defaults.opacity opacity)
                                                                            (fn [_button _event]
                                                                              (controller:set-defaults! {:opacity opacity})))
                                                               row-ctx))
                                                            1)))})
                             inner-ctx))
                          0)
                        (FlexChild
                          (fn [inner-ctx]
                            ((state-button (if defaults.fill_enabled "Fill On" "Fill Off")
                                           defaults.fill_enabled
                                           (fn [_button _event]
                                             (controller:set-defaults! {:fill_enabled (not defaults.fill_enabled)})))
                             inner-ctx))
                          0)]}))

    (fn build-edit-section []
      (Flex {:axis 1
             :xspacing 0.25
             :children [(FlexChild
                          (fn [inner-ctx]
                            ((action-button "Undo" {:on-click (fn [_button _event]
                                                                (controller:on-undo))
                                                    :enabled? (controller:can-undo?)})
                             inner-ctx))
                          1)
                        (FlexChild
                          (fn [inner-ctx]
                            ((action-button "Redo" {:on-click (fn [_button _event]
                                                                (controller:on-redo))
                                                    :enabled? (controller:can-redo?)})
                             inner-ctx))
                          1)
                        (FlexChild
                          (fn [inner-ctx]
                            ((action-button "Delete" {:on-click (fn [_button _event]
                                                                  (controller:on-delete-selection))
                                                      :enabled? (> (controller:selection-count) 0)
                                                      :background-color (glm.vec4 0.34 0.16 0.16 0.95)
                                                      :hover-background-color (glm.vec4 0.42 0.19 0.19 0.98)
                                                      :pressed-background-color (glm.vec4 0.28 0.13 0.13 0.98)})
                             inner-ctx))
                          1)]}))

    (fn build-layer-rename-section [layer]
      (Flex {:axis 2
             :spacing 0.25
             :children [(title-child "Layer Name")
                        (FlexChild
                          (fn [inner-ctx]
                            ((Input {:text rename-buffer
                                     :placeholder "Layer name"
                                     :min-width 12.0
                                     :on-change (fn [_input text]
                                                  (set rename-buffer text))})
                             inner-ctx))
                          0)
                        (FlexChild
                          (fn [inner-ctx]
                            ((action-button "Save" {:on-click (fn [_button _event]
                                                                (apply-rename!))
                                                    :enabled? (and layer
                                                                   (> (# (trim-name rename-buffer)) 0)
                                                                   (not (= (trim-name rename-buffer) layer.name)))
                                                    :background-color (glm.vec4 0.16 0.32 0.24 0.95)})
                             inner-ctx))
                          0)]}))

    (fn build-tools-section []
      (local active-tool controller.state.ui.active_tool)
      (local tools [["Select" "select"]
                    ["Rect" "rectangle"]
                    ["Ellipse" "ellipse"]
                    ["Line" "line"]
                    ["Pen" "pen"]
                    ["Brush" "brush"]
                    ["Marker" "marker"]
                    ["Eraser" "eraser"]])
      (Flex {:axis 2
             :spacing 0.25
             :children (icollect [_ entry (ipairs tools)]
                                 (let [label (. entry 1)
                                       tool (. entry 2)]
                                   (FlexChild
                                     (fn [inner-ctx]
                                       ((tool-button label
                                                     (= active-tool tool)
                                                     (fn [_button _event]
                                                       (controller:set-active-tool tool)))
                                        inner-ctx))
                                     0)))}))

    (fn build-drawing-panel []
      (local active-layer (sync-rename-buffer!))
      (local layers controller.state.document.layers)
      (panel-shell
        (fn [inner-ctx]
          ((Flex {:axis 2
                  :spacing 0.4
                  :children [(title-child "Layers")
                             (FlexChild (fn [child-ctx] ((build-layer-rename-section active-layer) child-ctx)) 0)
                             (FlexChild
                               (fn [child-ctx]
                                 ((action-button "+ Layer" {:on-click (fn [_button _event]
                                                                        (controller:add-layer))
                                                            :background-color (glm.vec4 0.16 0.32 0.24 0.95)})
                                  child-ctx))
                               0)
                             (FlexChild
                               (fn [child-ctx]
                                 ((Flex {:axis 2
                                         :spacing 0.18
                                         :children (icollect [_ layer (ipairs layers)]
                                                             (FlexChild (fn [row-ctx] ((build-layer-row layer) row-ctx)) 0))})
                                  child-ctx))
                               0)
                             (title-child "Edit")
                             (FlexChild (fn [child-ctx] ((build-edit-section) child-ctx)) 0)
                             (title-child "Tools")
                             (FlexChild (fn [child-ctx] ((build-tools-section) child-ctx)) 0)
                             (FlexChild (fn [child-ctx] ((build-defaults-section) child-ctx)) 0)]})
           inner-ctx))
        (glm.vec4 0.12 0.14 0.18 0.96)))

    (fn build-feature-rail []
      (panel-shell
        (fn [inner-ctx]
          ((Flex {:axis 2
                  :spacing 0.25
                  :children [(FlexChild
                               (fn [child-ctx]
                                 ((tool-button "Graph"
                                               (= app.active-canvas-feature "graph")
                                               (fn [_button _event]
                                                 (when app.set-active-canvas-feature
                                                   (app.set-active-canvas-feature "graph"))))
                                  child-ctx))
                               0)
                             (FlexChild
                               (fn [child-ctx]
                                 ((tool-button "Draw"
                                               (= app.active-canvas-feature "drawing")
                                               (fn [_button _event]
                                                 (when app.set-active-canvas-feature
                                                   (app.set-active-canvas-feature "drawing"))))
                                  child-ctx))
                               0)]})
           inner-ctx))
        (glm.vec4 0.08 0.1 0.14 0.96)))

    (fn rebuild-children! []
      (drop-children)
      (local show-dock?
        (and app.canvas
             (= app.active-interaction-surface :canvas)
             (= app.canvas-visible? true)))
      (if show-dock?
          (do
            (set children.rail (remember-child ((build-feature-rail) ctx)))
            (root-layout:add-child children.rail.layout)
            (when (= app.active-canvas-feature "drawing")
              (set children.panel (remember-child ((build-drawing-panel) ctx)))
              (root-layout:add-child children.panel.layout)))
          (do
            (set children.rail nil)
            (set children.panel nil))))

    (fn request-rebuild! []
      (set pending-rebuild? true)
      true)

    (fn controller-change-rebuild? [payload]
      (local reason (and payload payload.reason))
      (not (= reason "gesture")))

    (fn measurer [self]
      (var width 0)
      (var height 0)
      (if children.rail
          (do
            (children.rail.layout:measurer)
            (set width (+ width rail-width))
            (when children.panel
              (children.panel.layout:measurer)
              (set width (+ width 0.35 panel-width)))
            (set height (math.max (. children.rail.layout.measure 2)
                                  (if children.panel
                                      (. children.panel.layout.measure 2)
                                      0))))
          (set height 0))
      (set self.measure (glm.vec3 width height 0)))

    (fn layouter [self]
      (set self.size self.measure)
      (local base-position self.position)
      (local height self.size.y)
      (when children.rail
        (set children.rail.layout.position base-position)
        (set children.rail.layout.size (glm.vec3 rail-width height 0))
        (set children.rail.layout.rotation self.rotation)
        (set children.rail.layout.clip-region self.clip-region)
        (set children.rail.layout.depth-offset-index (+ self.depth-offset-index 32))
        (children.rail.layout:layouter))
      (when children.panel
        (set children.panel.layout.position (+ base-position (glm.vec3 (+ rail-width 0.35) 0 0)))
        (set children.panel.layout.size (glm.vec3 panel-width height 0))
        (set children.panel.layout.rotation self.rotation)
        (set children.panel.layout.clip-region self.clip-region)
        (set children.panel.layout.depth-offset-index (+ self.depth-offset-index 33))
        (children.panel.layout:layouter)))

    (set root-layout
         (Layout {:name "drawing-sidebar"
                  :measurer measurer
                  :layouter layouter
                  :children []}))

    (set changed-handler
         (controller.changed:connect
           (fn [_payload]
             (when (controller-change-rebuild? _payload)
               (request-rebuild!)))))

    (when app.canvas-shell-changed
      (set shell-changed-handler
           (app.canvas-shell-changed:connect
             (fn [_payload]
               (request-rebuild!)))))

    (rebuild-children!)
    (set pending-rebuild? false)

    {:layout root-layout
     :update (fn [_self]
               (when pending-rebuild?
                 (set pending-rebuild? false)
                 (rebuild-children!)
                 (when root-layout
                   (root-layout:mark-measure-dirty))))
     :drop (fn [_self]
             (when changed-handler
               (controller.changed:disconnect changed-handler true)
               (set changed-handler nil))
             (when shell-changed-handler
               (app.canvas-shell-changed:disconnect shell-changed-handler true)
               (set shell-changed-handler nil))
             (drop-children)
             (root-layout:drop))})

  build)

DrawingSidebarView
