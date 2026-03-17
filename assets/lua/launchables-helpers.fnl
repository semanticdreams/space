(local glm (require :glm))
(local ThemeActions (require :theme-actions))

(local default-terminal-size (glm.vec3 60 36 0))

(fn make-terminal-dialog [opts]
  (local options (or opts {}))
  (local DefaultDialog (require :default-dialog))
  (local Sized (require :sized))
  (local TerminalWidget (require :terminal-widget))
  (DefaultDialog
    {:title "Terminal"
     :name "hud-terminal-dialog"
     :body-padding false
     :on-close options.on-close
     :child
     (Sized {:size default-terminal-size
             :child (TerminalWidget {:name "hud-terminal"
                                     :focus-name "hud-terminal"
                                     :follow-tail? true})})}))

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

(fn make-fennel-interpreter-dialog [opts]
  (local options (or opts {}))
  (local DefaultDialog (require :default-dialog))
  (local FennelInterpreterView (require :fennel-interpreter-view))
  (DefaultDialog
    {:title "Fennel Interpreter"
     :name "fennel-interpreter-dialog"
     :resizeable true
     :on-close options.on-close
     :child (FennelInterpreterView {:name "fennel-interpreter"})}))

(var box-textured-element nil)
(fn add-box-textured [opts]
  (local options (or opts {}))
  (local scene (or options.scene app.scene))
  (assert (and scene scene.add-panel-child) "box-textured requires app.scene.add-panel-child")
  (local GltfMesh (require :gltf-mesh))
  (local position (or options.position (glm.vec3 5 -100 5)))
  (local rotation (or options.rotation (glm.quat (math.rad -90) (glm.vec3 1 0 0))))
  (if box-textured-element
      box-textured-element
      (do
        (local box-textured
          (GltfMesh {:path "models/BoxTextured.glb"
                     :position position
                     :rotation rotation
                     :scale (glm.vec3 100)
                     :name "box-textured-model"}))
        (set box-textured-element
             (scene:add-panel-child {:builder box-textured
                                     :position position
                                     :rotation rotation
                                     :persistence {:kind "scene-box-textured"
                                                   :restorer-module "launchables/box-textured"}
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

(fn make-next-app-dialog [hud]
  (assert hud "next-app dialog requires hud")
  (local DefaultDialog (require :default-dialog))
  (local SubAppView (require :sub-app-view))
  (local NextAppSubApp (require :next-app/sub-app))
  (DefaultDialog
    {:title "Next App"
     :name "next-app-dialog"
     :child
     (SubAppView {:name "next-app-sub-world"
                  :size (glm.vec3 18 12 0)
                  :units-per-pixel hud.world-units-per-pixel
                  :sub-app-builder NextAppSubApp
                  :sub-app-options {:renderer-options {:cuboid-count 100
                                                       :cuboid-seed 1337}}})}))

{:make-terminal-dialog make-terminal-dialog
 :make-fennel-interpreter-dialog make-fennel-interpreter-dialog
 :make-icon-browser-dialog make-icon-browser-dialog
 :add-box-textured add-box-textured
 :make-sub-app-one-dialog make-sub-app-one-dialog
 :make-next-app-dialog make-next-app-dialog
 :toggle-theme ThemeActions.toggle-theme}
