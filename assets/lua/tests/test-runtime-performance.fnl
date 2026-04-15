(local tests [])
(local fs (require :fs))
(local Settings (require :settings))
(local RuntimePerformance (require :runtime-performance))

(var temp-counter 0)
(local settings-temp-root (fs.join-path "/tmp/space/tests" "runtime-performance-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path settings-temp-root (.. "runtime-performance-test-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn manual-mode-defaults-to-max []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (RuntimePerformance.ensure-settings-defaults settings)
    (local state (RuntimePerformance.create-state))
    (local resolved (RuntimePerformance.resolve settings state))
    (assert (= resolved.control_mode "auto"))
    (assert (= resolved.manual_mode "max"))
    (assert (= resolved.effective_mode "max"))
    (assert (= resolved.source "manual"))
    (assert (= (RuntimePerformance.resolve-fps-cap settings resolved.effective_mode) 60))
    true)))

(fn manual-control-ignores-auto-rules []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (RuntimePerformance.ensure-settings-defaults settings)
    (settings.set-value "runtime_performance.control_mode" "manual" {:save? false})
    (settings.set-value "runtime_performance.manual_mode" "max" {:save? false})
    (local state (RuntimePerformance.create-state))
    (RuntimePerformance.set-minimized state true)
    (local resolved (RuntimePerformance.resolve settings state))
    (assert (= resolved.control_mode "manual"))
    (assert (= resolved.effective_mode "max"))
    (assert (= resolved.source "manual"))
    true)))

(fn minimized-override-restores-manual-mode []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (RuntimePerformance.ensure-settings-defaults settings)
    (settings.set-value "runtime_performance.control_mode" "auto" {:save? false})
    (settings.set-value "runtime_performance.manual_mode" "balanced" {:save? false})
    (local state (RuntimePerformance.create-state))
    (RuntimePerformance.set-minimized state true)
    (local minimized (RuntimePerformance.resolve settings state))
    (assert (= minimized.control_mode "auto"))
    (assert (= minimized.effective_mode "minimized"))
    (assert (= minimized.source "system"))
    (RuntimePerformance.set-minimized state false)
    (local restored (RuntimePerformance.resolve settings state))
    (assert (= restored.effective_mode "balanced"))
    (assert (= restored.source "manual"))
    true)))

(fn visibility-and-lifecycle-overrides-map-to-minimized []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (RuntimePerformance.ensure-settings-defaults settings)
    (settings.set-value "runtime_performance.control_mode" "auto" {:save? false})
    (settings.set-value "runtime_performance.manual_mode" "balanced" {:save? false})
    (local state (RuntimePerformance.create-state))

    (RuntimePerformance.set-occluded state true)
    (local r1 (RuntimePerformance.resolve settings state))
    (assert (= r1.effective_mode "minimized"))
    (RuntimePerformance.set-occluded state false)

    (RuntimePerformance.set-hidden state true)
    (local r2 (RuntimePerformance.resolve settings state))
    (assert (= r2.effective_mode "minimized"))
    (RuntimePerformance.set-hidden state false)

    (RuntimePerformance.set-suspended state true)
    (local r3 (RuntimePerformance.resolve settings state))
    (assert (= r3.effective_mode "minimized"))
    (RuntimePerformance.set-suspended state false)

    (RuntimePerformance.set-screen-locked state true)
    (local r4 (RuntimePerformance.resolve settings state))
    (assert (= r4.effective_mode "minimized"))
    (RuntimePerformance.set-screen-locked state false)

    (local restored (RuntimePerformance.resolve settings state))
    (assert (= restored.effective_mode "balanced"))
    (assert (= restored.source "manual"))
    true)))

(fn minimized-class-latches-while-unfocused []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (RuntimePerformance.ensure-settings-defaults settings)
    (settings.set-value "runtime_performance.control_mode" "auto" {:save? false})
    (settings.set-value "runtime_performance.manual_mode" "balanced" {:save? false})
    (local state (RuntimePerformance.create-state))

    (RuntimePerformance.set-focused state false)
    (RuntimePerformance.set-hidden state true)
    (local first (RuntimePerformance.resolve settings state))
    (assert (= first.effective_mode "minimized"))

    ; Simulate noisy WINDOW_SHOWN while still unfocused: should remain minimized.
    (RuntimePerformance.set-hidden state false)
    (local still-minimized (RuntimePerformance.resolve settings state))
    (assert (= still-minimized.effective_mode "minimized"))
    (assert (= still-minimized.active_override "system:minimized"))

    ; Regaining focus clears latch and allows fallback to baseline.
    (RuntimePerformance.set-focused state true)
    (local restored (RuntimePerformance.resolve settings state))
    (assert (= restored.effective_mode "balanced"))
    (assert (= restored.source "manual"))
    true)))

