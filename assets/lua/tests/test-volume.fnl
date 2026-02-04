(local glm (require :glm))
(local Hud (require :hud))
(local VolumeControl (require :volume-control))
(local BuildContext (require :build-context))
(local Settings (require :settings))
(local fs (require :fs))
(local MathUtils (require :math-utils))

(local approx (. MathUtils :approx))

(var temp-counter 0)
(local volume-temp-root (fs.join-path "/tmp/space/tests" "volume-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path volume-temp-root (.. "volume-test-" (os.time) "-" temp-counter)))

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

 

(fn make-vector-buffer []
  (local state {:allocate 0
                :delete 0})
  (local buffer {:state state})
  (set buffer.allocate (fn [_self _count]
                         (set state.allocate (+ state.allocate 1))
                         state.allocate))
  (set buffer.delete (fn [_self _handle]
                       (set state.delete (+ state.delete 1))))
  (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
  (set buffer.set-float (fn [_self _handle _offset _value] nil))
  buffer)

(fn make-test-ctx []
  (local triangle (make-vector-buffer))
  (local text-buffer (make-vector-buffer))
  (local ctx (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                            :hoverables (assert app.hoverables "test requires app.hoverables")}))
  (set ctx.triangle-vector triangle)
  (set ctx.pointer-target {})
  (set ctx.get-text-vector (fn [_self _font] text-buffer))
  ctx)

(fn make-icons-stub []
  (local glyph {:advance 1
                :planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {}})
  (local stub {:font font
               :codepoints {}})
  (fn set-codepoint [name value]
    (set (. stub.codepoints name) value)
    (set (. font.glyph-map value) glyph))
  (set-codepoint :volume_mute 4101)
  (set-codepoint :volume_down 4102)
  (set-codepoint :volume_up 4103)
  (set-codepoint :volume_off 4104)
  (set stub.get
       (fn [self name]
         (local value (. self.codepoints name))
         (assert value (.. "Missing icon " name))
         value))
  (set stub.resolve
       (fn [self name]
         (local code (self:get name))
         {:type :font
          :codepoint code
          :font self.font}))
  stub)

(fn icon-name [button icons]
  (local codes (and button.text button.text.child (button.text.child:get-codepoints)))
  (local code (and codes (. codes 1)))
  (var name nil)
  (when (and code icons icons.codepoints)
    (each [label value (pairs icons.codepoints)]
      (when (= value code)
        (set name label))))
  name)

(fn master-volume-clamps []
  (local audio app.engine.audio)
  (assert audio "Audio binding missing")
  (local original (or (and audio.getMasterVolume (audio:getMasterVolume)) 1.0))
  (audio:setMasterVolume 0.7)
  (assert (approx (audio:getMasterVolume) 0.7))
  (audio:setMasterVolume -1.0)
  (assert (approx (audio:getMasterVolume) 0.0))
  (audio:setMasterVolume 2.0)
  (assert (approx (audio:getMasterVolume) 1.0))
  (audio:setMasterVolume original))

(fn volume-button-updates-icon-and-scrolls []
  (local audio app.engine.audio)
  (assert audio "Audio binding missing")
  (local original (or (and audio.getMasterVolume (audio:getMasterVolume)) 1.0))
  (audio:setMasterVolume 0.0)
  (local icons (make-icons-stub))
  (local ctx (make-test-ctx))
  (set ctx.icons icons)
  (local button ((VolumeControl.make-volume-button) ctx))
  (assert (= (icon-name button icons) "volume_mute"))

  (button:on-mouse-wheel {:x 0 :y 1})
  (assert (approx (audio:getMasterVolume) 0.05))
  (assert (= (icon-name button icons) "volume_down"))

  (button:on-mouse-wheel {:x 0 :y 20})
  (assert (approx (audio:getMasterVolume) 1.0))
  (assert (= (icon-name button icons) "volume_up"))

  (when button.drop
    (button:drop))
  (audio:setMasterVolume original))

(fn volume-button-toggle-mutes-and-restores []
  (local audio app.engine.audio)
  (assert audio "Audio binding missing")
  (local original (or (and audio.getMasterVolume (audio:getMasterVolume)) 1.0))
  (audio:setMasterVolume 0.4)
  (local icons (make-icons-stub))
  (local ctx (make-test-ctx))
  (set ctx.icons icons)
  (local button ((VolumeControl.make-volume-button) ctx))
  (assert (approx (audio:getMasterVolume) 0.4))
  (assert (= (icon-name button icons) "volume_down"))

  (button:on-click {})
  (assert (approx (audio:getMasterVolume) 0.0))
  (assert (= (icon-name button icons) "volume_off"))

  (button:on-click {})
  (assert (approx (audio:getMasterVolume) 0.4))
  (assert (= (icon-name button icons) "volume_down"))

  (when button.drop
    (button:drop))
  (audio:setMasterVolume original))

(fn volume-settings-roundtrip []
  (local audio app.engine.audio)
  (assert audio "Audio binding missing")
  (local original (or (and audio.getMasterVolume (audio:getMasterVolume)) 1.0))
  (with-temp-dir (fn [root]
    (VolumeControl.apply-settings {:volume 0.4 :muted? false})
    (local stored-before (VolumeControl.get-stored-volume))
    (assert (approx stored-before 0.4)
            (.. "expected stored volume 0.4 got " (tostring stored-before)))
    (local settings (Settings {:config-dir root :filename "settings.toml"}))
    (settings.set-value "audio.volume" (VolumeControl.get-stored-volume) {:save? false})
    (settings.set-value "audio.muted" (VolumeControl.get-muted?) {:save? false})
    (settings.save)
    (local content (fs.read-file (fs.join-path root "settings.toml")))
    (assert (string.find content "0.4" 1 true)
            (.. "expected settings file to contain 0.4, got: " content))
    (local reload (Settings {:config-dir root :filename "settings.toml"}))
    (local stored (reload.get-value "audio.volume" nil))
    (assert (approx stored 0.4)
            (.. "expected 0.4 got " (tostring stored)))
    (local muted (reload.get-value "audio.muted" nil))
    (assert (= muted false) "expected muted to be false")))
  (audio:setMasterVolume original))

(local tests [
 {:name "Audio master volume clamps" :fn master-volume-clamps}
 {:name "Volume button updates icon and scrolls" :fn volume-button-updates-icon-and-scrolls}
 {:name "Volume button toggles mute and restores previous volume" :fn volume-button-toggle-mutes-and-restores}
 {:name "Volume settings roundtrip preserves floats" :fn volume-settings-roundtrip}
])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "volume"
                       :tests tests})))

{:name "volume"
 :tests tests
 :main main}
