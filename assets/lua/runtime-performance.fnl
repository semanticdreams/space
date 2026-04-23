(local default-settings
  {:runtime_performance {:control_mode "auto"
                         :manual_mode "max"
                         :restore_manual_on_clear true
                         :screensaver {:inhibit_mode "interesting_activity"}
                         :modes {:max {:fps_cap 60
                                       :pause_physics false
                                       :pause_input false
                                       :pause_ui false}
                                 :balanced {:fps_cap 30
                                            :pause_physics false
                                            :pause_input false
                                            :pause_ui false}
                                 :unfocused {:fps_cap 12
                                             :pause_physics false
                                             :pause_input false
                                             :pause_ui false}
                                 :minimized {:fps_cap 0
                                             :pause_physics true
                                             :pause_input true
                                             :pause_ui true}}
                         :auto {:enabled true
                                :system {:unfocused {:enabled true
                                                     :priority 890
                                                     :target_mode "unfocused"}
                                         :on_battery {:enabled true
                                                      :priority 880
                                                      :target_mode "balanced"}
                                         :video_playback {:enabled true
                                                          :priority 950
                                                          :target_mode "max"}
                                         :minimized {:enabled true
                                                     :priority 1000
                                                     :target_mode "minimized"}
                                         :occluded {:enabled true
                                                    :priority 1000
                                                    :target_mode "minimized"}
                                         :hidden {:enabled true
                                                  :priority 1000
                                                  :target_mode "minimized"}
                                         :suspended {:enabled true
                                                     :priority 1000
                                                     :target_mode "minimized"}
                                         :screen_locked {:enabled true
                                                         :priority 1000
                                                         :target_mode "minimized"}
                                         ; Exposed for future wiring.
                                         :resizing {:enabled false
                                                    :priority 800
                                                    :target_mode "max"}
                                         :moving {:enabled false
                                                  :priority 800
                                                  :target_mode "max"}
                                         :fullscreen {:enabled false
                                                      :priority 850
                                                      :target_mode "max"}
                                         :power_saver {:enabled false
                                                       :priority 900
                                                       :target_mode "balanced"}}
                                :idle {:enabled true
                                       :unfocused_after_seconds 60
                                       :unfocused_priority 650
                                       :unfocused_target_mode "unfocused"
                                       :minimized_after_seconds 600
                                       :minimized_priority 980
                                       :minimized_target_mode "minimized"}
                                :rules {:gameplay {:enabled true
                                                   :priority 940
                                                   :target_mode "max"}}}}})
(local default-system-rules
  (. (. (. default-settings :runtime_performance) :auto) :system))

(fn get-setting [settings key fallback]
  (if (and settings settings.get-value)
      (settings.get-value key fallback)
      fallback))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn sanitize-bool [value fallback]
  (if (= (type value) :boolean)
      value
      fallback))

(fn sanitize-priority [value fallback]
  (if (finite-number? value)
      (math.floor value)
      fallback))

(fn normalize-mode [mode]
  (if (= mode "max")
      "max"
      (= mode "balanced")
      "balanced"
      (= mode "unfocused")
      "unfocused"
      (= mode "minimized")
      "minimized"
      "max"))

(fn normalize-control-mode [mode]
  (if (= mode "auto")
      "auto"
      "manual"))

(fn normalize-screensaver-inhibit-mode [mode]
  (if (= mode "always")
      "always"
      (= mode "never")
      "never"
      "interesting_activity"))

(fn sanitize-fps-cap [value fallback]
  (if (finite-number? value)
      (math.max 0 (math.min 240 (math.floor value)))
      fallback))

(fn mode-default-fps [mode]
  (local modes (. (. default-settings :runtime_performance) :modes))
  (local mode-settings (. modes mode))
  (. mode-settings :fps_cap))

(fn resolve-manual-mode [settings]
  (normalize-mode
    (get-setting settings "runtime_performance.manual_mode" "max")))

(fn resolve-control-mode [settings]
  (normalize-control-mode
    (get-setting settings "runtime_performance.control_mode" "auto")))

(fn resolve-screensaver-inhibit-mode [settings]
  (normalize-screensaver-inhibit-mode
    (get-setting settings
                 "runtime_performance.screensaver.inhibit_mode"
                 "interesting_activity")))

(fn auto-enabled? [settings]
  (sanitize-bool (get-setting settings "runtime_performance.auto.enabled" true) true))

