(local {: KEY_F1} (require :command-hints))

(fn normalize-handlers [handlers]
  (if (and handlers (= (type handlers) :table))
      handlers
      [handlers]))

(fn resolve-handler [handler event-name]
  (if (not handler)
      nil
      (if (= (type handler) :function)
          handler
          (. handler event-name))))

(fn require-command-hints-manager [ctx state]
  (local hud ((. ctx :hud)))
  (assert hud
          (.. "State " (tostring (and state state.name)) " requires a HUD host for command hints"))
  (assert hud.command-hints
          (.. "State " (tostring (and state state.name)) " requires hud.command-hints"))
  hud.command-hints)

(fn FirstHandlerWins [handlers]
  (local ordered (normalize-handlers handlers))
  (fn [event-name ctx payload]
    (var handled false)
    (each [_ handler (ipairs ordered)]
      (when (not handled)
        (local event-handler (resolve-handler handler event-name))
        (when event-handler
          (set handled (not (not (event-handler ctx payload)))))))
    handled))

(fn Broadcast [handlers]
  (local ordered (normalize-handlers handlers))
  (fn [event-name ctx payload]
    (var handled false)
    (each [_ handler (ipairs ordered)]
      (local event-handler (resolve-handler handler event-name))
      (when event-handler
        (when (event-handler ctx payload)
          (set handled true))))
    handled))

(fn Chain [handlers]
  (local ordered (normalize-handlers handlers))
  (fn [event-name ctx payload]
    (var handled false)
    (each [_ handler (ipairs ordered)]
      (local event-handler (resolve-handler handler event-name))
      (when event-handler
        (when (event-handler ctx payload)
          (set handled true))))
    handled))

(fn CommandHints [route-key route _ctx state]
  (if (and (not route)
           (not (= route-key :key-down)))
      nil
      (fn [_event-name ctx payload]
        (local handled (if route
                           (route route-key ctx payload)
                           false))
        (if handled
            (do
              (when (or (ctx.command-executed?)
                        (ctx.event-consumed?))
                (local manager (require-command-hints-manager ctx state))
                (assert manager.close-on-handled-event
                        (.. "State " (tostring (and state state.name)) " requires hud.command-hints:close-on-handled-event"))
                (manager:close-on-handled-event route-key payload))
              handled)
            (if (and (= route-key :key-down)
                     (= (and payload payload.key) KEY_F1))
                (do
                  (local manager (require-command-hints-manager ctx state))
                  (assert manager.handle-toggle-key
                          (.. "State " (tostring (and state state.name)) " requires hud.command-hints:handle-toggle-key"))
                  (manager:handle-toggle-key payload))
                false)))))

{:FirstHandlerWins FirstHandlerWins
 :Broadcast Broadcast
 :Chain Chain
 :CommandHints CommandHints}
