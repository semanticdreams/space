(local Video (require :video))

(local tests [])

(fn wait-until [predicate timeout-seconds pump]
  (local deadline (+ (os.clock) timeout-seconds))
  (while (and (not (predicate)) (< (os.clock) deadline))
    (if pump
        (pump)
        (os.execute "sleep 0.005")))
  (predicate))

(fn decode-no-audio-video-into-texture []
  (local player
    (Video.VideoPlayer {:path "lua/tests/data/test-videos/00_baseline_h264_320x240_30fps_yuv420p_noaudio.mp4"
                        :autoplay true
                        :muted true}))

  (local ready?
    (wait-until (fn [] (player:ready))
                3.0
                (fn []
                  (player:update 16)
                  (os.execute "sleep 0.005"))))
  (assert ready? "video player did not become ready within timeout")

  (local texture (player:texture))
  (assert texture.ready "video texture should be marked ready")
  (assert (> texture.width 0) "video texture width should be > 0")
  (assert (> texture.height 0) "video texture height should be > 0")
  (assert (> (player:duration) 0) "video duration should be > 0")
  (player:drop))

(fn seek-and-end-short-video []
  (local player
    (Video.VideoPlayer {:path "lua/tests/data/test-videos/11_ultra_short_250ms.mp4"
                        :autoplay false
                        :loop false
                        :muted true}))
  (player:seek 0.15)
  (player:play)
  (local ended?
    (wait-until (fn [] (player:ended))
                3.0
                (fn []
                  (player:update 16)
                  (os.execute "sleep 0.005"))))
  (assert ended? "video player did not reach ended state")
  (player:drop))

(fn decode-video-with-audio-streaming-smoke []
  (local player
    (Video.VideoPlayer {:path "lua/tests/data/test-videos/01_baseline_h264_with_audio.mp4"
                        :autoplay true
                        :muted false}))
  (local ready?
    (wait-until (fn [] (player:ready))
                3.0
                (fn []
                  (player:update 16)
                  (os.execute "sleep 0.005"))))
  (assert ready? "audio video did not become ready within timeout")
  (assert (not (player:ended)) "audio video should not be ended immediately")
  (player:drop))

(fn pause-resume-audio-video-keeps-position-stable []
  (local player
    (Video.VideoPlayer {:path "lua/tests/data/test-videos/01_baseline_h264_with_audio.mp4"
                        :autoplay true
                        :muted false}))

  (local ready?
    (wait-until (fn [] (player:ready))
                4.0
                (fn []
                  (player:update 16)
                  (os.execute "sleep 0.01"))))
  (assert ready? "pause/resume test player did not become ready")

  (local advanced?
    (wait-until (fn [] (> (player:position) 0.20))
                4.0
                (fn []
                  (player:update 16)
                  (os.execute "sleep 0.01"))))
  (assert advanced? "player position did not advance before pause")

  (player:pause)
  (local paused-pos (player:position))
  (local pause-deadline (+ (os.clock) 0.8))
  (while (< (os.clock) pause-deadline)
    (player:update 16)
    (os.execute "sleep 0.01")
    (local delta (math.abs (- (player:position) paused-pos)))
    (assert (< delta 0.05) "player position drifted while paused"))

  (player:play)
  (local resumed?
    (wait-until (fn [] (> (player:position) (+ paused-pos 0.08)))
                3.0
                (fn []
                  (player:update 16)
                  (os.execute "sleep 0.01"))))
  (assert resumed? "player did not resume progression after play")

  (player:drop))

(fn looped-short-video-wraps-and-does-not-end []
  (local player
    (Video.VideoPlayer {:path "lua/tests/data/test-videos/11_ultra_short_250ms.mp4"
                        :autoplay true
                        :loop true
                        :muted true}))

  (local ready?
    (wait-until (fn [] (player:ready))
                3.0
                (fn []
                  (player:update 16)
                  (os.execute "sleep 0.01"))))
  (assert ready? "loop test player did not become ready")

  (local duration (player:duration))
  (assert (> duration 0.0) "loop test duration should be > 0")

  (local deadline (+ (os.clock) 1.2))
  (while (< (os.clock) deadline)
    (player:update 16)
    (os.execute "sleep 0.01"))

  (assert (not (player:ended)) "looped clip should not enter ended state")
  (local pos (player:position))
  (assert (>= pos 0.0) "looped position should be non-negative")
  (assert (< pos (+ duration 0.05)) "looped position should stay within one media duration")
  (player:drop))