(fn resolve-fps-cap [settings mode]
  (local default-cap (mode-default-fps mode))
  (sanitize-fps-cap
    (get-setting settings
                 (.. "runtime_performance.modes." mode ".fps_cap")
                 default-cap)
    default-cap))

(fn resolve-pause-physics [settings mode]
  (local default-value
    (if (= mode "minimized")
        true
        false))
  (sanitize-bool
    (get-setting settings
                 (.. "runtime_performance.modes." mode ".pause_physics")
                 default-value)
    default-value))

(fn resolve-pause-input [settings mode]
  (local default-value
    (if (= mode "minimized")
        true
        false))
  (sanitize-bool
    (get-setting settings
                 (.. "runtime_performance.modes." mode ".pause_input")
                 default-value)
    default-value))

(fn resolve-pause-ui [settings mode]
  (local default-value
    (if (= mode "minimized")
        true
        false))
  (sanitize-bool
    (get-setting settings
                 (.. "runtime_performance.modes." mode ".pause_ui")
                 default-value)
    default-value))

(fn parse-system-rule [settings rule-name]
  (local base (.. "runtime_performance.auto.system." rule-name))
  (local default-rule (. default-system-rules rule-name))
  (local fallback-enabled
    (if default-rule
        (sanitize-bool (. default-rule :enabled) true)
        true))
  (local fallback-priority
    (if default-rule
        (sanitize-priority (. default-rule :priority) 700)
        700))
  (local fallback-target
    (if default-rule
        (normalize-mode (. default-rule :target_mode))
        "max"))
  {:id (.. "system:" rule-name)
   :source "system"
   :enabled (sanitize-bool (get-setting settings (.. base ".enabled") fallback-enabled) fallback-enabled)
   :priority (sanitize-priority (get-setting settings (.. base ".priority") fallback-priority)
                                fallback-priority)
   :target_mode (normalize-mode (get-setting settings (.. base ".target_mode") fallback-target))})

(fn has-active-gameplay-lease? [state]
  (each [_ lease (pairs state.leases)]
    (when (and lease lease.active (= (or lease.source "") "rule:gameplay"))
      (lua "return true")))
  false)

(fn has-interesting-activity? [state]
  (or state.system.video_playback
      (has-active-gameplay-lease? state)))

(fn should-inhibit-screensaver [settings state]
  (assert state "runtime-performance.should-inhibit-screensaver requires state")
  (local mode (resolve-screensaver-inhibit-mode settings))
  (if (= mode "always")
      true
      (= mode "never")
      false
      (has-interesting-activity? state)))

(fn idle-unfocused-after-seconds [settings]
  (sanitize-priority
    (get-setting settings "runtime_performance.auto.idle.unfocused_after_seconds" 60)
    60))

(fn idle-minimized-after-seconds [settings]
  (sanitize-priority
    (get-setting settings "runtime_performance.auto.idle.minimized_after_seconds" 600)
    600))

(fn idle-enabled? [settings]
  (sanitize-bool (get-setting settings "runtime_performance.auto.idle.enabled" true) true))

(fn normalize-idle-stage [stage]
  (if (= stage "idle_minimized")
      "idle_minimized"
      (= stage "idle_unfocused")
      "idle_unfocused"
      (= stage "suppressed")
      "suppressed"
      "active"))

(fn ensure-idle-state [state now-seconds]
  (if (not state.idle)
      (set state.idle {:last_input_seconds now-seconds
                       :stage "active"}))
  state.idle)

(fn resolve-idle-stage [settings state now-seconds]
  (if (not (idle-enabled? settings))
      "active"
      (if (has-interesting-activity? state)
          "suppressed"
          (do
            (local idle-state (ensure-idle-state state now-seconds))
            (local idle-seconds (math.max 0 (- now-seconds idle-state.last_input_seconds)))
            (local minimized-after (math.max 1 (idle-minimized-after-seconds settings)))
            (local unfocused-after (math.max 1 (idle-unfocused-after-seconds settings)))
            (if (>= idle-seconds minimized-after)
                (if state.system.focused
                    "idle_unfocused"
                    "idle_minimized")
                (if (>= idle-seconds unfocused-after)
                    "idle_unfocused"
                    "active"))))))

