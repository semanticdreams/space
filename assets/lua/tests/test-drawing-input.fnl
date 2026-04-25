(local _ (require :main))
(local NormalState (require :normal-state))
(local InputState (require :input-state-router))
(local States (require :states))
(local StateSystemBindings (require :state-system-bindings))

(local tests [])

(fn make-command-hints-stub []
  {:handle-toggle-key (fn [_self _payload] true)
   :close-on-handled-event (fn [_self _route-key _payload] false)})

(fn command-hints-hud-provider [_self]
  {:command-hints (make-command-hints-stub)})

(local KEY_DELETE 127)
(local KEY_RETURN 13)
(local KEY_ESCAPE 27)
(local KEY_Z_LOWER (string.byte "z"))
(local KEY_Y_LOWER (string.byte "y"))
(local CTRL-MOD 64)

(fn with-app-bindings [bindings body]
  (local previous {})
  (each [key value (pairs bindings)]
    (set (. previous key) (. app key))
    (set (. app key) value))
  (local (ok result) (pcall body))
  (InputState.reset)
  (each [key value (pairs previous)]
    (set (. app key) value))
  (when (not ok)
    (error result))
  result)

(fn with-normal-state [body]
  (local original-states app.states)
  (local states
    (States {:hud_provider command-hints-hud-provider
             :focus_manager_provider (fn [_self]
                                       app.focus)}))
  (StateSystemBindings.bind-states-host states)
  (set app.states states)
  (local state (NormalState))
  (states:add-state :normal state)
  (local (ok result) (pcall body state))
  (StateSystemBindings.bind-states-host original-states)
  (set app.states original-states)
  (when (not ok)
    (error result))
  result)

(fn drawing-mode-blocks-graph-keyboard-actions []
  (var delete-calls 0)
  (var open-calls 0)
  (with-app-bindings
    {:active-canvas-feature "drawing"
     :drawing-controller {:on-delete-selection (fn [_self] false)}
     :graph-view {:remove-selected-nodes (fn [_self]
                                           (set delete-calls (+ delete-calls 1))
                                           1)
                  :open-focused-node (fn [_self]
                                       (set open-calls (+ open-calls 1))
                                       true)}
     :focus nil}
    (fn []
      (with-normal-state
        (fn [state]
          (assert (not (state:on-key-down {:key KEY_DELETE :mod 0})))
          (assert (not (state:on-key-down {:key KEY_RETURN :mod 0})))
          (assert (= delete-calls 0))
          (assert (= open-calls 0)))))))

(fn active-input-blocks-drawing-shortcuts []
  (local draw-calls {:delete 0
                     :undo 0
                     :redo 0
                     :cancel 0})
  (local input-events [])
  (with-app-bindings
    {:active-canvas-feature "drawing"
     :drawing-controller {:on-delete-selection (fn [_self]
                                                 (set draw-calls.delete (+ draw-calls.delete 1))
                                                 true)
                          :on-undo (fn [_self]
                                     (set draw-calls.undo (+ draw-calls.undo 1))
                                     true)
                          :on-redo (fn [_self]
                                     (set draw-calls.redo (+ draw-calls.redo 1))
                                     true)
                          :cancel-gesture (fn [_self]
                                            (set draw-calls.cancel (+ draw-calls.cancel 1))
                                            true)}
     :graph-view nil
     :focus nil}
    (fn []
      (with-normal-state
        (fn [state]
          (InputState.connect-input
            {:on-key-down (fn [_self payload]
                            (table.insert input-events {:key payload.key :mod (or payload.mod 0)})
                            false)})
          (assert (state:on-key-down {:key KEY_DELETE :mod 0}))
          (assert (state:on-key-down {:key KEY_ESCAPE :mod 0}))
          (assert (state:on-key-down {:key KEY_Z_LOWER :mod CTRL-MOD}))
          (assert (state:on-key-down {:key KEY_Y_LOWER :mod CTRL-MOD}))
          (assert (= (# input-events) 4))
          (assert (= draw-calls.delete 0))
          (assert (= draw-calls.undo 0))
          (assert (= draw-calls.redo 0))
          (assert (= draw-calls.cancel 0)))))))

(table.insert tests {:name "Drawing mode blocks graph keyboard actions"
                     :fn drawing-mode-blocks-graph-keyboard-actions})
(table.insert tests {:name "Active inputs block drawing shortcuts in normal state"
                     :fn active-input-blocks-drawing-shortcuts})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "drawing-input"
                       :tests tests})))

{:name "drawing-input"
 :tests tests
 :main main}
