(local Harness (require :tests.e2e.harness))
(local Dialog (require :dialog))
(local Menu (require :menu))
(local Text (require :text))
(local glm (require :glm))

(fn dialog-builder [title body]
  (Dialog {:title title
           :child (fn [ctx]
                    ((Text {:text body}) ctx))}))

(fn run [ctx]
  (local hud
    (Harness.make-hud-target {:width ctx.width
                              :height ctx.height
                              :builder (Harness.make-test-hud-builder)}))

  ;; Tile dialog: should always stay beneath float dialogs.
  (hud:add-panel-child {:location :tiles
                        :builder (dialog-builder "Tile dialog" "Tile")
                        :align-x :start
                        :align-y :center
                        :depth-offset-index 0})

  ;; Two overlapping dialogs deliberately share the same explicit base depth.
  ;; Float layer must still assign unique depth bands per dialog.
  (hud:add-panel-child {:location :float
                        :builder (dialog-builder "Back dialog" "Below")
                        :position (glm.vec3 -22.8 8.0 0)
                        :size (glm.vec3 11.0 6.6 0)
                        :depth-offset-index 0})
  (hud:add-panel-child {:location :float
                        :builder (dialog-builder "Front dialog" "Cover")
                        :position (glm.vec3 -21.8 7.2 0)
                        :size (glm.vec3 11.0 6.6 0)
                        :depth-offset-index 0})

  ;; Overlay menu should render on top of dialogs and keep text visible.
  (hud:add-overlay-child {:builder (Menu {:actions [{:name "Inspect"}
                                                     {:name "Bring to front"}
                                                     {:name "Close"}]})
                          :position (glm.vec3 14.0 8.8 0)
                          :depth-offset-index 0})

  (Harness.draw-targets ctx.width ctx.height [{:target hud}])
  (Harness.capture-snapshot {:name "hud-depth-ordering"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target hud))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E hud depth ordering snapshot complete"))

{:run run
 :main main}
