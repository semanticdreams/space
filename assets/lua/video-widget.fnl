(local Video (require :video))
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
                              :muted (not (not opts.muted))})))

    (local image
      ((Image {:name (or opts.name "video")
               :texture (player:texture)
               :size opts.size
               :width opts.width
               :height opts.height
               :base-width opts.base-width
               :tint opts.tint})
       ctx))

    (fn drop [self]
      (self.image:drop)
      (when (and owns-player? self.player self.player.drop)
        (self.player:drop)))

    {:layout image.layout
     :drop drop
     :player player
     :image image}))

VideoWidget