(fn repeated-seeks-do-not-break-readiness []
  (local player
    (Video.VideoPlayer {:path "lua/tests/data/test-videos/00_baseline_h264_320x240_30fps_yuv420p_noaudio.mp4"
                        :autoplay false
                        :loop false
                        :muted true}))

  (local has-duration?
    (wait-until (fn [] (> (player:duration) 0.0))
                3.0
                (fn []
                  (player:update 16)
                  (os.execute "sleep 0.005"))))
  (assert has-duration? "seek stress test duration did not become available")

  (local duration (player:duration))
  (local max-seek (math.max 0.0 (- duration 0.05)))
  (for [i 1 24]
    (local t (* max-seek (/ (math.fmod (* i 7) 23) 23.0)))
    (player:seek t)
    (player:play)
    (player:update 16)
    (os.execute "sleep 0.005")
    (player:pause))

  (player:play)
  (local ready?
    (wait-until (fn [] (player:ready))
                3.0
                (fn []
                  (player:update 16)
                  (os.execute "sleep 0.005"))))
  (assert ready? "seek stress test player lost readiness after repeated seeks")
  (player:drop))

(fn multiple-players-progress-concurrently []
  (local p1
    (Video.VideoPlayer {:path "lua/tests/data/test-videos/00_baseline_h264_320x240_30fps_yuv420p_noaudio.mp4"
                        :autoplay true
                        :muted true}))
  (local p2
    (Video.VideoPlayer {:path "lua/tests/data/test-videos/10_h264_all_intra.mp4"
                        :autoplay true
                        :muted true}))
  (local p3
    (Video.VideoPlayer {:path "lua/tests/data/test-videos/01_baseline_h264_with_audio.mp4"
                        :autoplay true
                        :muted true}))

  (local all-ready?
    (wait-until (fn [] (and (p1:ready) (p2:ready) (p3:ready)))
                4.0
                (fn []
                  (p1:update 16)
                  (p2:update 16)
                  (p3:update 16)
                  (os.execute "sleep 0.005"))))
  (assert all-ready? "all concurrent players should become ready")

  (assert (> (p1:position) 0.0) "player 1 should advance")
  (assert (> (p2:position) 0.0) "player 2 should advance")
  (assert (> (p3:position) 0.0) "player 3 should advance")

  (p1:drop)
  (p2:drop)
  (p3:drop))

(fn multiple-audio-players-run-and-seek []
  (if (= (os.getenv "SPACE_DISABLE_AUDIO") "1")
      (print "[SKIP] audio concurrency assertion skipped: SPACE_DISABLE_AUDIO=1")
      (do
        (local a
          (Video.VideoPlayer {:path "lua/tests/data/test-videos/01_baseline_h264_with_audio.mp4"
                              :autoplay true
                              :loop true
                              :muted false}))
        (local b
          (Video.VideoPlayer {:path "lua/tests/data/test-videos/01_baseline_h264_with_audio.mp4"
                              :autoplay true
                              :loop true
                              :muted false}))

        (local ready?
          (wait-until (fn [] (and (a:ready) (b:ready)))
                      5.0
                      (fn []
                        (a:update 16)
                        (b:update 16)
                        (os.execute "sleep 0.01"))))
        (assert ready? "audio concurrency players did not become ready")

        (local deadline (+ (os.clock) 1.2))
        (while (< (os.clock) deadline)
          (a:update 16)
          (b:update 16)
          (os.execute "sleep 0.01"))

        (local a-before (a:position))
        (local b-before (b:position))
        (local status-a (a:status))
        (local status-b (b:status))
        (local strict-clock?
          (and (. status-a "audio-active")
               (. status-b "audio-active")
               (. status-a "has-audio-clock")
               (. status-b "has-audio-clock")))
        (if strict-clock?
            (do
              (assert (> a-before 0.05) "first audio player should advance")
              (assert (> b-before 0.05) "second audio player should advance"))
            (print "[SKIP] strict audio progression checks skipped: audio clock unavailable"))

        (b:seek 0.35)
        (b:play)
        (local resumed?
          (wait-until (fn [] (> (b:position) 0.45))
                      4.0
                      (fn []
                        (a:update 16)
                        (b:update 16)
                        (os.execute "sleep 0.01"))))
        (assert resumed? "seeked audio player did not continue after seek")
        (assert (not (a:ended)) "looped audio player A should not end")
        (assert (not (b:ended)) "looped audio player B should not end")

        (a:drop)
        (b:drop))))

