(local glm (require :glm))
(local Sized (require :sized))
(local Video (require :video))
(local VideoWidget (require :video-widget))
(local Persistence (require :scene-panel-persistence))

(local video-path "lua/tests/data/test-videos/01_baseline_h264_with_audio.mp4")
(local kind "scene-demo-video-cube")
(local restorer-module "launchables/demo-video-cube")

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

(fn open-panel [opts]
  (local options (or opts {}))
  (assert Video.available (or Video.missing-reason "video module unavailable"))
  (local scene (assert (or options.scene options.target app.scene)
                       "demo-video-cube launchable requires scene target"))
  (assert (and scene scene.add-panel-child)
          "demo-video-cube launchable requires app.scene.add-panel-child")
  (local transform (Persistence.panel-transform-options (or options.panel {})))
  (scene:add-panel-child {:builder (make-builder)
                          :position transform.position
                          :rotation transform.rotation
                          :persistence {:kind kind
                                        :restorer-module restorer-module}}))

(fn restore [opts]
  (open-panel opts))

{:name "demo-video-cube"
 :kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore
 :run (fn [] (open-panel {:scene app.scene}))}
