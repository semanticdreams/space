(local glm (require :glm))
(local gl (require :gl))
(local Harness (require :tests.e2e.harness))
(local Rectangle (require :rectangle))
(local Sized (require :sized))
(local Card (require :card))
(local Padding (require :padding))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))

(fn make-scene-builder []
  (fn [ctx]
    (local theme (and ctx ctx.theme))
    (local primary (and theme theme.button theme.button.variants theme.button.variants.primary))
    (assert primary "theme snapshot requires primary button variant")
    ((Sized {:size (glm.vec3 6 4 0)
             :child (Rectangle {:color primary.background})}) ctx)))

(fn make-overlay-card []
  (fn [ctx]
    (local theme (and ctx ctx.theme))
    (local text-color (and theme theme.text theme.text.foreground))
    (assert text-color "theme snapshot requires theme text color")
    (local title-style (TextStyle {:scale 1.5 :color text-color}))
    (local body-style (TextStyle {:scale 1.2 :color text-color}))
    (local row
      (Flex {:axis :x
             :xspacing 0.4
             :yalign :center
             :children [(FlexChild (Button {:text "Confirm"
                                            :variant :primary
                                            :padding [0.4 0.3]}))
                        (FlexChild (Button {:text "Later"
                                            :variant :secondary
                                            :padding [0.4 0.3]}))]}))
    ((Card
       {:child
        (Padding
          {:edge-insets [0.6 0.5]
           :child
           (Flex {:axis 2
                  :reverse false
                  :yspacing 0.3
                  :xalign :start
                  :children [(FlexChild (Text {:text "Theme Preview"
                                               :style title-style}))
                             (FlexChild (Text {:text "Buttons, text, and panels"
                                               :style body-style}))
                             (FlexChild row)]})})})
     ctx)))

(fn draw-scene-and-hud [ctx scene-target hud-target]
  (app.set-viewport {:width ctx.width :height ctx.height})
  (gl.glViewport 0 0 ctx.width ctx.height)
  (gl.glDisable gl.GL_CULL_FACE)
  (gl.glEnable gl.GL_DEPTH_TEST)
  (gl.glDepthFunc gl.GL_LESS)
  (gl.glClearColor 0.04 0.05 0.07 1.0)
  (gl.glClear (bor gl.GL_COLOR_BUFFER_BIT gl.GL_DEPTH_BUFFER_BIT))
  (app.renderers:apply-theme (app.themes.get-active-theme))
  (app.renderers.skybox:render scene-target)
  (app.renderers:draw-target scene-target {:text false})
  (gl.glClear gl.GL_DEPTH_BUFFER_BIT)
  (app.renderers:draw-target hud-target))

(fn capture-theme [ctx theme-key]
  (app.themes.set-theme theme-key)
  (local scene-target
    (Harness.make-scene-target {:builder (make-scene-builder)}))
  (local hud-target
    (Harness.make-hud-target {:width ctx.width
                              :height ctx.height
                              :scale-factor 1.4
                              :builder (Harness.make-test-hud-builder)}))
  (local overlay-button
    (Harness.add-centered-overlay-button hud-target
                                         {:text "Toggle"
                                          :text-scale 1.8
                                          :padding [0.6 0.4]}))
  (hud-target:update)
  (local overlay-layout (and hud-target.overlay-root hud-target.overlay-root.layout))
  (when overlay-layout
    (local center
      (+ overlay-layout.position
         (glm.vec3 (/ overlay-layout.size.x 2)
                   (/ overlay-layout.size.y 2)
                   0)))
    (hud-target:add-overlay-child {:builder (make-overlay-card)
                                   :position (+ center (glm.vec3 0 2.2 0))}))
  (draw-scene-and-hud ctx scene-target hud-target)
  (local theme-font (and (app.themes.get-active-theme) (. (app.themes.get-active-theme) :font)))
  (Harness.assert-button-label overlay-button theme-font)
  (Harness.capture-snapshot {:name (.. "theme-" (if (= theme-key :light) "light" "dark"))
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target scene-target)
  (Harness.cleanup-target hud-target))

(fn run [ctx]
  (local original (and app.themes app.themes.get-active-theme-name
                       (app.themes.get-active-theme-name)))
  (capture-theme ctx :dark)
  (capture-theme ctx :light)
  (when (and original app.themes app.themes.set-theme)
    (app.themes.set-theme original)
    (set ctx.font (and (app.themes.get-active-theme) (. (app.themes.get-active-theme) :font)))))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E theme snapshots complete"))

{:run run
 :main main}
