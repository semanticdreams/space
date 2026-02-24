(local Video (require :video))
(local glm (require :glm))
(local {: Layout} (require :layout))
(local Image (require :image))

(fn VideoWidget [opts]
  (assert opts "VideoWidget requires options")
  (fn build [ctx]
    (assert Video.available (or Video.missing-reason "video module unavailable"))

    (local owns-player? (not opts.player))
    (local player
      (or opts.player
          (Video.VideoPlayer {:path opts.path
                              :loop (not (not opts.loop))
                              :autoplay (if (= opts.autoplay nil) true opts.autoplay)
                              :muted (not (not opts.muted))
                              :positional-audio (not (not opts.positional-audio))
                              :audio-position (or opts.audio-position (glm.vec3 0 0 0))
                              :audio-velocity (or opts.audio-velocity (glm.vec3 0 0 0))
                              :audio-direction (or opts.audio-direction (glm.vec3 0 0 0))
                              :audio-gain (or opts.audio-gain 1.0)
                              :audio-pitch (or opts.audio-pitch 1.0)
                              :audio-max-distance (or opts.audio-max-distance 300.0)
                              :audio-rolloff-factor (or opts.audio-rolloff-factor 0.05)
                              :audio-reference-distance (or opts.audio-reference-distance 10.0)
                              :audio-min-gain (or opts.audio-min-gain 0.0)
                              :audio-max-gain (or opts.audio-max-gain 1.0)
                              :audio-cone-inner-angle (or opts.audio-cone-inner-angle 360.0)
                              :audio-cone-outer-angle (or opts.audio-cone-outer-angle 360.0)
                              :audio-cone-outer-gain (or opts.audio-cone-outer-gain 0.0)})))

    (local image
      ((Image {:name (or opts.name "video")
               :texture (player:texture)
               :size opts.size
               :width opts.width
               :height opts.height
               :base-width opts.base-width
               :tint opts.tint})
       ctx))

    (fn update-audio-position [position size rotation]
      (when (and player.positional-audio player.set-audio-position (player:positional-audio))
        (local half-size (glm.vec3 (* 0.5 size.x) (* 0.5 size.y) (* 0.5 size.z)))
        (local center (+ position (rotation:rotate half-size)))
        (player:set-audio-position center)))

    (fn measurer [self]
      (image.layout:measurer)
      (set self.measure image.layout.measure))

    (fn layouter [self]
      (set image.layout.size self.size)
      (set image.layout.position self.position)
      (set image.layout.rotation self.rotation)
      (set image.layout.depth-offset-index self.depth-offset-index)
      (set image.layout.clip-region self.clip-region)
      (image.layout:layouter)
      (update-audio-position self.position self.size self.rotation))

    (local layout
      (Layout {:name (or opts.name "video-widget")
               :children [image.layout]
               : measurer
               : layouter}))

    (fn drop [self]
      (self.layout:drop)
      (self.image:drop)
      (when (and owns-player? self.player self.player.drop)
        (self.player:drop)))

    {:layout layout
     :drop drop
     :player player
     :image image}))

VideoWidget
