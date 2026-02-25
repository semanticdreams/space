(local DialTypeModule (require :dial-type))
;; gamepad axis ids
(local AXIS-LX 0)
(local AXIS-LY 1)

(local tests [])

(fn dial-type-module-exposes-factory []
  (assert DialTypeModule "dial-type module should load")
  (assert DialTypeModule.DialType "dial-type module should expose DialType factory")
  (local dial (DialTypeModule.DialType))
  (assert dial "DialType factory should create an instance")
  (assert (not (dial:has-input)) "new DialType should not have pending input"))

(fn dial-type-produces-discrete-tap []
  (local dial (DialTypeModule.DialType))
  (assert (not (dial:update 0.0 0.0 0.0 0.0)))
  ;; Push left stick beyond threshold and release.
  (assert (not (dial:update 1.0 0.0 0.0 0.0)))
  (assert (dial:update 0.0 0.0 0.0 0.0))
  (assert (dial:has-input))
  (local out (dial:poll))
  (assert out "poll should return emitted stacks")
  (assert (> (length (. out 1)) 0) "left stack should contain one or more sectors")
  (assert (= (length (. out 2)) 0) "right stack should be empty")
  (assert (not (dial:has-input)) "poll should consume pending input"))

(fn dial-type-keeps-sticks-independent []
  (local dial (DialTypeModule.DialType))
  ;; Build a dialing gesture on left stick and a tap on right stick.
  (dial:update 1.0 0.0 0.0 0.0)
  (dial:update 0.0 1.0 0.0 -1.0)
  (assert (dial:update 0.0 0.0 0.0 0.0))
  (local out (dial:poll))
  (assert out "poll should return combined output")
  (assert (> (length (. out 1)) 1) "left dialing sequence should contain multiple sectors")
  (assert (= (length (. out 2)) 1) "right tap should contain one sector")
  (assert (= (. (. out 1) 1) 1) "left dialing sequence should start from right sector in this gesture"))

(fn input-dial-type-adapter-processes-only-when-updated []
  (local input app.engine.input)
  (local adapter (DialTypeModule.InputDialType input))
  ;; reset gamepads
  (each [_ id (ipairs (input:gamepad-ids))]
    (input:on-gamepad-disconnected id 0))

  (input:on-gamepad-connected 0 101 1)
  (input:on-gamepad-axis AXIS-LX 1.0 101 2)
  ;; no update call yet, so no dial output should be present
  (assert (not (adapter:has-input-for 101)))
  (assert (not (adapter:update-gamepad 101)))
  (input:on-gamepad-axis AXIS-LX 0.0 101 3)
  (assert (adapter:update-gamepad 101))
  (local out (adapter:poll-gamepad 101))
  (assert out "adapter should emit dial output after explicit update")
  (assert (> (length (. out 1)) 0) "left stack should contain emitted sectors"))

(table.insert tests {:name "DialType module exposes factory"
                     :fn dial-type-module-exposes-factory})
(table.insert tests {:name "DialType produces discrete tap input"
                     :fn dial-type-produces-discrete-tap})
(table.insert tests {:name "DialType keeps left/right stick inputs independent"
                     :fn dial-type-keeps-sticks-independent})
(table.insert tests {:name "InputDialType adapter updates on demand"
                     :fn input-dial-type-adapter-processes-only-when-updated})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "dial-type"
                       :tests tests})))

{:name "dial-type"
 :tests tests
 :main main}