(fn update-idle-state [settings state now-seconds]
  (assert state "runtime-performance.update-idle-state requires state")
  (local now (or now-seconds (os.clock)))
  (local idle-state (ensure-idle-state state now))
  (local next-stage (resolve-idle-stage settings state now))
  (local normalized (normalize-idle-stage next-stage))
  (if (= idle-state.stage normalized)
      false
      (do
        (set idle-state.stage normalized)
        true)))

(fn note-input [state now-seconds]
  (assert state "runtime-performance.note-input requires state")
  (local now (or now-seconds (os.clock)))
  (local idle-state (ensure-idle-state state now))
  (set idle-state.last_input_seconds now)
  (if (= idle-state.stage "active")
      false
      (do
        (set idle-state.stage "active")
        true)))

(fn minimized-class-active? [state raw-flag]
  (or raw-flag
      (and (not state.system.focused)
           state.system.minimized_class_latched)))

(fn system-rule-active? [state rule-name]
  (if (= rule-name "unfocused")
      (and (not state.system.minimized)
           (not state.system.occluded)
           (not state.system.hidden)
           (not state.system.suspended)
           (not state.system.screen_locked)
           (not state.system.minimized_class_latched)
           (not state.system.focused))
      (= rule-name "minimized")
      (minimized-class-active? state state.system.minimized)
      (= rule-name "occluded")
      (minimized-class-active? state state.system.occluded)
      (= rule-name "hidden")
      (minimized-class-active? state state.system.hidden)
      (= rule-name "suspended")
      (minimized-class-active? state state.system.suspended)
      (= rule-name "screen_locked")
      (minimized-class-active? state state.system.screen_locked)
      (= rule-name "on_battery")
      state.system.on_battery
      (= rule-name "video_playback")
      state.system.video_playback
      false))

(fn append-active-system-overrides [out settings state]
  (local names ["minimized"
                "occluded"
                "hidden"
                "suspended"
                "screen_locked"
                "video_playback"
                "on_battery"
                "unfocused"])
  (each [_ name (ipairs names)]
    (local rule (parse-system-rule settings name))
    (when (and rule.enabled (system-rule-active? state name))
      (table.insert out rule))))

(fn append-active-idle-overrides [out settings state]
  (when (idle-enabled? settings)
    (local idle-state state.idle)
    (when idle-state
      (local normalized (normalize-idle-stage idle-state.stage))
      (if (= normalized "idle_minimized")
          ; Never force idle->minimized while focused; minimized mode may
          ; pause input and would prevent immediate wake on user activity.
          (when (not state.system.focused)
            (table.insert out {:id "idle:minimized"
                               :source "idle"
                               :enabled true
                               :priority (sanitize-priority
                                           (get-setting settings "runtime_performance.auto.idle.minimized_priority" 980)
                                           980)
                               :target_mode (normalize-mode
                                              (get-setting settings
                                                           "runtime_performance.auto.idle.minimized_target_mode"
                                                           "minimized"))}))
          (= normalized "idle_unfocused")
          (table.insert out {:id "idle:unfocused"
                             :source "idle"
                             :enabled true
                             :priority (sanitize-priority
                                         (get-setting settings "runtime_performance.auto.idle.unfocused_priority" 650)
                                         650)
                             :target_mode (normalize-mode
                                            (get-setting settings
                                                         "runtime_performance.auto.idle.unfocused_target_mode"
                                                         "unfocused"))})))))

(fn append-active-leases [out state]
  (each [id lease (pairs state.leases)]
    (when (and lease lease.active)
      (table.insert out {:id id
                         :source (or lease.source "lease")
                         :priority (sanitize-priority lease.priority 800)
                         :target_mode (normalize-mode lease.target_mode)
                         :order (or lease.order 0)}))))

(fn select-highest-priority [entries]
  (var best nil)
  (each [_ entry (ipairs entries)]
    (if (or (not best)
            (> entry.priority best.priority)
            (and (= entry.priority best.priority)
                 (> (or entry.order 0) (or best.order 0))))
        (set best entry)))
  best)

(fn any-minimized-class-raw-active? [system]
  (or system.minimized
      system.occluded
      system.hidden
      system.suspended
      system.screen_locked))

(fn create-state []
  {:system {:focused true
            :minimized false
            :occluded false
            :hidden false
            :suspended false
            :screen_locked false
            :on_battery false
            :video_playback false
            ; Latches minimized-class state while unfocused to avoid noisy
            ; X11/Xfce shown/exposed clears during workspace switches.
            :minimized_class_latched false}
   :leases {}
   :lease-order 0
   :last nil})

