(local Harness (require :tests.e2e.harness))
(local Video (require :video))
(local VideoWidget (require :video-widget))

(fn wait-for-ready [target video-node timeout-seconds]
  (local timeout (or timeout-seconds 4.0))
  (local width target.width)
  (local height target.height)
  (local deadline (+ (os.clock) timeout))
  (var ready? false)
  (while (and (< (os.clock) deadline) (not ready?))
    (video-node.player:update 16)
    (Harness.draw-targets width height [{:target target}])
    (local status (video-node.player:status))
    (assert (not (. status "has-error")) (.. "video snapshot status error: " status.error))
    (when (video-node.player:ready)
      (set ready? true))
    (when (not ready?)
      (os.execute "sleep 0.01")))
  ready?)

(fn warm-mid-frame [target video-node]
  (local width target.width)
  (local height target.height)
  (local duration (video-node.player:duration))
  (assert (> duration 0.0) "video snapshot duration should be > 0 before mid-frame seek")
  (local mid-seconds (* duration 0.5))
  (video-node.player:seek mid-seconds)
  (video-node.player:pause)
  (local deadline (+ (os.clock) 0.45))
  (while (< (os.clock) deadline)
    (video-node.player:update 16)
    (Harness.draw-targets width height [{:target target}])
    (local status (video-node.player:status))
    (assert (not (. status "has-error")) (.. "video snapshot warmup error: " status.error))
    (os.execute "sleep 0.01"))
  (video-node.player:pause))

(fn run [ctx]
  (if (not Video.available)
      (print (.. "[SKIP] e2e video snapshot: " (or Video.missing-reason "FFmpeg unavailable")))
      (do
        (var video-node nil)
        (local path (app.engine.get-asset-path "lua/tests/data/test-videos/00_baseline_h264_320x240_30fps_yuv420p_noaudio.mp4"))
        (local file (io.open path "rb"))
        (assert file (.. "video fixture missing: " path))
        (file:close)
        (local video-builder
          (fn [child-ctx]
            (local node
              ((VideoWidget {:path path
                             :name "e2e-video"
                             :base-width 18
                             :autoplay false
                             :loop false
                             :muted true}) child-ctx))
            (set video-node node)
            node))

        (local target
          (Harness.make-screen-target {:width ctx.width
                                       :height ctx.height
                                       :world-units-per-pixel ctx.units-per-pixel
                                       :builder video-builder}))

        (assert video-node "video snapshot missing video widget")
        (local ready? (wait-for-ready target video-node 6.0))
        (assert ready? "video snapshot player did not become ready")
        (warm-mid-frame target video-node)

        (local texture (video-node.player:texture))
        (assert texture "video snapshot missing texture")
        (assert texture.ready "video snapshot texture should be ready")
        (assert (> (or texture.id 0) 0) "video snapshot texture id should be > 0")
        (assert (> (or texture.width 0) 0) "video snapshot texture width missing")
        (assert (> (or texture.height 0) 0) "video snapshot texture height missing")
        (local image-batches (target:get-image-batches))
        (local image-batch (. image-batches texture.id))
        (assert image-batch "video snapshot missing image batch for texture id")
        (assert (> (image-batch.vector:length) 0) "video snapshot image batch has no vertices")
        (assert (not (video-node.image.layout:effective-culled?)) "video snapshot image layout culled")
        (video-node.image.raw:update)
        (Harness.draw-targets ctx.width ctx.height [{:target target}])

        (Harness.capture-snapshot {:name "video-frame"
                                   :width ctx.width
                                   :height ctx.height
                                   :tolerance 3})
        (Harness.cleanup-target target))))

(fn main []
  (Harness.with-app {}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E video snapshot complete"))

{:run run
 :main main}
