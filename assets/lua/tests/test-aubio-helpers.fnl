(local aubio-vec (require :aubio/vec))
(local aubio-io (require :aubio/io))
(local aubio-helpers-vec (require :aubio/helpers/vec))
(local aubio-helpers-source (require :aubio/helpers/source))
(local aubio-helpers-presets (require :aubio/helpers/presets))

(fn approx= [left right eps]
  (< (math.abs (- left right)) eps))

(fn test-mixdown-equal []
  (local frames 4)
  (local matrix (aubio-vec.FMat 2 frames))
  (for [i 0 (- frames 1)]
    (matrix:set 0 i 1)
    (matrix:set 1 i 3))
  (local out (aubio-helpers-vec.mixdown-equal matrix))
  (assert (= (out:length) frames) "expected mixdown length to match input")
  (for [i 0 (- frames 1)]
    (local value (out:get i))
    (assert (approx= value 2 1e-6) (.. "expected mixdown value 2, got " (tostring value)))))

(fn test-mixdown-weighted []
  (local frames 4)
  (local matrix (aubio-vec.FMat 2 frames))
  (for [i 0 (- frames 1)]
    (matrix:set 0 i 1)
    (matrix:set 1 i 3))
  (local weights (aubio-vec.FVec 2))
  (weights:set 0 0.25)
  (weights:set 1 0.75)
  (local out (aubio-helpers-vec.mixdown-weighted matrix weights))
  (for [i 0 (- frames 1)]
    (local value (out:get i))
    (assert (approx= value 2.5 1e-6) (.. "expected weighted mixdown 2.5, got " (tostring value)))))

(fn test-normalize-peak []
  (local buffer (aubio-vec.FVec 4))
  (buffer:set 0 0.5)
  (buffer:set 1 0.25)
  (buffer:set 2 0.125)
  (buffer:set 3 0.0)
  (aubio-helpers-vec.normalize-peak buffer 1 1e-6)
  (local peak (aubio-vec.fvec-max buffer))
  (assert (approx= peak 1 1e-6) (.. "expected peak 1, got " (tostring peak))))

(fn test-normalize-rms []
  (local buffer (aubio-vec.FVec 4))
  (for [i 0 3]
    (buffer:set i 1))
  (aubio-helpers-vec.normalize-rms buffer 0.5 1e-6)
  (var sum 0)
  (for [i 0 3]
    (local value (buffer:get i))
    (set sum (+ sum (* value value))))
  (local rms (math.sqrt (/ sum 4)))
  (assert (approx= rms 0.5 1e-6) (.. "expected rms 0.5, got " (tostring rms))))

(fn test-apply-window []
  (local buffer (aubio-vec.FVec 8))
  (for [i 0 7]
    (buffer:set i 1))
  (aubio-helpers-vec.apply-window buffer "hanning")
  (var changed false)
  (for [i 0 7]
    (local value (buffer:get i))
    (when (> (math.abs (- value 1)) 1e-6)
      (set changed true)))
  (assert changed "expected window to modify buffer")
  (assert (> (aubio-vec.fvec-max buffer) 0) "expected window to preserve non-zero samples"))

(fn test-source-stream []
  (assert (and app app.engine) "app.engine missing")
  (local hop 512)
  (local path (app.engine.get-asset-path "sounds/on.wav"))
  (local source (aubio-io.Source path 0 hop))
  (local buffer (aubio-vec.FVec hop))
  (local iter (aubio-helpers-source.stream source buffer))
  (local (read buf) (iter))
  (assert (> read 0) "expected stream to read frames")
  (assert (= (buf:length) hop) "expected stream to return provided buffer")
  (source:close))

(fn test-source-loop []
  (assert (and app app.engine) "app.engine missing")
  (local hop 512)
  (local path (app.engine.get-asset-path "sounds/on.wav"))
  (local source (aubio-io.Source path 0 hop))
  (local buffer (aubio-vec.FVec hop))
  (local duration (source:duration))
  (source:seek duration)
  (local iter (aubio-helpers-source.loop source buffer))
  (local (read buf) (iter))
  (assert (> read 0) "expected loop to restart after EOF")
  (assert (= (buf:length) hop) "expected loop to return provided buffer")
  (source:close))

(fn test-presets []
  (local voice (. aubio-helpers-presets :voice))
  (local music (. aubio-helpers-presets :music))
  (assert (> (. voice :samplerate) 0) "expected voice samplerate")
  (assert (> (. voice :buf) 0) "expected voice buf size")
  (assert (> (. voice :hop) 0) "expected voice hop size")
  (assert (> (. music :samplerate) 0) "expected music samplerate")
  (assert (> (. music :buf) 0) "expected music buf size")
  (assert (> (. music :hop) 0) "expected music hop size"))

(local tests [{:name "aubio helpers mixdown equal" :fn test-mixdown-equal}
 {:name "aubio helpers mixdown weighted" :fn test-mixdown-weighted}
 {:name "aubio helpers normalize peak" :fn test-normalize-peak}
 {:name "aubio helpers normalize rms" :fn test-normalize-rms}
 {:name "aubio helpers apply window" :fn test-apply-window}
 {:name "aubio helpers source stream" :fn test-source-stream}
 {:name "aubio helpers source loop" :fn test-source-loop}
 {:name "aubio helpers presets" :fn test-presets}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "aubio-helpers"
                       :tests tests})))

{:name "aubio-helpers"
 :tests tests
 :main main}
