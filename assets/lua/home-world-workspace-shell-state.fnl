(fn resolve-runtime-interaction-surface [surface]
  (if (or (= surface :canvas)
          (= surface "canvas"))
      :canvas
      :scene))

(fn encode-interaction-surface [surface]
  (if (= (resolve-runtime-interaction-surface surface) :canvas)
      "canvas"
      "scene"))

(fn capture-activity-shell-state [world runtime activity-state]
  (local existing-activity-state (or (and world.state world.state.activity) {}))
  (local captured (or activity-state {}))
  (if (and runtime runtime.requested-activity-known?)
      (set captured.active_id runtime.requested-activity-id)
      (set captured.active_id existing-activity-state.active_id))
  (set captured.preferred_interaction_surface
       (encode-interaction-surface
         (or (and runtime runtime.preferred-interaction-surface)
             existing-activity-state.preferred_interaction_surface
             "scene")))
  (when (not captured.sessions)
    (set captured.sessions (or existing-activity-state.sessions {})))
  captured)

{:resolve-runtime-interaction-surface resolve-runtime-interaction-surface
 :encode-interaction-surface encode-interaction-surface
 :capture-activity-shell-state capture-activity-shell-state}
