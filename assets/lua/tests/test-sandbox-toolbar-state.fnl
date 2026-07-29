(local tests [])
(local _ (require :main))
(local SandboxToolbarState (require :sandbox-toolbar-state))

(fn sandbox-toolbar-state-defaults []
  "Default state must have camera-mode :flight, object-move-enabled? false,
  and drag-attachment :center."
  (local state (SandboxToolbarState {}))
  (assert (= state.camera-mode :flight)
          "Default camera-mode must be :flight")
  (assert (= state.object-move-enabled? false)
          "Default object-move-enabled? must be false")
  (assert (= state.drag-attachment :center)
          "Default drag-attachment must be :center"))

(fn sandbox-toolbar-state-changed-signal-fires-on-mutation []
  "State.changed must be a Signal and must fire once per mutation."
  (local state (SandboxToolbarState {}))
  (var emit-count 0)
  (state.changed:connect (fn [] (set emit-count (+ emit-count 1))))
  (state:set-camera-mode :grounded)
  (assert (= emit-count 1)
          (.. "Changed signal should fire once after set-camera-mode, got " (tostring emit-count)))
  (state:set-object-move-enabled! true)
  (assert (= emit-count 2)
          (.. "Changed signal should fire twice after set-object-move-enabled!, got " (tostring emit-count)))
  (state:set-drag-attachment :anchor)
  (assert (= emit-count 3)
          (.. "Changed signal should fire three times after set-drag-attachment, got " (tostring emit-count))))

(fn sandbox-toolbar-state-changed-signal-noop-on-same-value []
  "State.changed must not fire when setting the same value."
  (local state (SandboxToolbarState {}))
  (var emit-count 0)
  (state.changed:connect (fn [] (set emit-count (+ emit-count 1))))
  (state:set-camera-mode :flight)
  (assert (= emit-count 0)
          (.. "Changed signal should not fire when setting same camera-mode, got " (tostring emit-count)))
  (state:set-object-move-enabled! false)
  (assert (= emit-count 0)
          (.. "Changed signal should not fire when setting same object-move-enabled?, got " (tostring emit-count)))
  (state:set-drag-attachment :center)
  (assert (= emit-count 0)
          (.. "Changed signal should not fire when setting same drag-attachment, got " (tostring emit-count))))

(fn sandbox-toolbar-state-invalid-camera-mode-errors []
  "Setting an invalid camera-mode must error."
  (local state (SandboxToolbarState {}))
  (local (ok err) (pcall state.set-camera-mode state :bogus))
  (assert (not ok) "Invalid camera-mode must error")
  (assert (err:find "Invalid camera mode")
          (.. "Error must mention invalid camera mode, got: " (tostring err))))

(fn sandbox-toolbar-state-invalid-drag-attachment-errors []
  "Setting an invalid drag-attachment must error."
  (local state (SandboxToolbarState {}))
  (local (ok err) (pcall state.set-drag-attachment state :bogus))
  (assert (not ok) "Invalid drag-attachment must error")
  (assert (err:find "Invalid drag attachment")
          (.. "Error must mention invalid drag attachment, got: " (tostring err))))

(fn sandbox-toolbar-state-capture-returns-canonical-table []
  "capture-state must return a table with canonical string values."
  (local state (SandboxToolbarState {}))
  (local captured (state:capture-state))
  (assert (= (type captured) :table)
          "capture-state must return a table")
  (assert (= captured.camera-mode "flight")
          (.. "captured camera-mode must be 'flight', got " (tostring captured.camera-mode)))
  (assert (= captured.object-move-enabled? false)
          (.. "captured object-move-enabled? must be false, got " (tostring captured.object-move-enabled?)))
  (assert (= captured.drag-attachment "center")
          (.. "captured drag-attachment must be 'center', got " (tostring captured.drag-attachment)))
  ;; After mutations, capture must reflect current state
  (state:set-camera-mode :grounded)
  (state:set-object-move-enabled! true)
  (state:set-drag-attachment :anchor)
  (local mutated (state:capture-state))
  (assert (= mutated.camera-mode "grounded")
          "captured camera-mode must be 'grounded' after mutation")
  (assert (= mutated.object-move-enabled? true)
          "captured object-move-enabled? must be true after mutation")
  (assert (= mutated.drag-attachment "anchor")
          "captured drag-attachment must be 'anchor' after mutation"))

(fn sandbox-toolbar-state-restore-accepts-valid-payload []
  "restore-state with a valid payload must set all fields."
  (local state (SandboxToolbarState {}))
  (state:restore-state {:camera-mode "grounded"
                        :object-move-enabled? true
                        :drag-attachment "anchor"})
  (assert (= state.camera-mode :grounded)
          "camera-mode must be :grounded after restore")
  (assert (= state.object-move-enabled? true)
          "object-move-enabled? must be true after restore")
  (assert (= state.drag-attachment :anchor)
          "drag-attachment must be :anchor after restore"))

(fn sandbox-toolbar-state-restore-accepts-nil []
  "restore-state with nil must leave defaults unchanged."
  (local state (SandboxToolbarState {}))
  (state:set-camera-mode :grounded)
  (state:restore-state nil)
  (assert (= state.camera-mode :grounded)
          "camera-mode must remain :grounded after nil restore")
  (state:restore-state {})
  (assert (= state.camera-mode :grounded)
          "camera-mode must remain :grounded after empty-table restore"))

