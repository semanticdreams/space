(local glm (require :glm))
(local Sized (require :sized))
(local Video (require :video))
(local VideoWidget (require :video-widget))

(local video-path "lua/tests/data/test-videos/01_baseline_h264_with_audio.mp4")

(fn make-builder []
  (local resolved-path (app.engine.get-asset-path video-path))
  (assert resolved-path (.. "demo-video-cube missing asset path: " video-path))
  (Sized {:size (glm.vec3 24 13.5 0)
          :child (VideoWidget {:path resolved-path
                               :name "demo-video-cube"
                               :base-width 24
                               :loop true
                               :autoplay true
                               :muted false
                               :positional-audio true})}))

(fn run []
  (assert Video.available (or Video.missing-reason "video module unavailable"))
  (local scene app.scene)
  (assert (and scene scene.add-panel-child)
          "demo-video-cube launchable requires app.scene.add-panel-child")
  (scene:add-panel-child {:builder (make-builder)}))

{:name "demo-video-cube"
 :run run}