(fn set-focused [state focused?]
  (local focused (not (= focused? false)))
  (tset (. state :system) :focused focused)
  (if focused
      (tset (. state :system) :minimized_class_latched false)
      (if (any-minimized-class-raw-active? state.system)
          (tset (. state :system) :minimized_class_latched true)))
  state)

(fn set-minimized [state minimized?]
  (local minimized (not (= minimized? false)))
  (tset (. state :system) :minimized minimized)
  (when (and minimized (not state.system.focused))
    (tset (. state :system) :minimized_class_latched true))
  state)

(fn set-occluded [state occluded?]
  (local occluded (not (= occluded? false)))
  (tset (. state :system) :occluded occluded)
  (when (and occluded (not state.system.focused))
    (tset (. state :system) :minimized_class_latched true))
  state)

(fn set-hidden [state hidden?]
  (local hidden (not (= hidden? false)))
  (tset (. state :system) :hidden hidden)
  (when (and hidden (not state.system.focused))
    (tset (. state :system) :minimized_class_latched true))
  state)

(fn set-suspended [state suspended?]
  (local suspended (not (= suspended? false)))
  (tset (. state :system) :suspended suspended)
  (when (and suspended (not state.system.focused))
    (tset (. state :system) :minimized_class_latched true))
  state)

(fn set-screen-locked [state screen-locked?]
  (local screen-locked (not (= screen-locked? false)))
  (tset (. state :system) :screen_locked screen-locked)
  (when (and screen-locked (not state.system.focused))
    (tset (. state :system) :minimized_class_latched true))
  state)

(fn set-on-battery [state on-battery?]
  (tset (. state :system) :on_battery (not (= on-battery? false)))
  state)

(fn set-video-playback [state video-playback?]
  (tset (. state :system) :video_playback (not (= video-playback? false)))
  state)

