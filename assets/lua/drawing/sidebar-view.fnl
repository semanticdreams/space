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
(local {: adjust} (require :widget-theme-utils))

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

(fn action-button [label opts]
  (local options (or opts {}))
  (local button-opts {:text label
                      :padding [0.4 0.25]
                      :focusable? false
                      :enabled? (if (= options.enabled? nil) true options.enabled?)
                      :on-click options.on-click})
  (when (not (= options.variant nil))
    (set button-opts.variant options.variant))
  (when (not (= options.background-color nil))
    (set button-opts.background-color options.background-color))
  (when (not (= options.hover-background-color nil))
    (set button-opts.hover-background-color options.hover-background-color))
  (when (not (= options.pressed-background-color nil))
    (set button-opts.pressed-background-color options.pressed-background-color))
  (when (not (= options.foreground-color nil))
    (set button-opts.foreground-color options.foreground-color))
  (Button button-opts))

(fn panel-shell [content-builder background-color opts]
  (local options (or opts {}))
  (local body-padding
    (if (= options.padding false)
        nil
        (or options.padding [0.45 0.45])))
  (Stack {:children [(fn [_ctx] ((Rectangle {:color background-color}) _ctx))
                     (if body-padding
                         (Padding {:edge-insets body-padding
                                   :child content-builder})
                         content-builder)]}))

(fn tool-button [label active? on-click opts]
  (assert on-click "tool-button requires on-click")
  (local options (or opts {}))
  (local button-opts {:padding [0.4 0.25]
                      :focusable? false
                      :text label
                      :enabled? (if (= options.enabled? nil) true options.enabled?)
                      :on-click (fn [button event]
                                  (when (and (not active?)
                                             (not (= button.enabled? false)))
                                    (on-click button event)))
                      :variant (if active? :primary :secondary)})
  (Button button-opts))

(fn feature-button [icon name label active? on-click]
  (assert on-click "feature-button requires on-click")
  (Button {:padding [0.4 0.25]
           :focusable? false
           :icon icon
           :icon-style {:scale 3.2}
           :name name
           :focus-name label
           :on-click (fn [button event]
                       (when (not active?)
                         (on-click button event)))
           :variant (if active? :primary :secondary)}))

(fn state-button [label active? on-click]
  (action-button label {:on-click on-click
                        :variant (if active? :primary :secondary)}))

(fn panel-background [theme kind]
  (local card-theme (and theme theme.card))
  (local base (or (and card-theme card-theme.background)
                  (if (= kind :rail)
                      (glm.vec4 0.08 0.1 0.14 0.96)
                      (glm.vec4 0.12 0.14 0.18 0.96))))
  (if (= kind :rail)
      (adjust base (if (and theme (= theme.name :light)) -0.06 -0.04))
      (adjust base (if (and theme (= theme.name :light)) -0.03 0.0))))