(fn idle-rules-and-interesting-suppression []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (RuntimePerformance.ensure-settings-defaults settings)
    (settings.set-value "runtime_performance.control_mode" "auto" {:save? false})
    (settings.set-value "runtime_performance.manual_mode" "max" {:save? false})
    (settings.set-value "runtime_performance.auto.idle.unfocused_after_seconds" 60 {:save? false})
    (settings.set-value "runtime_performance.auto.idle.minimized_after_seconds" 600 {:save? false})
    (local state (RuntimePerformance.create-state))

    (RuntimePerformance.note-input state 0)
    (RuntimePerformance.update-idle-state settings state 61)
    (local idle-unfocused (RuntimePerformance.resolve settings state))
    (assert (= idle-unfocused.effective_mode "unfocused"))
    (assert (= idle-unfocused.active_override "idle:unfocused"))

    (RuntimePerformance.update-idle-state settings state 601)
    (local focused-idle (RuntimePerformance.resolve settings state))
    (assert (= focused-idle.effective_mode "unfocused"))
    (assert (= focused-idle.active_override "idle:unfocused"))

    (RuntimePerformance.set-focused state false)
    (RuntimePerformance.update-idle-state settings state 601)
    (local idle-minimized (RuntimePerformance.resolve settings state))
    (assert (= idle-minimized.effective_mode "minimized"))
    (assert (= idle-minimized.active_override "idle:minimized"))

    (RuntimePerformance.activate-gameplay-lease settings state "demo")
    (RuntimePerformance.update-idle-state settings state 601)
    (local interesting (RuntimePerformance.resolve settings state))
    (assert (= interesting.effective_mode "max"))
    (assert (= interesting.source "rule:gameplay"))

    (RuntimePerformance.note-input state 602)
    (RuntimePerformance.clear-gameplay-lease state "demo")
    (RuntimePerformance.set-focused state true)
    (RuntimePerformance.update-idle-state settings state 602)
    (local resumed (RuntimePerformance.resolve settings state))
    (assert (= resumed.effective_mode "max"))
    (assert (= resumed.source "manual"))
    true)))

(fn idle-minimized-does-not-apply-while-focused []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (RuntimePerformance.ensure-settings-defaults settings)
    (settings.set-value "runtime_performance.control_mode" "auto" {:save? false})
    (settings.set-value "runtime_performance.manual_mode" "max" {:save? false})
    (settings.set-value "runtime_performance.auto.idle.unfocused_after_seconds" 60 {:save? false})
    (settings.set-value "runtime_performance.auto.idle.minimized_after_seconds" 600 {:save? false})
    (local state (RuntimePerformance.create-state))

    (RuntimePerformance.set-focused state true)
    (RuntimePerformance.note-input state 0)
    (RuntimePerformance.update-idle-state settings state 601)
    (local focused-idle (RuntimePerformance.resolve settings state))
    (assert (= focused-idle.effective_mode "unfocused"))
    (assert (= focused-idle.active_override "idle:unfocused"))

    (RuntimePerformance.set-focused state false)
    (RuntimePerformance.update-idle-state settings state 601)
    (local unfocused-idle (RuntimePerformance.resolve settings state))
    (assert (= unfocused-idle.effective_mode "minimized"))
    (assert (= unfocused-idle.active_override "idle:minimized"))
    true)))

(fn battery-and-video-rules-prioritize-and-restore []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (RuntimePerformance.ensure-settings-defaults settings)
    (settings.set-value "runtime_performance.control_mode" "auto" {:save? false})
    (settings.set-value "runtime_performance.manual_mode" "max" {:save? false})
    (local state (RuntimePerformance.create-state))

    (RuntimePerformance.set-on-battery state true)
    (local on-battery (RuntimePerformance.resolve settings state))
    (assert (= on-battery.effective_mode "balanced"))
    (assert (= on-battery.active_override "system:on_battery"))

    (RuntimePerformance.set-video-playback state true)
    (local video-active (RuntimePerformance.resolve settings state))
    (assert (= video-active.effective_mode "max"))
    (assert (= video-active.active_override "system:video_playback"))

    (RuntimePerformance.set-video-playback state false)
    (local back-to-battery (RuntimePerformance.resolve settings state))
    (assert (= back-to-battery.effective_mode "balanced"))
    (assert (= back-to-battery.active_override "system:on_battery"))

    (RuntimePerformance.set-on-battery state false)
    (local back-to-manual (RuntimePerformance.resolve settings state))
    (assert (= back-to-manual.effective_mode "max"))
    (assert (= back-to-manual.source "manual"))
    true)))

