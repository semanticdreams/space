(local audio-input (require :audio-input))
(local disable-audio (= (os.getenv "SPACE_DISABLE_AUDIO") "1"))

(fn list-devices-returns-tables []
  (local devices (audio-input.list-devices))
  (assert (= (type devices) "table") "devices should be a table")
  (each [_ device (ipairs devices)]
    (assert (= (type device) "table") "device entry should be a table")
    (assert (not (= device.index nil)) "device should include index")
    (assert (not (= device.name nil)) "device should include name")))

(fn invalid-channels-error []
  (local (ok err)
    (pcall (fn []
             (audio-input.AudioInput {:channels 0}))))
  (assert (not ok) "channels <= 0 should error")
  (assert (and err (string.find (tostring err) "channels" 1 true))
          "error should mention channels"))

(fn start-stop-default-device []
  (if (not (os.getenv "SPACE_TEST_AUDIO_INPUT"))
      true
      (do
        (local device (audio-input.default-input-device))
        (if (not device)
            true
            (do
              (local input
                (audio-input.AudioInput {:device device
                                         :channels 1
                                         :sample-rate 44100
                                         :frames-per-buffer 256
                                         :buffer-seconds 0.5}))
              (assert (input:start) "start should return true")
              (assert (input:running?) "input should report running")
              (assert (>= (input:available-frames) 0) "available should be >= 0")
              (local samples (input:read-frames 128))
              (assert (= (type samples) "table") "read-frames should return a table")
              (when (> (# samples) 0)
                (assert (= (% (# samples) (input:channels)) 0)
                        "samples should be interleaved by channel"))
              (input:stop)
              (assert (not (input:running?)) "input should stop"))))))

(local tests
  (if disable-audio
      []
      [{:name "audio input lists devices" :fn list-devices-returns-tables}
       {:name "audio input rejects invalid channels" :fn invalid-channels-error}
       {:name "audio input starts and stops" :fn start-stop-default-device}]))

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "audio-input"
                       :tests tests})))

{:name "audio-input"
 :tests tests
 :main main}
