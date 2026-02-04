(local aubio-vec (require :aubio/vec))
(local aubio-temporal (require :aubio/temporal))
(local aubio-io (require :aubio/io))
(local aubio-utils (require :aubio/utils))

(fn fill-sine [buffer freq samplerate]
  (local buf-length (buffer:length))
  (local two-pi (* 2 math.pi))
  (for [i 0 (- buf-length 1)]
    (local t (/ i samplerate))
    (local value (math.sin (* two-pi freq t)))
    (buffer:set i value)))

(fn test-pitch-detects-sine []
  (local samplerate 44100)
  (local hop 512)
  (local buf 1024)
  (local input (aubio-vec.FVec hop))
  (local output (aubio-vec.FVec 1))
  (fill-sine input 440 samplerate)
  (local pitch (aubio-temporal.Pitch "yin" buf hop samplerate))
  (for [_ 1 12]
    (pitch:do input output))
  (local hz (output:get 0))
  (assert (> hz 300) (.. "expected pitch > 300Hz, got " (tostring hz)))
  (assert (< hz 600) (.. "expected pitch < 600Hz, got " (tostring hz))))

(fn test-source-reads-asset []
  (assert (and app app.engine) "app.engine missing")
  (local hop 512)
  (local path (app.engine.get-asset-path "sounds/on.wav"))
  (local source (aubio-io.Source path 0 hop))
  (local samplerate (source:samplerate))
  (local buf 1024)
  (local onset (aubio-temporal.Onset "default" buf hop samplerate))
  (local input (aubio-vec.FVec hop))
  (local output (aubio-vec.FVec 1))
  (local read (source:do input))
  (assert (> read 0) "expected aubio source to read frames")
  (onset:do input output)
  (source:close))

(fn test-logging-controls []
  (local log-levels (. aubio-utils :log-levels))
  (local seen [])
  (aubio-utils.log-set-level (. log-levels :err)
    (fn [level name message]
      (table.insert seen {:level level :name name :message message})))
  (local (ok err)
    (pcall (fn []
             (aubio-io.Source "/missing-aubio-source.wav" 0 256))))
  (aubio-utils.log-reset)
  (assert (not ok) "expected aubio source to fail")
  (assert (> (# seen) 0) "expected aubio log handler to receive messages"))

(local tests [{:name "aubio pitch detects sine" :fn test-pitch-detects-sine}
 {:name "aubio source reads asset" :fn test-source-reads-asset}
 {:name "aubio logging controls" :fn test-logging-controls}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "aubio"
                       :tests tests})))

{:name "aubio"
 :tests tests
 :main main}
