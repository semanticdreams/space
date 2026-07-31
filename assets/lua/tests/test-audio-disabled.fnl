(local tests [])
(local glm (require :glm))

(fn ignore-disabled-audio-ready [_name]
  nil)

(fn disabled-audio-load-play-and-control-are-deterministic []
  (assert (= (os.getenv "SPACE_DISABLE_AUDIO") "1")
          "test-audio-disabled must run with SPACE_DISABLE_AUDIO=1")
  (local audio app.engine.audio)
  (assert audio "Audio binding missing")
  (local path (app.engine.get-asset-path "sounds/on.wav"))
  (assert (= (audio:loadSoundAsync "disabled-smoke-async" path ignore-disabled-audio-ready) false)
          "disabled audio should not queue async OpenAL loads")
  (assert (= (audio:loadSound "disabled-smoke" path) false)
          "disabled audio should not report loaded OpenAL buffers")
  (assert (= (audio:isReady "disabled-smoke") false)
          "disabled audio should not record unloaded buffers as ready")
  (local source (audio:playSound "disabled-smoke" (glm.vec3 0 0 0)))
  (assert (= source 0) "disabled audio should not create playback sources")
  (audio:stopSound source)
  (audio:setListenerPosition (glm.vec3 1 2 3))
  (audio:setListenerVelocity (glm.vec3 0 0 0))
  (audio:setSourcePosition source (glm.vec3 4 5 6))
  (audio:setSourceVelocity source (glm.vec3 0 0 0))
  (audio:setMasterVolume 0.5)
  (assert (= (audio:getMasterVolume) 0.5)
          "disabled audio should still retain master volume state")
  (audio:update 16)
  (audio:reset)
  (assert (= (audio:getMasterVolume) 0.5)
          "disabled audio reset should not discard volume preference"))

(local disabled-audio-test
  {:name "disabled audio load/play/control paths are deterministic"
   :fn disabled-audio-load-play-and-control-are-deterministic})

(table.insert tests disabled-audio-test)

(fn run-audio-disabled-tests []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "audio-disabled"
                     :tests tests}))

(local main
  run-audio-disabled-tests)

{:name "audio-disabled"
 :tests tests
 :main main}
