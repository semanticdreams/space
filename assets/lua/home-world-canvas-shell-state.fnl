(local CanvasFeatures (require :canvas-features))

(fn resolve-runtime-interaction-surface [surface]
  (if (or (= surface :canvas)
          (= surface "canvas"))
      :canvas
      :scene))

(fn encode-interaction-surface [surface]
  (if (= (resolve-runtime-interaction-surface surface) :canvas)
      "canvas"
      "scene"))

(fn capture-canvas-shell-state [world runtime canvas-state]
  (local existing-canvas-state (or (and world.state world.state.canvas) {}))
  (local captured (or canvas-state {}))
  (set captured.active_feature
       (or (and runtime runtime.active-canvas-feature)
           existing-canvas-state.active_feature
           (. CanvasFeatures :default-feature-id)))
  (set captured.preferred_interaction_surface
       (encode-interaction-surface
         (or (and runtime runtime.preferred-interaction-surface)
             existing-canvas-state.preferred_interaction_surface
             "scene")))
  captured)

{:resolve-runtime-interaction-surface resolve-runtime-interaction-surface
 :encode-interaction-surface encode-interaction-surface
 :capture-canvas-shell-state capture-canvas-shell-state}
