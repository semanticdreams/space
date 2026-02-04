(local glm (require :glm))
(local {: Flex : FlexChild} (require :flex))
(local Text (require :text))
(local Button (require :button))
(local DefaultDialog (require :default-dialog))
(local Padding (require :padding))
(local Sized (require :sized))
(local TerminalWidget (require :terminal-widget))
(local VolumeControl (require :volume-control))
(local GltfMesh (require :gltf-mesh))
(local WalletView (require :wallet-view))
(local TetrisView (require :tetris-view))
(local XdgIconBrowser (require :xdg-icon-browser))
(local GraphViewControlView (require :graph-view-control-view))
(local SubAppView (require :sub-app-view))
(local {: ControlPanelLayout} (require :hud-control-panel-layout))

(local default-terminal-size (glm.vec3 60 36 0))

(fn make-terminal-dialog [opts]
  (local options (or opts {}))
  (DefaultDialog
    {:title "Terminal"
     :name "hud-terminal-dialog"
     :on-close options.on-close
     :child
     (Padding {:edge-insets [0.6 0.5]
               :child
               (Sized {:size default-terminal-size
                       :child (TerminalWidget {:name "hud-terminal"
                                               :focus-name "hud-terminal"
                                               :follow-tail? true})})})}))



(fn make-button-row [opts]
  (local options (or opts {}))
  (local on-open-demo options.on-open-demo)
  (local on-open-terminal options.on-open-terminal)
  (local on-open-wallet options.on-open-wallet)
  (local on-open-tetris options.on-open-tetris)
  (local on-open-chat options.on-open-chat)
  (local on-open-icon-browser options.on-open-icon-browser)
  (local on-open-graph-control options.on-open-graph-control)
  (local on-open-sub-app options.on-open-sub-app)
  (local scene options.scene)
  (var box-textured-element nil)
  (fn copy-list [items]
    (local result [])
    (when items
      (each [_ item (ipairs items)]
        (table.insert result item)))
    result)
  (fn rebuild-graph-view [selected]
    (when app.graph-view
      (app.graph-view:drop)
      (set app.graph-view nil))
    (when (and app.graph app.scene app.hud)
      (local GraphView (require :graph/view))
      (set app.graph-view (GraphView {:graph app.graph
                                      :ctx (and app.scene app.scene.build-context)
                                      :movables app.movables
                                      :selector app.object-selector
                                      :view-target app.hud
                                      :camera app.camera
                                      :pointer-target app.scene}))
      (when (and selected app.graph-view.selection)
        (app.graph-view.selection:set-selection selected))))
  (fn apply-theme [theme-name]
    (local previous-selected
      (and app.graph-view app.graph-view.selection
           (copy-list app.graph-view.selection.selected-nodes)))
    (local themes app.themes)
    (when (and themes themes.set-theme)
      (themes.set-theme theme-name))
    (when (and app.settings app.settings.set-value app.settings.save)
      (app.settings.set-value "ui.theme"
                              (if (= theme-name :light) "light" "dark")
                              {:save? false})
      (app.settings.save))
    (when (and app.scene app.scene.build-default)
      (app.scene:build-default))
    (when (and app.hud app.hud.build-default)
      (app.hud:build-default))
    (when (and app.renderers app.renderers.apply-theme)
      (app.renderers:apply-theme (and app.themes (app.themes.get-active-theme))))
    (rebuild-graph-view previous-selected))
  (fn toggle-theme []
    (local themes app.themes)
    (local current (and themes themes.get-active-theme-name (themes.get-active-theme-name)))
    (local next (if (= current :light) :dark :light))
    (apply-theme next))
  (fn add-box-textured []
    (when (and scene scene.add-panel-child)
      (if box-textured-element
          box-textured-element
          (do
            (local box-textured
              (GltfMesh {:path "models/BoxTextured.glb"
                         :position (glm.vec3 5 -100 5)
                         :rotation (glm.quat (math.rad -90) (glm.vec3 1 0 0))
                         :scale (glm.vec3 100)
                         :name "box-textured-model"}))
            (set box-textured-element
                 (scene:add-panel-child {:builder box-textured
                                        :position (glm.vec3 5 -100 5)
                                        :rotation (glm.quat (math.rad -90) (glm.vec3 1 0 0))
                                        :skip-cuboid true}))
            box-textured-element))))
  (local volume-button (VolumeControl.make-volume-button))
  (Flex
    {:axis 1
     :yalign :largest
     :children
     [
      (FlexChild (Button {:variant :secondary
                          :padding [0.4 0.4]
                          :text "Reset"}))
      (FlexChild (Button {:variant :tertiary
                          :padding [0.4 0.4]
                          :text "Toggle"}))
      (FlexChild (Button {:variant :primary
                          :padding [0.4 0.4]
                          :text "box-textured"
                          :on-click (fn [_button _event]
                                      (add-box-textured))}))
      (FlexChild (Button {:variant :primary
                          :padding [0.4 0.4]
                          :text "Demo"
                          :on-click (fn [_button _event]
                                      (when on-open-demo
                                        (on-open-demo)))}))
      (FlexChild (Button {:variant :primary
                          :padding [0.4 0.4]
                          :text "Chat"
                          :on-click (fn [_button _event]
                                      (when on-open-chat
                                        (on-open-chat)))}))
      (FlexChild (Button {:variant :primary
                          :padding [0.4 0.4]
                          :text "Graph"
                          :on-click (fn [_button _event]
                                      (when on-open-graph-control
                                        (on-open-graph-control)))}))
      (FlexChild (Button {:variant :primary
                          :padding [0.4 0.4]
                          :text "Tetris"
                          :on-click (fn [_button _event]
                                      (when on-open-tetris
                                        (on-open-tetris)))}))
      (FlexChild (Button {:variant :primary
                          :padding [0.4 0.4]
                          :text "sub-app-one"
                          :on-click (fn [_button _event]
                                      (when on-open-sub-app
                                        (on-open-sub-app)))}))
      (FlexChild volume-button)
      (FlexChild (Button {:text "Icons"
                          :variant :primary
                          :padding [0.4 0.4]
                          :on-click (fn [_button _event]
                                      (when on-open-icon-browser
                                        (on-open-icon-browser)))}))
      (FlexChild (Button {:icon "wallet"
                          :variant :primary
                          :padding [0.4 0.4]
                          :on-click (fn [_button _event]
                                      (when on-open-wallet
                                        (on-open-wallet)))}))
      (FlexChild (Button {:icon "contrast"
                          :variant :primary
                          :padding [0.4 0.4]
                          :on-click (fn [_button _event]
                                      (toggle-theme))}))
      (FlexChild
        (Button
          {:icon "terminal"
           :variant :primary
           :padding [0.4 0.4]
           :on-click
           (fn [_button _event]
             (when on-open-terminal
               (on-open-terminal {})))}))
      (FlexChild (Button {:icon "settings"
                          :variant :primary
                          :padding [0.4 0.4]}))
      ]}))