(fn status-api-returns-structured-fields []
  (local player
    (Video.VideoPlayer {:path "lua/tests/data/test-videos/00_baseline_h264_320x240_30fps_yuv420p_noaudio.mp4"
                        :autoplay false
                        :muted true}))

  (local status (player:status))
  (assert (= (type status) :table) "status should return a table")
  (assert (= (type status.ready) :boolean) "status.ready should be boolean")
  (assert (= (type status.ended) :boolean) "status.ended should be boolean")
  (assert (= (type status.playing) :boolean) "status.playing should be boolean")
  (assert (= (type status.error) :string) "status.error should be string")
  (assert (= (type (. status "has-error")) :boolean) "status.has-error should be boolean")
  (assert (= (type (. status "clock-seconds")) :number) "status.clock-seconds should be number")
  (assert (= (type (. status "has-audio-clock")) :boolean) "status.has-audio-clock should be boolean")
  (assert (= (type (. status "audio-available")) :boolean) "status.audio-available should be boolean")
  (assert (= (type (. status "audio-active")) :boolean) "status.audio-active should be boolean")
  (assert (= (type (. status "positional-audio")) :boolean) "status.positional-audio should be boolean")
  (assert (= (type (. status "queued-audio-chunks")) :number) "status.queued-audio-chunks should be number")
  (assert (= (type (. status "dropped-audio-chunks")) :number) "status.dropped-audio-chunks should be number")
  (assert (= (type (. status "flushed-audio-chunks")) :number) "status.flushed-audio-chunks should be number")
  (assert (= (type (. status "av-drift-seconds")) :number) "status.av-drift-seconds should be number")
  (assert (= (type (. status "max-av-drift-seconds")) :number) "status.max-av-drift-seconds should be number")
  (assert (= (type (. status "recent-max-av-drift-seconds")) :number) "status.recent-max-av-drift-seconds should be number")
  (assert (= (type (. status "av-drift-window-seconds")) :number) "status.av-drift-window-seconds should be number")
  (assert (= (type (. status "dropped-video-frames")) :number) "status.dropped-video-frames should be number")
  (assert (= (type (. status "decode-loop-iterations")) :number) "status.decode-loop-iterations should be number")
  (assert (= (type (. status "decode-wait-ms")) :number) "status.decode-wait-ms should be number")
  (assert (>= (. status "queued-audio-chunks") 0) "status.queued-audio-chunks should be non-negative")
  (assert (>= (. status "dropped-audio-chunks") 0) "status.dropped-audio-chunks should be non-negative")
  (assert (>= (. status "flushed-audio-chunks") 0) "status.flushed-audio-chunks should be non-negative")
  (assert (>= (. status "recent-max-av-drift-seconds") 0) "status.recent-max-av-drift-seconds should be non-negative")
  (assert (> (. status "av-drift-window-seconds") 0) "status.av-drift-window-seconds should be positive")
  (assert (>= (. status "decode-loop-iterations") 0) "status.decode-loop-iterations should be non-negative")
  (assert (>= (. status "decode-wait-ms") 0) "status.decode-wait-ms should be non-negative")

  (player:play)
  (local progressed?
    (wait-until (fn [] (> (player:position) 0.05))
                3.0
                (fn []
                  (player:update 16)
                  (os.execute "sleep 0.01"))))
  (assert progressed? "status test player did not progress")
  (local status-playing (player:status))
  (assert status-playing.playing "status.playing should become true while active")
  (assert (not (. status-playing "has-error")) "status.has-error should be false on healthy playback")

  (player:pause)
  (local status-paused (player:status))
  (assert (not status-paused.playing) "status.playing should be false after pause")
  (player:set-positional-audio true)
  (assert (player:positional-audio) "player should report positional audio true after enabling")
  (player:set-positional-audio false)
  (assert (not (player:positional-audio)) "player should report positional audio false after disabling")
  (player:drop))

