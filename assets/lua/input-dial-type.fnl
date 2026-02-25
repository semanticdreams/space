(fn InputDialType [opts]
  (local options (or opts {}))
  (local engine (or options.engine (and app app.engine)))
  (assert engine "InputDialType requires :engine or app.engine")
  (assert engine.dial-type-activate "InputDialType requires engine.dial-type-activate")
  (assert engine.dial-type-deactivate "InputDialType requires engine.dial-type-deactivate")
  (assert engine.dial-type-on-input "InputDialType requires engine.dial-type-on-input")
  (assert engine.dial-type-off-input "InputDialType requires engine.dial-type-off-input")
  (local gamepad-id options.gamepad-id)
  (assert gamepad-id "InputDialType requires :gamepad-id")
  (local on-input (or options.on-input options.callback))
  (assert (= (type on-input) :function) "InputDialType requires :on-input callback")
  (local deactivate-on-drop?
    (if (= options.deactivate-on-drop nil)
        true
        options.deactivate-on-drop))

  (engine:dial-type-activate gamepad-id)
  (var callback-id (engine:dial-type-on-input gamepad-id on-input))
  (var dropped? false)

  (fn drop [_self]
    (when (not dropped?)
      (set dropped? true)
      (when callback-id
        (engine:dial-type-off-input callback-id)
        (set callback-id nil))
      (when deactivate-on-drop?
        (engine:dial-type-deactivate gamepad-id))))

  {:engine engine
   :gamepad-id gamepad-id
   :callback-id callback-id
   :drop drop})

{:InputDialType InputDialType}