(fn make-icon-browser-dialog [opts]
  (local options (or opts {}))
  (DefaultDialog
    {:title "Icon Browser"
     :name "icon-browser-dialog"
     :resizeable true
     :on-close options.on-close
     :child (XdgIconBrowser.XdgIconBrowser {})}))

(fn ControlPanel [_opts]
  (fn build [ctx]
    (local hud (or ctx.pointer-target {}))
    (local button-row
      (make-button-row
        {:scene hud.scene
         :on-open-demo
         (fn []
           (local scene hud.scene)
           (when (and scene scene.add-demo-browser)
             (scene:add-demo-browser)))
         :on-open-terminal
         (fn [dialog-opts]
           (local scene hud.scene)
           (when (and scene scene.add-panel-child)
             (scene:add-panel-child {:builder (make-terminal-dialog dialog-opts)})))
         :on-open-wallet
         (fn []
           (local scene hud.scene)
           (when (and scene scene.add-panel-child)
             (scene:add-panel-child {:builder (WalletView {})})))
         :on-open-chat
         (fn []
           (when (and hud hud.add-panel-child)
             (local LlmChatView (require :llm-chat-view))
             (hud:add-panel-child {:builder (LlmChatView {})})))
         :on-open-tetris
         (fn []
           (local scene hud.scene)
           (when (and scene scene.add-panel-child)
             (scene:add-panel-child {:builder (TetrisView.TetrisDialog {})
                                    :skip-cuboid true})))
         :on-open-icon-browser
         (fn []
           (when (and hud hud.add-panel-child)
             (hud:add-panel-child {:builder (make-icon-browser-dialog {})})))
         :on-open-graph-control
         (fn []
           (when (and hud hud.add-panel-child)
             (hud:add-panel-child {:builder (GraphViewControlView {})})))
         :on-open-sub-app
         (fn []
           (local scene hud.scene)
           (when (and scene scene.add-panel-child)
             (scene:add-panel-child
               {:builder
                (DefaultDialog
                  {:title "Sub App One"
                   :name "sub-app-one-dialog"
                   :child (SubAppView {:name "sub-world-one"
                                       :size (glm.vec3 18 12 0)
                                       :units-per-pixel hud.world-units-per-pixel})})})))
         }
        ))
    (local title-builder
      (fn [child-ctx]
        ((Text {:text "CONTROL PANEL"}) child-ctx)))
    (local status-builder
      (fn [child-ctx]
        ((Text {:text "Status: Nominal"}) child-ctx)))
    ((ControlPanelLayout {:title-builder title-builder
                          :status-builder status-builder
                          :button-row-builder button-row})
     ctx))
  build)

(local exports {:ControlPanel ControlPanel})

(setmetatable exports {:__call (fn [_ ...]
                                 (ControlPanel ...))})

exports
