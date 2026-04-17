(local TouchRouter (require :touch-router))

(local router (TouchRouter {}))

(local PrimaryTouchMouseDown
  {:touch-down
   (fn [ctx payload]
     (router:on-touch-down ctx payload))})

(local PrimaryTouchMouseMotion
  {:touch-motion
   (fn [ctx payload]
     (router:on-touch-motion ctx payload))})

(local PrimaryTouchMouseUp
  {:touch-up
   (fn [ctx payload]
     (router:on-touch-up ctx payload))})

(local PrimaryTouchMouseCanceled
  {:touch-canceled
   (fn [ctx payload]
     (router:on-touch-canceled ctx payload))})

(local TouchLifecycle
  {:enter (fn [_ctx]
            (router:reset))
   :leave (fn [_ctx]
            (router:reset))})

{:PrimaryTouchMouseDown PrimaryTouchMouseDown
 :PrimaryTouchMouseMotion PrimaryTouchMouseMotion
 :PrimaryTouchMouseUp PrimaryTouchMouseUp
 :PrimaryTouchMouseCanceled PrimaryTouchMouseCanceled
 :TouchLifecycle TouchLifecycle
 :reset (fn [] (router:reset))}
