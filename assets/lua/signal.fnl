(fn Signal []
  (var callbacks [])
  (var emit-depth 0)
  (var compact-pending? false)

  (fn compact-callbacks []
    (when (and compact-pending? (= emit-depth 0))
      (local filtered [])
      (each [_ record (ipairs callbacks)]
        (when (and record record.active?)
          (table.insert filtered record)))
      (set callbacks filtered)
      (set compact-pending? false)))

  (fn emit [first payload]
    (local actual (if payload payload first))
    (set emit-depth (+ emit-depth 1))
    (local (ok err)
      (pcall
        (fn []
          (local count (length callbacks))
          (for [idx 1 count]
            (local record (. callbacks idx))
            (when (and record record.active?)
              (record.handler actual))))))
    (set emit-depth (- emit-depth 1))
    (compact-callbacks)
    (when (not ok)
      (error err 0)))

  (fn connect [first handler]
    (local actual (if handler handler first))
    (assert (= (type actual) :function) "Signal.connect expects a function")
    (table.insert callbacks {:handler actual
                             :active? true})
    actual)

  (fn disconnect [first handler not-connected-ok?]
    (local actual-handler (if (= (type first) :table) handler first))
    (local allow-missing
      (if (= (type first) :table)
          not-connected-ok?
          handler))
    (var removed false)
    (each [_ record (ipairs callbacks)]
      (when (and (not removed)
                 record
                 record.active?
                 (= record.handler actual-handler))
        (set record.active? false)
        (set removed true)
        (set compact-pending? true)))
    (if removed
        (compact-callbacks)
        (when (not allow-missing)
          (error "Signal handler not connected"))))

  (fn clear [_maybe-self]
    (each [_ record (ipairs callbacks)]
      (when record
        (set record.active? false)))
    (set compact-pending? true)
    (compact-callbacks))

  {: emit : connect : disconnect : clear})
