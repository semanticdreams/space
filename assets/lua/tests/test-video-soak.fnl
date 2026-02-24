(local Video (require :video))

(local tests [])

(fn parse-duration-seconds []
  (local raw (os.getenv "SPACE_VIDEO_SOAK_SECONDS"))
  (if (and raw (> (string.len raw) 0))
      (do
        (local parsed (tonumber raw))
        (if (and parsed (> parsed 0))
            parsed
            600.0))
      600.0))

(fn parse-sleep-seconds []
  (local raw (os.getenv "SPACE_VIDEO_SOAK_SLEEP_SECONDS"))
  (if (and raw (> (string.len raw) 0))
      (do
        (local parsed (tonumber raw))
        (if (and parsed (> parsed 0))
            parsed
            0.01))
      0.01))

(fn parse-max-recent-drift-seconds []
  (local raw (os.getenv "SPACE_VIDEO_SOAK_MAX_RECENT_DRIFT_SECONDS"))
  (if (and raw (> (string.len raw) 0))
      (do
        (local parsed (tonumber raw))
        (if (and parsed (> parsed 0))
            parsed
            0.35))
      0.35))

(fn parse-max-decode-wait-ms []
  (local raw (os.getenv "SPACE_VIDEO_SOAK_MAX_DECODE_WAIT_MS"))
  (if (and raw (> (string.len raw) 0))
      (do
        (local parsed (tonumber raw))
        (if (and parsed (>= parsed 0))
            parsed
            nil))
      nil))

(fn soak-video-clock-stability []
  (assert Video.available (or Video.missing-reason "video unavailable"))
  (local duration-seconds (parse-duration-seconds))
  (local sleep-seconds (parse-sleep-seconds))
  (local max-recent-drift-seconds (parse-max-recent-drift-seconds))
  (local max-decode-wait-ms (parse-max-decode-wait-ms))
  (local audio-disabled? (= (os.getenv "SPACE_DISABLE_AUDIO") "1"))
  (print (.. "[video-soak] duration=" duration-seconds
             "s sleep=" sleep-seconds
             "s max-recent-drift=" max-recent-drift-seconds
             " max-decode-wait-ms=" (or max-decode-wait-ms "disabled")))

  (local player
    (Video.VideoPlayer {:path "lua/tests/data/test-videos/01_baseline_h264_with_audio.mp4"
                        :autoplay true
                        :loop true
                        :muted false}))

  (local start (os.clock))
  (var last-position 0.0)
  (var max-regression 0.0)
  (var wrap-count 0)
  (var frames 0)
  (var ready-seen? false)
  (var max-recent-window-drift 0.0)
  (var max-decode-wait-ms-seen 0)
  (var saw-audio-clock? false)

  (while (< (- (os.clock) start) duration-seconds)
    (player:update 16)
    (set frames (+ frames 1))

    (local status (player:status))
    (assert (not (. status "has-error")) (.. "video soak error: " status.error))
    (when (. status "has-audio-clock")
      (set saw-audio-clock? true))
    (local recent-window-drift (. status "recent-max-av-drift-seconds"))
    (if (> recent-window-drift max-recent-window-drift)
        (set max-recent-window-drift recent-window-drift))
    (local decode-wait-ms (. status "decode-wait-ms"))
    (if (> decode-wait-ms max-decode-wait-ms-seen)
        (set max-decode-wait-ms-seen decode-wait-ms))

    (when status.ready
      (set ready-seen? true))

    (local pos (player:position))
    (local regression (- last-position pos))
    (if (> regression max-regression)
        (set max-regression regression))
    (local media-duration (player:duration))
    (local wrapped?
      (and (> media-duration 0.0)
           (> regression (* media-duration 0.6))
           (< pos (* media-duration 0.4))
           (> last-position (* media-duration 0.6))))
    (when wrapped?
      (set wrap-count (+ wrap-count 1)))
    ;; allow tiny jitter from clock quantization, but not real backward jumps
    (when (not wrapped?)
      (assert (<= regression 0.08) (.. "video soak position regressed too much: " regression)))
    (set last-position pos)

    (os.execute (.. "sleep " sleep-seconds)))

  (assert ready-seen? "video soak player never became ready")
  (assert (> frames 0) "video soak should execute at least one update frame")
  (if (and saw-audio-clock? (not audio-disabled?))
      (assert (<= max-recent-window-drift max-recent-drift-seconds)
              (.. "video soak recent drift budget exceeded: "
                  max-recent-window-drift " > " max-recent-drift-seconds))
      (print "[SKIP] video soak drift budget assertion skipped: audio clock unavailable or disabled"))
  (when max-decode-wait-ms
    (assert (<= max-decode-wait-ms-seen max-decode-wait-ms)
            (.. "video soak decode wait budget exceeded: "
                max-decode-wait-ms-seen " > " max-decode-wait-ms)))
  (print (.. "[video-soak] complete frames=" frames
             " last-position=" last-position
             " max-regression=" max-regression
             " max-recent-window-drift=" max-recent-window-drift
             " max-decode-wait-ms=" max-decode-wait-ms-seen
             " wraps=" wrap-count))
  (player:drop))

(if Video.available
    (table.insert tests {:name "video soak clock stability" :fn soak-video-clock-stability})
    (table.insert tests
                  {:name "video soak skipped when FFmpeg unavailable"
                   :fn (fn []
                         (assert (not Video.available) "video module unexpectedly available")
                         (print (.. "[SKIP] video soak: " (or Video.missing-reason "FFmpeg unavailable"))))}))

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "video-soak"
                       :tests tests})))

{:name "video-soak"
 :tests tests
 :main main}
