(local glm (require :glm))
(local DemoAudio {})

(fn can-attach-audio? [entity]
  (and entity app.engine app.engine.audio app.engine.get-asset-path))

(fn DemoAudio.attach [entity]
  (if (can-attach-audio? entity)
      (do
        (local audio app.engine.audio)
        (local sound-path (app.engine.get-asset-path "sounds/test.wav"))
        (when (and sound-path audio.loadSoundAsync)
          (local name "scene-demo-loop")
          (var source nil)
          (audio:loadSoundAsync
            name
            sound-path
            (fn [_loaded-name _buffer]
              (when (not source)
                (set source (audio:playSound name (glm.vec3 0 0 0) true true)))))
          (local original-drop entity.drop)
          (set entity.drop
               (fn [self]
                 (when source
                   (audio:stopSound source))
                 (when original-drop
                   (original-drop self)))))
        entity)
      entity))

DemoAudio
