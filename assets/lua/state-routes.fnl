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

{:FirstHandlerWins FirstHandlerWins
 :Broadcast Broadcast
 :Chain Chain}
