(local InputDialTypeModule (require :input-dial-type))

(local tests [])

(fn input-dial-type-registers-and-unregisters-through-engine-api []
  (local calls {:activate 0
                :deactivate 0
                :on-input 0
                :off-input 0
                :controller-id nil
                :callback nil
                :off-token nil})
  (local engine
    {:dial-type-activate (fn [_self controller-id]
                           (set calls.activate (+ calls.activate 1))
                           (set calls.controller-id controller-id))
     :dial-type-deactivate (fn [_self _controller-id]
                             (set calls.deactivate (+ calls.deactivate 1)))
     :dial-type-on-input (fn [_self _controller-id callback]
                           (set calls.on-input (+ calls.on-input 1))
                           (set calls.callback callback)
                           77)
     :dial-type-off-input (fn [_self token]
                            (set calls.off-input (+ calls.off-input 1))
                            (set calls.off-token token)
                            true)})
  (var received nil)
  (local notifier
    (InputDialTypeModule.InputDialType
      {:engine engine
       :controller-id 101
       :on-input (fn [payload]
                   (set received payload))}))
  (assert (= calls.activate 1) "notifier should activate controller once")
  (assert (= calls.on-input 1) "notifier should register callback once")
  (assert (= calls.controller-id 101) "notifier should activate requested controller")
  (assert (= notifier.callback-id 77) "notifier should keep callback registration token")
  (calls.callback {:instance-id 101 :input [[1] []]})
  (assert received "callback registered through engine should be callable")
  (notifier:drop)
  (assert (= calls.off-input 1) "drop should unregister callback")
  (assert (= calls.off-token 77) "drop should unregister using stored token")
  (assert (= calls.deactivate 1) "drop should deactivate controller by default"))

(fn input-dial-type-can-keep-controller-active-on-drop []
  (local calls {:deactivate 0})
  (local engine
    {:dial-type-activate (fn [_self _controller-id] nil)
     :dial-type-deactivate (fn [_self _controller-id]
                             (set calls.deactivate (+ calls.deactivate 1)))
     :dial-type-on-input (fn [_self _controller-id _callback] 88)
     :dial-type-off-input (fn [_self _token] true)})
  (local notifier
    (InputDialTypeModule.InputDialType
      {:engine engine
       :controller-id 202
       :deactivate-on-drop false
       :on-input (fn [_payload] nil)}))
  (notifier:drop)
  (assert (= calls.deactivate 0) "drop should not deactivate when deactivate-on-drop is false"))

(table.insert tests {:name "InputDialType registers/unregisters via engine API"
                     :fn input-dial-type-registers-and-unregisters-through-engine-api})
(table.insert tests {:name "InputDialType can skip deactivate on drop"
                     :fn input-dial-type-can-keep-controller-active-on-drop})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "input-dial-type"
                       :tests tests})))

{:name "input-dial-type"
 :tests tests
 :main main}