(fn auto-enabled-false-disables-all-auto-sources []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (RuntimePerformance.ensure-settings-defaults settings)
    (settings.set-value "runtime_performance.control_mode" "auto" {:save? false})
    (settings.set-value "runtime_performance.manual_mode" "balanced" {:save? false})
    (settings.set-value "runtime_performance.auto.enabled" false {:save? false})
    (local state (RuntimePerformance.create-state))

    (RuntimePerformance.set-minimized state true)
    (RuntimePerformance.set-on-battery state true)
    (RuntimePerformance.set-video-playback state true)
    (RuntimePerformance.activate-lease state {:id "manual-test-lease"
                                              :target_mode "max"
                                              :priority 999
                                              :source "test"})
    (RuntimePerformance.note-input state 0)
    (RuntimePerformance.update-idle-state settings state 601)
    (local resolved (RuntimePerformance.resolve settings state))
    (assert (= resolved.effective_mode "balanced"))
    (assert (= resolved.source "manual"))
    (assert (= resolved.active_override nil))
    true)))

(fn unfocused-on-battery-prefers-unfocused-cap []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (RuntimePerformance.ensure-settings-defaults settings)
    (settings.set-value "runtime_performance.control_mode" "auto" {:save? false})
    (settings.set-value "runtime_performance.manual_mode" "max" {:save? false})
    (local state (RuntimePerformance.create-state))

    (RuntimePerformance.set-on-battery state true)
    (local focused-battery (RuntimePerformance.resolve settings state))
    (assert (= focused-battery.effective_mode "balanced"))
    (assert (= focused-battery.active_override "system:on_battery"))

    (RuntimePerformance.set-focused state false)
    (local unfocused-battery (RuntimePerformance.resolve settings state))
    (assert (= unfocused-battery.effective_mode "unfocused"))
    (assert (= unfocused-battery.active_override "system:unfocused"))
    (assert (= (RuntimePerformance.resolve-fps-cap settings unfocused-battery.effective_mode) 12))

    (RuntimePerformance.set-focused state true)
    (local restored-focus (RuntimePerformance.resolve settings state))
    (assert (= restored-focus.effective_mode "balanced"))
    (assert (= restored-focus.active_override "system:on_battery"))
    true)))

(fn battery-rule-can-be-disabled []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (RuntimePerformance.ensure-settings-defaults settings)
    (settings.set-value "runtime_performance.control_mode" "auto" {:save? false})
    (settings.set-value "runtime_performance.manual_mode" "max" {:save? false})
    (settings.set-value "runtime_performance.auto.system.on_battery.enabled" false {:save? false})
    (local state (RuntimePerformance.create-state))
    (RuntimePerformance.set-on-battery state true)
    (local resolved (RuntimePerformance.resolve settings state))
    (assert (= resolved.effective_mode "max"))
    (assert (= resolved.source "manual"))
    true)))

(fn lease-override-and-clear []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (RuntimePerformance.ensure-settings-defaults settings)
    (settings.set-value "runtime_performance.control_mode" "auto" {:save? false})
    (settings.set-value "runtime_performance.manual_mode" "balanced" {:save? false})
    (local state (RuntimePerformance.create-state))
    (RuntimePerformance.activate-lease state {:id "world-game"
                                              :target_mode "max"
                                              :priority 900
                                              :source "rule"})
    (local leased (RuntimePerformance.resolve settings state))
    (assert (= leased.effective_mode "max"))
    (assert (= leased.active_override "world-game"))
    (assert (= leased.source "rule"))
    (RuntimePerformance.clear-lease state "world-game")
    (local cleared (RuntimePerformance.resolve settings state))
    (assert (= cleared.effective_mode "balanced"))
    (assert (= cleared.source "manual"))
    true)))

