(local tests [])
(local _ (require :main))
(local SandboxToolbarState (require :sandbox-toolbar-state))

(fn sandbox-toolbar-state-defaults-to-flight []
  (local state (SandboxToolbarState {}))
  (assert (= state.interaction-mode :flight) "default mode must be :flight")
  (assert (= (state:navigation-mode) :flight) "default navigation mode must be :flight")
  (assert (= (state:object-drag-mode) nil) "default object drag mode must be nil"))

(fn sandbox-toolbar-state-sets-valid-modes []
  (local state (SandboxToolbarState {}))
  (each [_ mode (ipairs [:flight :walk :move :grab])]
    (state:set-interaction-mode mode)
    (assert (= state.interaction-mode mode) (.. "mode should be " (tostring mode)))))

(fn sandbox-toolbar-state-rejects-invalid-mode []
  (local state (SandboxToolbarState {}))
  (local (ok err) (pcall state.set-interaction-mode state :grounded))
  (assert (not ok) "legacy :grounded must not be a valid runtime mode")
  (assert (string.find (tostring err) "Invalid interaction mode")
          (.. "error should mention invalid interaction mode, got " (tostring err))))

(fn sandbox-toolbar-state-rejects-malformed-constructor-options []
  (local (ok err) (pcall SandboxToolbarState false))
  (assert (not ok) "constructor options must be a table or nil")
  (assert (string.find (tostring err) "opts must be a table" 1 true)
          (.. "error should mention opts table, got " (tostring err)))
  (local (ok2 err2) (pcall SandboxToolbarState {:interaction-mode false}))
  (assert (not ok2) "false interaction-mode must be rejected")
  (assert (string.find (tostring err2) "Invalid interaction mode" 1 true)
          (.. "error should mention invalid interaction mode, got " (tostring err2)))
  (each [_ key (ipairs [:camera-mode :object-move-enabled? :drag-attachment])]
    (local (legacy-ok legacy-err) (pcall SandboxToolbarState {key true}))
    (assert (not legacy-ok) (.. "constructor must reject legacy key " (tostring key)))
    (assert (string.find (tostring legacy-err) (tostring key) 1 true)
            (.. "error should mention legacy key " (tostring key) ", got " (tostring legacy-err)))))

(fn sandbox-toolbar-state-captures-canonical-payload []
  (local state (SandboxToolbarState {:interaction-mode :grab}))
  (local captured (state:capture-state))
  (assert (= captured.interaction-mode "grab") "capture must store interaction-mode")
  (assert (= captured.camera-mode nil) "capture must not store camera-mode")
  (assert (= captured.object-move-enabled? nil) "capture must not store object-move-enabled?")
  (assert (= captured.drag-attachment nil) "capture must not store drag-attachment"))

(fn sandbox-toolbar-state-migrates-legacy-payloads []
  (local state (SandboxToolbarState {}))
  (state:restore-state {:object-move-enabled? true :drag-attachment "anchor" :camera-mode "flight"})
  (assert (= state.interaction-mode :grab) "legacy move+anchor must migrate to :grab")
  (state:restore-state {:object-move-enabled? true :drag-attachment "center" :camera-mode "flight"})
  (assert (= state.interaction-mode :move) "legacy move+center must migrate to :move")
  (state:restore-state {:object-move-enabled? false :camera-mode "grounded"})
  (assert (= state.interaction-mode :walk) "legacy grounded must migrate to :walk")
  (state:restore-state {:camera-mode "flight"})
  (assert (= state.interaction-mode :flight) "legacy flight must migrate to :flight"))

(fn sandbox-toolbar-state-rejects-malformed-legacy-payloads []
  (local state (SandboxToolbarState {}))
  (local (ok err) (pcall state.restore-state state {:object-move-enabled? "true"}))
  (assert (not ok) "legacy object-move-enabled? string must be rejected")
  (assert (string.find (tostring err) "object-move-enabled?" 1 true)
          (.. "error should mention object-move-enabled?, got " (tostring err)))
  (local (ok2 err2) (pcall state.restore-state state {:drag-attachment "hinge"}))
  (assert (not ok2) "unknown legacy drag-attachment must be rejected")
  (assert (string.find (tostring err2) "drag-attachment" 1 true)
          (.. "error should mention drag-attachment, got " (tostring err2)))
  (local (ok3 err3) (pcall state.restore-state state {:camera-mode "ground"}))
  (assert (not ok3) "unknown legacy camera-mode must be rejected")
  (assert (string.find (tostring err3) "camera-mode" 1 true)
          (.. "error should mention camera-mode, got " (tostring err3))))

(fn sandbox-toolbar-state-removes-legacy-runtime-aliases []
  (local state (SandboxToolbarState {}))
  (assert (= state.camera-mode nil) "camera-mode alias must be absent")
  (assert (= state.object-move-enabled? nil) "object-move-enabled? alias must be absent")
  (assert (= state.drag-attachment nil) "drag-attachment alias must be absent")
  (assert (= state.toggle-camera-mode nil) "toggle-camera-mode must be absent")
  (assert (= state.toggle-object-move-enabled! nil) "toggle-object-move-enabled! must be absent")
  (assert (= state.toggle-drag-attachment nil) "toggle-drag-attachment must be absent"))

(table.insert tests {:name "sandbox toolbar state defaults to flight"
                     :fn sandbox-toolbar-state-defaults-to-flight})
(table.insert tests {:name "sandbox toolbar state sets valid modes"
                     :fn sandbox-toolbar-state-sets-valid-modes})
(table.insert tests {:name "sandbox toolbar state rejects invalid mode"
                     :fn sandbox-toolbar-state-rejects-invalid-mode})
(table.insert tests {:name "sandbox toolbar state rejects malformed constructor options"
                     :fn sandbox-toolbar-state-rejects-malformed-constructor-options})
(table.insert tests {:name "sandbox toolbar state captures canonical payload"
                     :fn sandbox-toolbar-state-captures-canonical-payload})
(table.insert tests {:name "sandbox toolbar state migrates legacy payloads"
                     :fn sandbox-toolbar-state-migrates-legacy-payloads})
(table.insert tests {:name "sandbox toolbar state rejects malformed legacy payloads"
                     :fn sandbox-toolbar-state-rejects-malformed-legacy-payloads})
(table.insert tests {:name "sandbox toolbar state removes legacy runtime aliases"
                     :fn sandbox-toolbar-state-removes-legacy-runtime-aliases})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "sandbox-toolbar-state"
                       :tests tests})))

{:name "sandbox-toolbar-state"
 :tests tests
 :main main}
