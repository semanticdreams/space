(local aubio-vec (require :aubio/vec))
(local aubio-io (require :aubio/io))
(local pitch-helper (require :aubio/helpers/pitch))
(local onset-helper (require :aubio/helpers/onset))
(local tempo-helper (require :aubio/helpers/tempo))

(fn fill-sine [buffer freq samplerate]
  (local buf-length (buffer:length))
  (local two-pi (* 2 math.pi))
  (for [i 0 (- buf-length 1)]
    (local t (/ i samplerate))
    (local value (math.sin (* two-pi freq t)))
    (buffer:set i value)))

(fn test-pitch-pipeline []
  (local samplerate 44100)
  (local hop 512)
  (local buf 1024)
  (local input (aubio-vec.FVec hop))
  (fill-sine input 440 samplerate)
  (local pipeline (pitch-helper.new {:method "yin"
                                     :buf buf
                                     :hop hop
                                     :samplerate samplerate}))
  (for [_ 1 12]
    (pipeline:push input))
  (local result (pipeline:result))
  (local value (. result :value))
  (assert (> value 300) (.. "expected pitch > 300Hz, got " (tostring value)))
  (assert (< value 600) (.. "expected pitch < 600Hz, got " (tostring value)))
  (assert (>= (. result :confidence) 0) "expected confidence to be non-negative"))

(fn test-onset-pipeline []
  (assert (and app app.engine) "app.engine missing")
  (local hop 512)
  (local buf 1024)
  (local path (app.engine.get-asset-path "sounds/on.wav"))
  (local source (aubio-io.Source path 0 hop))
  (local samplerate (source:samplerate))
  (local pipeline (onset-helper.new {:method "default"
                                     :buf buf
                                     :hop hop
                                     :samplerate samplerate}))
  (local input (aubio-vec.FVec hop))
  (var result nil)
  (for [_ 1 6]
    (local read (source:do input))
    (when (> read 0)
      (set result (pipeline:push input))))
  (source:close)
  (assert result "expected onset pipeline result")
  (assert (= (type (. result :onset)) "boolean") "expected onset boolean")
  (assert (= (type (. result :descriptor)) "number") "expected descriptor number")
  (assert (= (type (. result :thresholded)) "number") "expected thresholded number"))

(fn test-tempo-pipeline []
  (assert (and app app.engine) "app.engine missing")
  (local hop 512)
  (local buf 1024)
  (local path (app.engine.get-asset-path "sounds/on.wav"))
  (local source (aubio-io.Source path 0 hop))
  (local samplerate (source:samplerate))
  (local pipeline (tempo-helper.new {:method "default"
                                     :buf buf
                                     :hop hop
                                     :samplerate samplerate}))
  (local input (aubio-vec.FVec hop))
  (var result nil)
  (for [_ 1 6]
    (local read (source:do input))
    (when (> read 0)
      (set result (pipeline:push input))))
  (source:close)
  (assert result "expected tempo pipeline result")
  (assert (= (type (. result :beat)) "boolean") "expected beat boolean")
  (assert (= (type (. result :bpm)) "number") "expected bpm number")
  (assert (= (type (. result :period)) "number") "expected period number")
  (assert (= (type (. result :confidence)) "number") "expected confidence number"))

(local tests [{:name "aubio pitch pipeline" :fn test-pitch-pipeline}
 {:name "aubio onset pipeline" :fn test-onset-pipeline}
 {:name "aubio tempo pipeline" :fn test-tempo-pipeline}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "aubio-pipelines"
                       :tests tests})))

{:name "aubio-pipelines"
 :tests tests
 :main main}
