(fn fixture-path [name]
  (assert app "tests.test-support requires global app")
  (assert app.engine "tests.test-support requires app.engine")
  (assert app.engine.get-asset-path "tests.test-support requires app.engine.get-asset-path")
  (app.engine.get-asset-path (.. "lua/tests/data/" name)))

(fn suspend-active-state [states]
  (var active-state (and states states.active-state (states:active-state)))
  (when (and active-state active-state.on-leave)
    (local (ok err) (pcall active-state.on-leave active-state))
    (if ok
        nil
        (if (and (= (type err) :string)
                 (string.find err "Signal handler not connected" 1 true))
            (set active-state nil)
            (error err))))
  active-state)

(fn resume-active-state [state]
  (when (and state state.on-enter)
    (state:on-enter)))

{:fixture-path fixture-path
 :suspend-active-state suspend-active-state
 :resume-active-state resume-active-state}