(fn audio-queue-flush-telemetry-increments-on-seek []
  (local player
    (Video.VideoPlayer {:path "lua/tests/data/test-videos/01_baseline_h264_with_audio.mp4"
                        :autoplay true
                        :loop true
                        :muted false}))

  (local ready?
    (wait-until (fn [] (player:ready))
                4.0
                (fn []
                  (player:update 16)
                  (os.execute "sleep 0.01"))))
  (assert ready? "flush telemetry test player did not become ready")

  (local queued-before
    (wait-until (fn []
                  (player:update 16)
                  (> (. (player:status) "queued-audio-chunks") 0))
                2.0
                (fn [] (os.execute "sleep 0.01"))))
  (if (not queued-before)
      (do
        (print "[SKIP] flush telemetry assertion skipped: no queued audio chunks")
        (player:drop))
      (do
        (local status-before (player:status))
        (local flushed-before (. status-before "flushed-audio-chunks"))
        (player:seek 0.15)
        (player:update 16)
        (local status-after (player:status))
        (assert (> (. status-after "flushed-audio-chunks") flushed-before)
                "seek should flush queued audio chunks and increment telemetry")
        (player:drop))))

(fn decode-telemetry-is-monotonic-during-buffer-and-consume []
  (local player
    (Video.VideoPlayer {:path "lua/tests/data/test-videos/00_baseline_h264_320x240_30fps_yuv420p_noaudio.mp4"
                        :autoplay false
                        :loop false
                        :muted true}))

  ;; Let the decoder run without consuming frames so buffering pressure can trigger wait accounting.
  (local start-status (player:status))
  (local start-iterations (. start-status "decode-loop-iterations"))
  (local start-wait-ms (. start-status "decode-wait-ms"))
  (local buffered?
    (wait-until (fn []
                  (local status (player:status))
                  (and (> (. status "decode-loop-iterations") start-iterations)
                       (> (. status "decode-wait-ms") start-wait-ms)))
                3.0
                (fn [] (os.execute "sleep 0.01"))))
  (assert buffered? "decode telemetry did not increase under buffering pressure")

  ;; Then consume frames and ensure counters remain monotonic in active updates.
  (local prev-status (player:status))
  (var prev-iterations (. prev-status "decode-loop-iterations"))
  (var prev-wait-ms (. prev-status "decode-wait-ms"))
  (local deadline (+ (os.clock) 0.6))
  (while (< (os.clock) deadline)
    (player:update 16)
    (local status (player:status))
    (local iterations (. status "decode-loop-iterations"))
    (local wait-ms (. status "decode-wait-ms"))
    (assert (>= iterations prev-iterations) "decode-loop-iterations regressed")
    (assert (>= wait-ms prev-wait-ms) "decode-wait-ms regressed")
    (set prev-iterations iterations)
    (set prev-wait-ms wait-ms)
    (os.execute "sleep 0.01"))
  (player:drop))

