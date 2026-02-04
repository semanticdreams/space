(fn Signal []
  (var callbacks [])

  (fn emit [first payload]
    (local actual (if payload payload first))
    (each [_ cb (ipairs callbacks)]
      (cb actual)))

  (fn connect [first handler]
    (local actual (if handler handler first))
    (assert (= (type actual) :function) "Signal.connect expects a function")
    (table.insert callbacks actual)
    actual)

  (fn disconnect [first handler not-connected-ok?]
    (local actual-handler (if (= (type first) :table) handler first))
    (local allow-missing
      (if (= (type first) :table)
          not-connected-ok?
          handler))
    (local filtered [])
    (var removed false)
    (each [_ cb (ipairs callbacks)]
      (if (and (not removed) (= cb actual-handler))
          (set removed true)
          (table.insert filtered cb)))
    (if removed
        (set callbacks filtered)
        (when (not allow-missing)
          (error "Signal handler not connected"))))

  (fn clear [_maybe-self]
    (set callbacks []))

  {: emit : connect : disconnect : clear})