(fn DrawingSidebarView [opts]
  (local options (or opts {}))
  (local controller (assert options.controller "DrawingSidebarView requires :controller"))

  (fn build [ctx]
    (var root-layout nil)
    (var content-entity nil)
    (var pending-rebuild? true)
    (var sidebar-state-token nil)
    (var changed-handler nil)
    (var shell-changed-handler nil)
    (var rename-layer-id nil)
    (var rename-layer-name nil)
    (var rename-buffer "")
    (local theme (and ctx ctx.theme))

    (fn color-token [value]
      (if value
          (.. (tostring (or (. value 1) value.x 0))
              ","
              (tostring (or (. value 2) value.y 0))
              ","
              (tostring (or (. value 3) value.z 0))
              ","
              (tostring (or (. value 4) value.w 0)))
          ""))

    (fn bool-token [value]
      (if value "1" "0"))

    (fn layer-list-token []
      (local parts [])
      (each [_ layer (ipairs (or controller.state.document.layers []))]
        (table.insert parts
                      (.. layer.kind
                          ":"
                          layer.id
                          ":"
                          layer.name)))
      (table.concat parts "|"))

    (fn defaults-token [defaults]
      (.. (color-token defaults.stroke_color)
          "|"
          (color-token defaults.fill_color)
          "|"
          (tostring defaults.thickness)
          "|"
          (tostring defaults.opacity)
          "|"
          (bool-token defaults.fill_enabled)))

    (fn current-sidebar-state-token []
      (local active-layer (controller:active-layer))
      (local defaults (controller:current-defaults))
      (local raster-layer? (= (and active-layer active-layer.kind) "raster"))
      (local move-enabled?
        (and raster-layer?
             controller.can-activate-tool?
             (controller:can-activate-tool? "move")))
      (table.concat [(layer-list-token)
                     (or (and active-layer active-layer.id) "")
                     (or (and active-layer active-layer.kind) "")
                     (or (and active-layer active-layer.name) "")
                     (or (controller:active-tool) "")
                     (defaults-token defaults)
                     (bool-token (controller:can-undo?))
                     (bool-token (controller:can-redo?))
                     (bool-token (> (controller:selection-count) 0))
                     (bool-token move-enabled?)
                     (bool-token (and controller.can-add-raster-layer?
                                      (controller:can-add-raster-layer?)))]
                    "\31"))

    (fn drop-content! []
      (when (and content-entity content-entity.drop)
        (content-entity:drop))
      (set content-entity nil)
      (when root-layout
        (root-layout:clear-children)))

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

    (fn validated-rename-buffer [layer]
      (if (not layer)
          nil
          (do
            (local (ok next-name) (pcall DrawingDocument.validate-layer-name
                                         rename-buffer
                                         "DrawingSidebarView rename-buffer"))
            (if (and ok (not (= next-name layer.name)))
                next-name
                nil))))

    (fn apply-rename! []
      (local layer (controller:active-layer))
      (local next-name (validated-rename-buffer layer))
      (if next-name
          (if (controller:rename-active-layer next-name)
              (do
                (set rename-layer-name next-name)
                (set rename-buffer next-name)
                true)
              false)
          false))

    (fn build-layer-row [layer]
      (local active? (= layer.id controller.state.ui.active_layer_id))
      (local layer-label
        (.. (if (= layer.kind "raster") "[R] " "[V] ")
            (if active?
                (.. "* " layer.name)
                layer.name)))
      (Flex {:axis 1
             :xspacing 0.25
             :yalign :center
             :children [(FlexChild (fn [child-ctx]
                                     ((tool-button layer-label
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
                                                           :variant :secondary})
                                      child-ctx))
                                  0)
                        (FlexChild (fn [child-ctx]
                                     ((action-button "dn" {:on-click (fn [_button _event]
                                                                       (controller:set-active-layer layer.id)
                                                                       (controller:move-active-layer 1))
                                                           :enabled? (< (or (DrawingDocument.layer-index controller.state.document layer.id) 1)
                                                                        (length controller.state.document.layers))
                                                           :variant :secondary})
                                      child-ctx))
                                  0)
                        (FlexChild (fn [child-ctx]
                                     ((action-button "x" {:on-click (fn [_button _event]
                                                                      (controller:set-active-layer layer.id)
                                                                      (controller:delete-active-layer))
                                                          :enabled? (> (controller:layer-count) 1)
                                                          :variant :danger})
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
                  :on-click (fn [_button _event]
                              (when (not selected?)
                                (local changes {})
                                (set (. changes key) value)
                                (controller:set-defaults! changes)))}))

    (fn build-defaults-section []
      (local defaults (controller:current-defaults))
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
                                                        (do
                                                          (local label (. entry 1))
                                                          (local color (. entry 2))
                                                          (local current defaults.stroke_color)
                                                          (local selected? (color-array= color current))
                                                          (FlexChild (fn [row-ctx] ((build-color-button label color :stroke_color selected?) row-ctx)) 1)))})
                             inner-ctx))
                          0)
                        (FlexChild
                          (fn [inner-ctx]
                            ((Flex {:axis 1
                                    :xspacing 0.2
                                    :children (icollect [_ entry (ipairs fill-options)]
                                                        (do
                                                          (local label (. entry 1))
                                                          (local color (. entry 2))
                                                          (local current defaults.fill_color)
                                                          (local selected? (color-array= color current))
                                                          (FlexChild (fn [row-ctx] ((build-color-button label color :fill_color selected?) row-ctx)) 1)))})
                             inner-ctx))
                          0)
                        (FlexChild
                          (fn [inner-ctx]
                            ((Flex {:axis 1
                                    :xspacing 0.2
                                    :children (icollect [_ entry (ipairs thickness-options)]
                                                        (do
                                                          (local label (. entry 1))
                                                          (local thickness (. entry 2))
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
                                                        (do
                                                          (local label (. entry 1))
                                                          (local opacity (. entry 2))
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
                          0)
                        (FlexChild
                          (fn [inner-ctx]
                            ((action-button "Redo" {:on-click (fn [_button _event]
                                                                (controller:on-redo))
                                                    :enabled? (controller:can-redo?)})
                             inner-ctx))
                          0)
                        (FlexChild
                          (fn [inner-ctx]
                            ((action-button "Delete" {:on-click (fn [_button _event]
                                                                  (controller:on-delete-selection))
                                                      :enabled? (> (controller:selection-count) 0)
                                                      :variant :danger})
                             inner-ctx))
                          0)]}))

    (fn build-layer-rename-section [layer]
      (fn [section-ctx]
        (var save-button nil)

        (fn sync-save-button! []
          (when save-button
            (save-button:set-enabled (not (= (validated-rename-buffer layer) nil)))))

        ((Flex {:axis 2
                :spacing 0.25
                :children [(title-child "Layer Name")
                           (FlexChild
                             (fn [inner-ctx]
                               ((Input {:text rename-buffer
                                        :placeholder "Layer name"
                                        :min-width 12.0
                                        :on-change (fn [_input text]
                                                     (set rename-buffer text)
                                                     (sync-save-button!))})
                                inner-ctx))
                             0)
                           (FlexChild
                             (fn [inner-ctx]
                               (set save-button
                                    ((action-button "Save" {:on-click (fn [_button _event]
                                                                        (when (apply-rename!)
                                                                          (sync-save-button!)))
                                                            :enabled? (not (= (validated-rename-buffer layer) nil))
                                                            :variant :success})
                                     inner-ctx))
                               save-button)
                             0)]})
         section-ctx)))

    (fn build-tools-section []
      (local active-tool (controller:active-tool))
      (local active-layer (controller:active-layer))
      (local raster-layer? (= (and active-layer active-layer.kind) "raster"))
      (local can-move?
        (and raster-layer?
             controller.can-activate-tool?
             (controller:can-activate-tool? "move")))
      (local tools
        (if raster-layer?
            [{:label "Marquee" :tool "marquee"}
             {:label "Move" :tool "move" :enabled? can-move?}
             {:label "Dropper" :tool "eyedropper"}
             {:label "Fill" :tool "fill"}
             {:label "Rect" :tool "rectangle"}
             {:label "Ellipse" :tool "ellipse"}
             {:label "Line" :tool "line"}
             {:label "Pen" :tool "pen"}
             {:label "Brush" :tool "brush"}
             {:label "Marker" :tool "marker"}
             {:label "Eraser" :tool "eraser"}]
            [{:label "Select" :tool "select"}
             {:label "Rect" :tool "rectangle"}
             {:label "Ellipse" :tool "ellipse"}
             {:label "Line" :tool "line"}
             {:label "Pen" :tool "pen"}
             {:label "Brush" :tool "brush"}
             {:label "Marker" :tool "marker"}
             {:label "Eraser" :tool "eraser"}]))
      (Flex {:axis 2
             :spacing 0.25
             :children (icollect [_ entry (ipairs tools)]
                                 (do
                                   (local label entry.label)
                                   (local tool entry.tool)
                                   (FlexChild
                                     (fn [inner-ctx]
                                       ((tool-button label
                                                     (= active-tool tool)
                                                     (fn [_button _event]
                                                       (controller:set-active-tool tool))
                                                     {:enabled? (if (= entry.enabled? nil)
                                                                    true
                                                                    entry.enabled?)})
                                        inner-ctx))
                                     0)))}))

    (fn build-drawing-panel []
      (local active-layer (sync-rename-buffer!))
      (local layers controller.state.document.layers)
      (local can-add-raster?
        (if controller.can-add-raster-layer?
            (controller:can-add-raster-layer?)
            false))
      (panel-shell
        (fn [inner-ctx]
          ((Flex {:axis 2
                  :spacing 0.4
                  :children [(title-child "Layers")
                             (FlexChild (fn [child-ctx] ((build-layer-rename-section active-layer) child-ctx)) 0)
                             (FlexChild
                               (fn [child-ctx]
                                 ((Flex {:axis 1
                                         :xspacing 0.2
                                         :children [(FlexChild
                                                      (fn [row-ctx]
                                                        ((action-button "+ Vector"
                                                                        {:on-click (fn [_button _event]
                                                                                      (controller:add-layer "vector"))
                                                                         :variant :success})
                                                         row-ctx))
                                                      1)
                                                    (FlexChild
                                                      (fn [row-ctx]
                                                        ((action-button "+ Raster"
                                                                        {:on-click (fn [_button _event]
                                                                                      (controller:add-layer "raster"))
                                                                         :enabled? can-add-raster?
                                                                         :variant :primary})
                                                         row-ctx))
                                                      1)]})
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
        (panel-background theme :panel)))

    (fn build-feature-rail []
      (panel-shell
        (fn [inner-ctx]
          ((Flex {:axis 2
                  :xalign :stretch
                  :spacing 0
                  :children [(FlexChild
                               (fn [child-ctx]
                                 ((feature-button "account_tree"
                                                  "graph-canvas-feature"
                                                  "Graph"
                                                  (= app.active-canvas-feature "graph")
                                                  (fn [_button _event]
                                                    (when app.set-active-canvas-feature
                                                      (app.set-active-canvas-feature "graph"))))
                                  child-ctx))
                               0)
                             (FlexChild
                              (fn [child-ctx]
                                ((feature-button "draw"
                                                 "drawing-canvas-feature"
                                                 "Draw"
                                                 (= app.active-canvas-feature "drawing")
                                                 (fn [_button _event]
                                                   (when app.set-active-canvas-feature
                                                     (app.set-active-canvas-feature "drawing"))))
                                  child-ctx))
                               0)]})
           inner-ctx))
        (panel-background theme :rail)
        {:padding false}))

    (fn build-content []
      (local show-dock?
        (and app.canvas
             (= app.active-interaction-surface :canvas)
             (= app.canvas-visible? true)))
      (if show-dock?
          (do
            (local builders [(FlexChild (build-feature-rail) 0)])
            (when (= app.active-canvas-feature "drawing")
              (table.insert builders (FlexChild (build-drawing-panel) 0)))
            ((Flex {:axis 1
                    :spacing 0
                    :yalign :stretch
                    :children builders})
             ctx))
          nil))

    (fn rebuild-children! []
      (drop-content!)
      (set content-entity (build-content))
      (set sidebar-state-token (current-sidebar-state-token))
      (when content-entity
        (root-layout:add-child content-entity.layout)))

    (fn request-rebuild! []
      (set pending-rebuild? true)
      true)

    (fn controller-change-rebuild? [payload]
      (local reason (and payload payload.reason))
      (if (= reason "gesture")
          false
          (do
            (local next-token (current-sidebar-state-token))
            (if (= next-token sidebar-state-token)
                false
                (do
                  (set sidebar-state-token next-token)
                  true)))))

    (fn measurer [self]
      (if content-entity
          (do
            (content-entity.layout:measurer)
            (set self.measure content-entity.layout.measure))
          (set self.measure (glm.vec3 0 0 0))))

    (fn layouter [self]
      (local allocated-size
        (glm.vec3 (math.max self.measure.x (or self.size.x 0))
                  (math.max self.measure.y (or self.size.y 0))
                  (math.max self.measure.z (or self.size.z 0))))
      (set self.size allocated-size)
      (when content-entity
        (set content-entity.layout.position self.position)
        (set content-entity.layout.size allocated-size)
        (set content-entity.layout.rotation self.rotation)
        (set content-entity.layout.clip-region self.clip-region)
        (set content-entity.layout.depth-offset-index self.depth-offset-index)
        (content-entity.layout:layouter)))

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
             (drop-content!)
             (root-layout:drop))})

  build)

DrawingSidebarView