(fn gameplay-lease-uses-shared-rule-settings []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (RuntimePerformance.ensure-settings-defaults settings)
    (settings.set-value "runtime_performance.control_mode" "auto" {:save? false})
    (settings.set-value "runtime_performance.manual_mode" "balanced" {:save? false})
    (settings.set-value "runtime_performance.auto.rules.gameplay.target_mode" "max" {:save? false})
    (settings.set-value "runtime_performance.auto.rules.gameplay.priority" 945 {:save? false})
    (local state (RuntimePerformance.create-state))
    (local lease (RuntimePerformance.activate-gameplay-lease settings state "demo"))
    (assert lease "gameplay lease should activate when enabled")
    (assert (= lease.id "rule:gameplay:demo"))
    (assert (= lease.priority 945))
    (assert (= lease.target_mode "max"))
    (local resolved (RuntimePerformance.resolve settings state))
    (assert (= resolved.effective_mode "max"))
    (RuntimePerformance.clear-gameplay-lease state "demo")
    (local cleared (RuntimePerformance.resolve settings state))
    (assert (= cleared.effective_mode "balanced"))
    true)))

(fn apply-settings-drives-engine-cap []
  (with-temp-dir (fn [root]
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (RuntimePerformance.ensure-settings-defaults settings)
    (settings.set-value "runtime_performance.control_mode" "auto" {:save? false})
    (local state (RuntimePerformance.create-state))
    (local captured {:fps nil :input nil :requests 0})
    (local engine {:set-target-fps (fn [fps] (set captured.fps fps))
                   :set-input-paused (fn [paused] (set captured.input paused))
                   :request-frame (fn []
                                    (set captured.requests (+ captured.requests 1))
                                    true)})
    (local r1 (RuntimePerformance.apply-settings settings state engine))
    (assert (= captured.fps 60))
    (assert (= captured.input false))
    (assert (= r1.pause_physics false))
    (assert (= r1.pause_ui false))
    (RuntimePerformance.set-minimized state true)
    (local r2 (RuntimePerformance.apply-settings settings state engine))
    (assert (= captured.fps 0))
    (assert (= captured.input true))
    (assert (= r2.pause_physics true))
    (assert (= r2.pause_ui true))
    (settings.set-value "runtime_performance.modes.minimized.pause_physics" false {:save? false})
    (settings.set-value "runtime_performance.modes.minimized.pause_input" false {:save? false})
    (settings.set-value "runtime_performance.modes.minimized.pause_ui" false {:save? false})
    (local r3 (RuntimePerformance.apply-settings settings state engine))
    (assert (= captured.input false))
    (assert (= r3.pause_physics false))
    (assert (= r3.pause_ui false))
    (RuntimePerformance.set-minimized state false)
    (local r4 (RuntimePerformance.apply-settings settings state engine))
    (assert (= captured.fps 60))
    (assert (= captured.input false))
    (assert (= r4.pause_physics false))
    (assert (= r4.pause_ui false))
    (assert (= captured.requests 1))
    true)))

(table.insert tests {:name "manual mode defaults to max" :fn manual-mode-defaults-to-max})
(table.insert tests {:name "manual control ignores auto rules" :fn manual-control-ignores-auto-rules})
(table.insert tests {:name "minimized override restores manual mode" :fn minimized-override-restores-manual-mode})
(table.insert tests {:name "visibility/lifecycle overrides map to minimized"
                     :fn visibility-and-lifecycle-overrides-map-to-minimized})
(table.insert tests {:name "minimized class latches while unfocused"
                     :fn minimized-class-latches-while-unfocused})
(table.insert tests {:name "idle rules and interesting suppression"
                     :fn idle-rules-and-interesting-suppression})
(table.insert tests {:name "idle minimized does not apply while focused"
                     :fn idle-minimized-does-not-apply-while-focused})
(table.insert tests {:name "battery and video rules prioritize and restore"
                     :fn battery-and-video-rules-prioritize-and-restore})
(table.insert tests {:name "unfocused on battery prefers unfocused cap"
                     :fn unfocused-on-battery-prefers-unfocused-cap})
(table.insert tests {:name "battery rule can be disabled"
                     :fn battery-rule-can-be-disabled})
(table.insert tests {:name "auto.enabled false disables all auto sources"
                     :fn auto-enabled-false-disables-all-auto-sources})
(table.insert tests {:name "lease override and clear" :fn lease-override-and-clear})
(table.insert tests {:name "gameplay lease uses shared rule settings"
                     :fn gameplay-lease-uses-shared-rule-settings})
(table.insert tests {:name "apply-settings drives engine fps cap" :fn apply-settings-drives-engine-cap})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "runtime-performance"
                       :tests tests})))

{:name "runtime-performance"
 :tests tests
 :main main}