(fn activate-lease [state opts]
  (assert state "runtime-performance.activate-lease requires state")
  (assert opts "runtime-performance.activate-lease requires opts")
  (local id (. opts :id))
  (assert (and (= (type id) :string) (> (# id) 0))
          "runtime-performance.activate-lease requires non-empty string :id")
  (set state.lease-order (+ state.lease-order 1))
  (tset state.leases id
       {:id id
        :active true
        :target_mode (normalize-mode (. opts :target_mode))
        :priority (sanitize-priority (. opts :priority) 800)
        :source (or (. opts :source) "lease")
        :order state.lease-order})
  (. state.leases id))

(fn clear-lease [state id]
  (assert state "runtime-performance.clear-lease requires state")
  (assert (and (= (type id) :string) (> (# id) 0))
          "runtime-performance.clear-lease requires non-empty string id")
  (tset state.leases id nil)
  true)

(fn gameplay-lease-id [id]
  (.. "rule:gameplay:" id))

(fn gameplay-rule-enabled? [settings]
  (sanitize-bool
    (get-setting settings "runtime_performance.auto.rules.gameplay.enabled" true)
    true))

(fn gameplay-rule-priority [settings]
  (sanitize-priority
    (get-setting settings "runtime_performance.auto.rules.gameplay.priority" 940)
    940))

(fn gameplay-rule-target-mode [settings]
  (normalize-mode
    (get-setting settings "runtime_performance.auto.rules.gameplay.target_mode" "max")))

(fn activate-gameplay-lease [settings state id]
  (assert settings "runtime-performance.activate-gameplay-lease requires settings")
  (assert state "runtime-performance.activate-gameplay-lease requires state")
  (assert (and (= (type id) :string) (> (# id) 0))
          "runtime-performance.activate-gameplay-lease requires non-empty string id")
  (if (not (gameplay-rule-enabled? settings))
      nil
      (activate-lease state {:id (gameplay-lease-id id)
                             :source "rule:gameplay"
                             :priority (gameplay-rule-priority settings)
                             :target_mode (gameplay-rule-target-mode settings)})))

(fn clear-gameplay-lease [state id]
  (assert state "runtime-performance.clear-gameplay-lease requires state")
  (assert (and (= (type id) :string) (> (# id) 0))
          "runtime-performance.clear-gameplay-lease requires non-empty string id")
  (clear-lease state (gameplay-lease-id id)))

(fn resolve [settings state]
  (assert state "runtime-performance.resolve requires state")
  (local control-mode (resolve-control-mode settings))
  (local manual-mode (resolve-manual-mode settings))
  (if (= control-mode "manual")
      {:control_mode control-mode
       :manual_mode manual-mode
       :effective_mode manual-mode
       :source "manual"
       :active_override nil
       :priority nil}
      (do
  (local auto-enabled (auto-enabled? settings))
  (local restore-manual?
    (sanitize-bool
      (get-setting settings "runtime_performance.restore_manual_on_clear" true)
      true))
  (local candidates [])
  (when auto-enabled
    (append-active-system-overrides candidates settings state)
    (append-active-idle-overrides candidates settings state)
    (append-active-leases candidates state))
  (local winner (select-highest-priority candidates))
  (if winner
      {:control_mode control-mode
       :manual_mode manual-mode
       :effective_mode winner.target_mode
       :source winner.source
       :active_override winner.id
       :priority winner.priority}
      (if restore-manual?
          {:control_mode control-mode
           :manual_mode manual-mode
           :effective_mode manual-mode
           :source "manual"
           :active_override nil
           :priority nil}
          {:control_mode control-mode
           :manual_mode manual-mode
           :effective_mode (or (and state.last state.last.effective_mode) manual-mode)
           :source (or (and state.last state.last.source) "manual")
           :active_override nil
           :priority nil})))))

(fn ensure-settings-defaults [settings]
  (if (and settings settings.ensure-defaults)
      (settings.ensure-defaults default-settings {:save? false})
      false))

(fn apply-settings [settings state engine]
  (local resolution (resolve settings state))
  (local fps-cap (resolve-fps-cap settings resolution.effective_mode))
  (local pause-physics (resolve-pause-physics settings resolution.effective_mode))
  (local pause-input (resolve-pause-input settings resolution.effective_mode))
  (local pause-ui (resolve-pause-ui settings resolution.effective_mode))
  (local screensaver-inhibited (should-inhibit-screensaver settings state))
  (when (and engine engine.set-target-fps)
    (engine.set-target-fps fps-cap))
  (when (and engine engine.set-input-paused)
    (engine.set-input-paused pause-input))
  (when (and engine engine.set-ui-paused)
    (engine.set-ui-paused pause-ui))
  (when (and engine engine.set-screensaver-inhibited)
    (local ok (engine.set-screensaver-inhibited screensaver-inhibited))
    (when (= ok false)
      (error "runtime-performance failed to apply screensaver inhibition")))
  (when (and engine engine.request-frame state.last (= state.last.fps_cap 0) (> fps-cap 0))
    (engine.request-frame))
  (set state.last {:manual_mode resolution.manual_mode
                   :control_mode resolution.control_mode
                   :effective_mode resolution.effective_mode
                   :source resolution.source
                   :active_override resolution.active_override
                   :priority resolution.priority
                   :fps_cap fps-cap
                   :pause_physics pause-physics
                   :pause_input pause-input
                   :pause_ui pause-ui
                   :screensaver_inhibited screensaver-inhibited})
  state.last)

{:defaults default-settings
 :normalize-mode normalize-mode
 :normalize-control-mode normalize-control-mode
 :normalize-screensaver-inhibit-mode normalize-screensaver-inhibit-mode
 :resolve-control-mode resolve-control-mode
 :resolve-manual-mode resolve-manual-mode
 :resolve-screensaver-inhibit-mode resolve-screensaver-inhibit-mode
 :resolve-fps-cap resolve-fps-cap
 :resolve-pause-physics resolve-pause-physics
 :resolve-pause-input resolve-pause-input
 :resolve-pause-ui resolve-pause-ui
 :create-state create-state
 :set-focused set-focused
 :set-minimized set-minimized
 :set-occluded set-occluded
 :set-hidden set-hidden
 :set-suspended set-suspended
 :set-screen-locked set-screen-locked
 :set-on-battery set-on-battery
 :set-video-playback set-video-playback
 :should-inhibit-screensaver should-inhibit-screensaver
 :activate-lease activate-lease
 :clear-lease clear-lease
 :activate-gameplay-lease activate-gameplay-lease
 :clear-gameplay-lease clear-gameplay-lease
 :update-idle-state update-idle-state
 :note-input note-input
 :resolve resolve
 :ensure-settings-defaults ensure-settings-defaults
 :apply-settings apply-settings}
