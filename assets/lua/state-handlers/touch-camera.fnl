(local TouchRouter (require :touch-router))
(local TouchTransform (require :state-handlers/touch-transform))

(local router
  (TouchRouter {:on-multitouch-start TouchTransform.handle-transform-start
                :on-multitouch-motion TouchTransform.handle-transform-motion
                :on-multitouch-end TouchTransform.handle-transform-end}))

(local CameraTouchDown
  {:touch-down
   (fn [ctx payload]
     (router:on-touch-down ctx payload))})

(local CameraTouchMotion
  {:touch-motion
   (fn [ctx payload]
     (router:on-touch-motion ctx payload))})

(local CameraTouchUp
  {:touch-up
   (fn [ctx payload]
     (router:on-touch-up ctx payload))})

(local CameraTouchCanceled
  {:touch-canceled
   (fn [ctx payload]
     (router:on-touch-canceled ctx payload))})

(local TouchLifecycle
  {:enter (fn [_ctx]
            (router:reset))
   :leave (fn [_ctx]
            (router:reset))})

{:CameraTouchDown CameraTouchDown
 :CameraTouchMotion CameraTouchMotion
 :CameraTouchUp CameraTouchUp
 :CameraTouchCanceled CameraTouchCanceled
 :TouchLifecycle TouchLifecycle
 :reset (fn [] (router:reset))}
