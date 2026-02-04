(local Button (require :button))
(local BuildContext (require :build-context))
(local Signal (require :signal))

(local volume-changed (Signal))
(local volume-changed-debounced (Signal))
(local volume-settings-changed-debounced (Signal))
(var debounce-token 0)
(var last-volume nil)
(var last-settings nil)
(var stored-volume nil)
(var stored-muted? false)
(local debounce-delay-ms 250)

(fn emit-debounced-settings []
  (volume-changed-debounced.emit last-volume)
  (when last-settings
    (volume-settings-changed-debounced.emit last-settings)))

(fn debounce-callback [token]
  (fn [_res]
    (when (= token debounce-token)
      (emit-debounced-settings))))

(fn emit-debounced []
  (assert (and app.engine app.engine.jobs app.engine.jobs.submit)
          "VolumeControl debounce requires app.engine.jobs")
  (set debounce-token (+ debounce-token 1))
  (local token debounce-token)
  (app.engine.jobs.submit
    {:kind "sleep_ms"
     :payload (tostring debounce-delay-ms)
     :callback (debounce-callback token)}))

(fn emit-volume-changed [value muted? stored]
  (set last-volume value)
  (set last-settings {:volume stored :muted? muted?})
  (volume-changed.emit value)
  (emit-debounced))

(fn clamp-volume [value]
  (math.min 1.0 (math.max 0.0 value)))

(fn current-master-volume []
  (local audio (and app.engine app.engine.audio))
  (if (and audio audio.getMasterVolume)
      (audio:getMasterVolume)
      1.0))

(fn apply-settings [opts]
  (local options (or opts {}))
  (local volume (. options :volume))
  (local muted? (. options :muted?))
  (when (not (= volume nil))
    (set stored-volume (clamp-volume volume)))
  (when (not (= muted? nil))
    (set stored-muted? (not (not muted?))))
  (when (= stored-volume nil)
    (set stored-volume (clamp-volume (current-master-volume))))
  (local audio (and app.engine app.engine.audio))
  (when (and audio audio.setMasterVolume)
    (local target (if stored-muted? 0 stored-volume))
    (audio:setMasterVolume (clamp-volume target)))
  {:volume stored-volume :muted? stored-muted?})

(fn get-stored-volume []
  stored-volume)

(fn get-muted? []
  stored-muted?)

(fn volume-icon-name [value muted?]
  (if muted?
      "volume_off"
      (let [clamped (clamp-volume value)]
        (if (<= clamped 0.0)
            "volume_mute"
            (if (< clamped 0.5)
                "volume_down"
                "volume_up")))))

(fn make-volume-button []
  (local volume-step 0.05)
  (fn build [ctx]
    (local initial-volume (or stored-volume (current-master-volume)))
    (local state {:muted? stored-muted?
                  :last-volume (math.max 0.05 initial-volume)})
    (local button-builder
      (Button {:variant :primary
               :padding [0.4 0.4]
               :icon (volume-icon-name (current-master-volume) stored-muted?)
               :name "volume-control"}))
    (local button (button-builder ctx))
    (local icon-text button.text)

    (fn set-icon [value opts]
      (local icons (and ctx ctx.icons))
      ;; icon-text is the Icon widget instance
      (when (and icon-text icons)
        (local icon-name (volume-icon-name value state.muted?))
        (when icon-text.set-icon
          (icon-text:set-icon icon-name (or opts {:mark-measure-dirty? true})))))

    (fn apply-volume [value opts]
      (local clamped (clamp-volume value))
      (local audio (and app.engine app.engine.audio))
      (when (and audio audio.setMasterVolume)
        (audio:setMasterVolume clamped))
      (when (not state.muted?)
        (set state.last-volume clamped))
      (set stored-muted? state.muted?)
      (set stored-volume state.last-volume)
      (set-icon clamped opts)
      (emit-volume-changed clamped state.muted? stored-volume)
      clamped)

    (fn adjust-volume [delta opts]
      (local current (current-master-volume))
      (local step (* delta volume-step))
      (set state.muted? false)
      (apply-volume (+ current step) opts))

    (fn toggle-mute []
      (if state.muted?
          (let [restore (or state.last-volume 1.0)]
            (set state.muted? false)
            (apply-volume restore))
          (do
            (set state.last-volume (or (and (> (current-master-volume) 0)
                                            (current-master-volume))
                                       state.last-volume
                                       1.0))
            (set state.muted? true)
            (apply-volume 0))))

    (set button.on-mouse-wheel
         (fn [_self payload]
           (local delta (or (and payload payload.y) 0))
           (if (= delta 0)
               nil
               (do
                 (adjust-volume delta)
                 true))))

    (when button.clicked
      (button.clicked.connect
        (fn [_event]
          (toggle-mute)
          true)))

    (local hud (or ctx.pointer-target {}))
    (set hud.volume-button button)
    (set-icon (current-master-volume) {:mark-measure-dirty? false})
    button))

{:make-volume-button make-volume-button
 :apply-settings apply-settings
 :get-stored-volume get-stored-volume
 :get-muted? get-muted?
 :clamp-volume clamp-volume
 :current-master-volume current-master-volume
 :volume-icon-name volume-icon-name
 :volume-changed volume-changed
 :volume-changed-debounced volume-changed-debounced
 :volume-settings-changed-debounced volume-settings-changed-debounced}
