(local aubio-stream (require :aubio/helpers/stream))
(local audio-input (require :audio-input))
(local disable-audio (= (os.getenv "SPACE_DISABLE_AUDIO") "1"))
(local run-audio-tests (= (os.getenv "SPACE_TEST_AUDIO_INPUT") "1"))

(fn test-stream-from-source []
  (assert (and app app.engine) "app.engine missing")
  (local hop 512)
  (local path (app.engine.get-asset-path "sounds/on.wav"))
  (local stream (aubio-stream.from-source {:uri path
                                           :hop hop}))
  (local source (. stream :source))
  (local (read buf) ((. stream :iter)))
  (assert (> read 0) "expected stream to read frames")
  (assert (= (buf:length) hop) "expected buffer length to match hop")
  (source:close))

(fn test-stream-from-source-loop []
  (assert (and app app.engine) "app.engine missing")
  (local hop 512)
  (local path (app.engine.get-asset-path "sounds/on.wav"))
  (local stream (aubio-stream.from-source {:uri path
                                           :hop hop
                                           :loop true}))
  (local source (. stream :source))
  (source:seek (source:duration))
  (local (read _buf) ((. stream :iter)))
  (assert (> read 0) "expected loop stream to restart after EOF")
  (source:close))

(fn test-stream-from-audio-input []
  (local device (audio-input.default-input-device))
  (if (not device)
      true
      (do
        (local input (audio-input.AudioInput {:device device
                                              :channels 1
                                              :sample-rate 44100
                                              :frames-per-buffer 256
                                              :buffer-seconds 0.5}))
        (input:start)
        (local stream (aubio-stream.from-audio-input {:input input
                                                      :frames 128
                                                      :gain 1.0}))
        (local (read buf) ((. stream :iter)))
        (assert (>= read 0) "expected audio input stream read")
        (assert (= (buf:length) 128) "expected buffer length to match frames")
        (input:stop))))

(local tests
  (if disable-audio
      []
      (if run-audio-tests
          [{:name "aubio stream from source" :fn test-stream-from-source}
           {:name "aubio stream from source loop" :fn test-stream-from-source-loop}
           {:name "aubio stream from audio input" :fn test-stream-from-audio-input}]
          [{:name "aubio stream from source" :fn test-stream-from-source}
           {:name "aubio stream from source loop" :fn test-stream-from-source-loop}])))

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "aubio-stream"
                       :tests tests})))

{:name "aubio-stream"
 :tests tests
 :main main}
