(local Runtime (require :state-runtime))
(local Common (require :state-handlers/common))

(local HoverLifecycle
  {:enter (fn [ctx]
            (local hoverables ((. Common :hoverables-from) ctx))
            (hoverables:on-enter))
   :leave (fn [ctx]
            (local hoverables ((. Common :hoverables-from) ctx))
            (hoverables:on-leave))})

(local HoverAfterMouseButtonUp
  {:mouse-button-up (fn [ctx payload]
                      (when (not ((. ctx :event-consumed?)))
                        (Runtime.handle-hover payload)))})

(local HoverMouseMotion
  {:mouse-motion (fn [ctx payload]
                   (when (not ((. ctx :event-consumed?)))
                     (Runtime.handle-hover payload)))})

(local HoverUpdated
  {:updated
   (fn [ctx _delta]
     (local hoverables ((. Common :hoverables-from) ctx))
     (local update-fn hoverables.update-from-input)
     (when update-fn
       (update-fn hoverables)))})

{:HoverLifecycle HoverLifecycle
 :HoverAfterMouseButtonUp HoverAfterMouseButtonUp
 :HoverMouseMotion HoverMouseMotion
 :HoverUpdated HoverUpdated}
