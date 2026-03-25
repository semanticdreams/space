(local Common (require :state-handlers/common))

(local CameraUpdated
  {:updated
   (fn [ctx delta]
     (local controls ((. Common :controls-from) ctx))
     (when controls
       (controls:update delta)))})

{:CameraUpdated CameraUpdated}
