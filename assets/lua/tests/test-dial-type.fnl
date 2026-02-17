(local DialTypeModule (require :dial-type))

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

(table.insert tests {:name "DialType module exposes factory"
                     :fn dial-type-module-exposes-factory})
(table.insert tests {:name "DialType produces discrete tap input"
                     :fn dial-type-produces-discrete-tap})
(table.insert tests {:name "DialType keeps left/right stick inputs independent"
                     :fn dial-type-keeps-sticks-independent})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "dial-type"
                       :tests tests})))

{:name "dial-type"
 :tests tests
 :main main}