(fn audio-drift-stays-within-budget []
  (if (= (os.getenv "SPACE_DISABLE_AUDIO") "1")
      (print "[SKIP] drift budget assertion skipped: SPACE_DISABLE_AUDIO=1")
      (do
        (local player
          (Video.VideoPlayer {:path "lua/tests/data/test-videos/01_baseline_h264_with_audio.mp4"
                              :autoplay true
                              :loop true
                              :muted false}))

        (local ready?
          (wait-until (fn [] (player:ready))
                      5.0
                      (fn []
                        (player:update 16)
                        (os.execute "sleep 0.01"))))
        (assert ready? "drift test player did not become ready")

        (local clock-started?
          (wait-until (fn []
                        (player:update 16)
                        (local status (player:status))
                        (assert (not (. status "has-error")) (.. "drift status error: " status.error))
                        (. status "has-audio-clock"))
                      4.0
                      (fn [] (os.execute "sleep 0.01"))))
        (if (not clock-started?)
            (print "[SKIP] drift budget assertion skipped: audio clock unavailable")
            (do
              (local initial-status (player:status))
              (local drift-window (math.max 0.5 (or (. initial-status "av-drift-window-seconds") 2.0)))
              (local settle-deadline (+ (os.clock) drift-window 0.35))
              (while (< (os.clock) settle-deadline)
                (player:update 16)
                (local status (player:status))
                (assert (not (. status "has-error")) (.. "drift status error: " status.error))
                (os.execute "sleep 0.01"))

              (local sample-deadline (+ (os.clock) 0.8))
              (var sampled-frames 0)
              (var peak-recent-drift 0.0)
              (var saw-audio-active? false)
              (while (< (os.clock) sample-deadline)
                (player:update 16)
                (local status (player:status))
                (assert (not (. status "has-error")) (.. "drift status error: " status.error))
                (when (. status "audio-active")
                  (set saw-audio-active? true))
                (set sampled-frames (+ sampled-frames 1))
                (local recent-abs (math.abs (. status "recent-max-av-drift-seconds")))
                (if (> recent-abs peak-recent-drift)
                    (set peak-recent-drift recent-abs))
                (os.execute "sleep 0.01"))

              (if (and saw-audio-active? (> sampled-frames 0))
                  (assert (< peak-recent-drift 0.25)
                          (.. "A/V drift budget exceeded: recent max drift " peak-recent-drift))
                  (print "[SKIP] drift budget assertion skipped: audio backend not active"))))
        (player:drop))))

(if Video.available
    (do
      (table.insert tests {:name "video decodes no-audio stream into texture" :fn decode-no-audio-video-into-texture})
      (table.insert tests {:name "video seek reaches ended on short clip" :fn seek-and-end-short-video})
      (table.insert tests {:name "video audio stream decode smoke" :fn decode-video-with-audio-streaming-smoke})
      (table.insert tests {:name "video pause/resume keeps stable position and resumes" :fn pause-resume-audio-video-keeps-position-stable})
      (table.insert tests {:name "video loop wraps without ending" :fn looped-short-video-wraps-and-does-not-end})
      (table.insert tests {:name "video repeated seeks keep player healthy" :fn repeated-seeks-do-not-break-readiness})
      (table.insert tests {:name "video multiple players progress concurrently" :fn multiple-players-progress-concurrently})
      (table.insert tests {:name "video audio players run concurrently with seek" :fn multiple-audio-players-run-and-seek})
      (table.insert tests {:name "video status api returns structured fields" :fn status-api-returns-structured-fields})
      (table.insert tests {:name "video seek increments audio flush telemetry" :fn audio-queue-flush-telemetry-increments-on-seek})
      (table.insert tests {:name "video decode telemetry stays monotonic while buffering and consuming" :fn decode-telemetry-is-monotonic-during-buffer-and-consume})
      (table.insert tests {:name "video audio drift stays within budget" :fn audio-drift-stays-within-budget}))
    (table.insert tests
                  {:name "video tests skipped when FFmpeg unavailable"
                   :fn (fn []
                         (assert (not Video.available) "video module unexpectedly available")
                         (print (.. "[SKIP] video tests: " (or Video.missing-reason "FFmpeg unavailable"))))}))

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "video"
                       :tests tests})))

{:name "video"
 :tests tests
 :main main}
