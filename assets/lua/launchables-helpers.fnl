(local glm (require :glm))
(local ThemeActions (require :theme-actions))

(local default-terminal-size (glm.vec3 60 36 0))

(fn make-terminal-dialog [opts]
  (local options (or opts {}))
  (local DefaultDialog (require :default-dialog))
  (local Padding (require :padding))
  (local Sized (require :sized))
  (local TerminalWidget (require :terminal-widget))
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

(fn make-icon-browser-dialog [opts]
  (local options (or opts {}))
  (local DefaultDialog (require :default-dialog))
  (local XdgIconBrowser (require :xdg-icon-browser))
  (DefaultDialog
    {:title "Icon Browser"
     :name "icon-browser-dialog"
     :resizeable true
     :on-close options.on-close
     :child (XdgIconBrowser.XdgIconBrowser {})}))

(var box-textured-element nil)
(fn add-box-textured []
  (local scene app.scene)
  (assert (and scene scene.add-panel-child) "box-textured requires app.scene.add-panel-child")
  (local GltfMesh (require :gltf-mesh))
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
        box-textured-element)))

(fn make-sub-app-one-dialog [hud]
  (assert hud "sub-app-one dialog requires hud")
  (local DefaultDialog (require :default-dialog))
  (local SubAppView (require :sub-app-view))
  (DefaultDialog
    {:title "Sub App One"
     :name "sub-app-one-dialog"
     :child
     (SubAppView {:name "sub-world-one"
                  :size (glm.vec3 18 12 0)
                  :units-per-pixel hud.world-units-per-pixel})}))

{:make-terminal-dialog make-terminal-dialog
 :make-icon-browser-dialog make-icon-browser-dialog
 :add-box-textured add-box-textured
 :make-sub-app-one-dialog make-sub-app-one-dialog
 :toggle-theme ThemeActions.toggle-theme}