(fn sandbox-toolbar-state-toggle-camera-mode []
  "toggle-camera-mode must toggle between :flight and :grounded."
  (local state (SandboxToolbarState {}))
  (assert (= state.camera-mode :flight)
          "camera-mode must start as :flight")
  (state:toggle-camera-mode)
  (assert (= state.camera-mode :grounded)
          "camera-mode must be :grounded after first toggle")
  (state:toggle-camera-mode)
  (assert (= state.camera-mode :flight)
          "camera-mode must be :flight after second toggle"))

(fn sandbox-toolbar-state-toggle-object-move-enabled []
  "toggle-object-move-enabled! must toggle the boolean."
  (local state (SandboxToolbarState {}))
  (assert (= state.object-move-enabled? false)
          "object-move-enabled? must start as false")
  (state:toggle-object-move-enabled!)
  (assert (= state.object-move-enabled? true)
          "object-move-enabled? must be true after first toggle")
  (state:toggle-object-move-enabled!)
  (assert (= state.object-move-enabled? false)
          "object-move-enabled? must be false after second toggle"))

(fn sandbox-toolbar-state-toggle-drag-attachment []
  "toggle-drag-attachment must toggle between :center and :anchor."
  (local state (SandboxToolbarState {}))
  (assert (= state.drag-attachment :center)
          "drag-attachment must start as :center")
  (state:toggle-drag-attachment)
  (assert (= state.drag-attachment :anchor)
          "drag-attachment must be :anchor after first toggle")
  (state:toggle-drag-attachment)
  (assert (= state.drag-attachment :center)
          "drag-attachment must be :center after second toggle"))

(fn sandbox-toolbar-state-rejects-non-boolean-object-move-enabled []
  "set-object-move-enabled! must error on non-boolean values."
  (local state (SandboxToolbarState {}))
  (local (ok err) (pcall state.set-object-move-enabled! state "false"))
  (assert (not ok) "set-object-move-enabled! must error on string false")
  (assert (err:find "boolean")
          (.. "Error must mention boolean, got: " (tostring err)))
  (local (ok2 err2) (pcall state.set-object-move-enabled! state 1))
  (assert (not ok2) "set-object-move-enabled! must error on number")
  (local (ok3 err3) (pcall state.set-object-move-enabled! state nil))
  (assert (not ok3) "set-object-move-enabled! must error on nil"))

(fn sandbox-toolbar-state-restore-rejects-non-table-payload []
  "restore-state must error when payload is non-nil and not a table."
  (local state (SandboxToolbarState {}))
  (local (ok err) (pcall state.restore-state state "bad"))
  (assert (not ok) "restore-state must error on string payload")
  (assert (err:find "table")
          (.. "Error must mention table, got: " (tostring err)))
  (local (ok2 err2) (pcall state.restore-state state 42))
  (assert (not ok2) "restore-state must error on number payload"))

(fn sandbox-toolbar-state-restore-accepts-nil-payload []
  "restore-state must accept nil payload without error."
  (local state (SandboxToolbarState {}))
  (local (ok _) (pcall state.restore-state state nil))
  (assert ok "restore-state must accept nil payload without error"))

(table.insert tests {:name "sandbox toolbar state defaults"
                      :fn sandbox-toolbar-state-defaults})
(table.insert tests {:name "sandbox toolbar state changed signal fires on mutation"
                      :fn sandbox-toolbar-state-changed-signal-fires-on-mutation})
(table.insert tests {:name "sandbox toolbar state changed signal noop on same value"
                      :fn sandbox-toolbar-state-changed-signal-noop-on-same-value})
(table.insert tests {:name "sandbox toolbar state invalid camera mode errors"
                      :fn sandbox-toolbar-state-invalid-camera-mode-errors})
(table.insert tests {:name "sandbox toolbar state invalid drag attachment errors"
                      :fn sandbox-toolbar-state-invalid-drag-attachment-errors})
(table.insert tests {:name "sandbox toolbar state capture returns canonical table"
                      :fn sandbox-toolbar-state-capture-returns-canonical-table})
(table.insert tests {:name "sandbox toolbar state restore accepts valid payload"
                      :fn sandbox-toolbar-state-restore-accepts-valid-payload})
(table.insert tests {:name "sandbox toolbar state restore accepts nil"
                      :fn sandbox-toolbar-state-restore-accepts-nil})
(table.insert tests {:name "sandbox toolbar state toggle camera mode"
                      :fn sandbox-toolbar-state-toggle-camera-mode})
(table.insert tests {:name "sandbox toolbar state toggle object move enabled"
                      :fn sandbox-toolbar-state-toggle-object-move-enabled})
(table.insert tests {:name "sandbox toolbar state toggle drag attachment"
                      :fn sandbox-toolbar-state-toggle-drag-attachment})
(table.insert tests {:name "sandbox toolbar state rejects non-boolean object move enabled"
                      :fn sandbox-toolbar-state-rejects-non-boolean-object-move-enabled})
(table.insert tests {:name "sandbox toolbar state restore rejects non-table payload"
                      :fn sandbox-toolbar-state-restore-rejects-non-table-payload})
(table.insert tests {:name "sandbox toolbar state restore accepts nil payload"
                      :fn sandbox-toolbar-state-restore-accepts-nil-payload})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "sandbox-toolbar-state"
                       :tests tests})))

{:name "sandbox-toolbar-state"
 :tests tests
 :main main}
