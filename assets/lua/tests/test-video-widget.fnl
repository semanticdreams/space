(local Video (require :video))
(local VideoWidget (require :video-widget))

(local tests [])

(fn make-vector-buffer []
  (local buffer {:length (fn [_self] 0)
                 :allocate (fn [_self _count] 1)
                 :delete (fn [_self _handle] nil)
                 :set-glm-vec3 (fn [_self _handle _offset _value] nil)
                 :set-glm-vec4 (fn [_self _handle _offset _value] nil)
                 :set-glm-vec2 (fn [_self _handle _offset _value] nil)
                 :set-float (fn [_self _handle _offset _value] nil)})
  buffer)

(fn make-test-ctx []
  (local batches {})
  {:get-image-batch (fn [_self texture]
                      (assert (and texture texture.id) "texture must expose id")
                      (when (not (. batches texture.id))
                        (set (. batches texture.id)
                             {:texture texture
                              :vector (make-vector-buffer)
                              :handles {}}))
                      (. batches texture.id))
   :track-image-handle (fn [_self _batch _handle _clip] nil)
   :untrack-image-handle (fn [_self _batch _handle] nil)})

(fn video-widget-builds-with-shared-player []
  (assert Video.available (or Video.missing-reason "video unavailable"))
  (local player
    (Video.VideoPlayer {:path "lua/tests/data/test-videos/00_baseline_h264_320x240_30fps_yuv420p_noaudio.mp4"
                        :autoplay false
                        :muted true}))

  (local widget
    ((VideoWidget {:player player
                   :name "video-widget-test"
                   :width 8})
     (make-test-ctx)))

  (widget.layout:measurer)
  (assert (= widget.player player) "widget should hold provided player")
  (assert widget.image "widget should expose composed image")
  (assert widget.layout "widget should expose layout")
  (assert (= widget.layout.measure.x 8) "widget width should match provided width")

  (widget:drop)
  (player:drop))

(if Video.available
    (table.insert tests {:name "video-widget builds with shared player" :fn video-widget-builds-with-shared-player})
    (table.insert tests
                  {:name "video-widget tests skipped when FFmpeg unavailable"
                   :fn (fn []
                         (assert (not Video.available) "video module unexpectedly available")
                         (print (.. "[SKIP] video-widget tests: " (or Video.missing-reason "FFmpeg unavailable"))))}))

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "video-widget"
                       :tests tests})))

{:name "video-widget"
 :tests tests
 :main main}
