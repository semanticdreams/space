(local TouchRouter (require :touch-router))
(local Runtime (require :state-runtime))

(fn active-controls []
  (Runtime.active-controls))

(fn handle-transform-start [_ctx gesture _session]
  (local controls (active-controls))
  (local handler (and controls controls.on-touch-transform-start))
  (and handler (controls:on-touch-transform-start gesture)))

(fn handle-transform-motion [_ctx gesture _session]
  (local controls (active-controls))
  (local handler (and controls controls.on-touch-transform))
  (when handler
    (controls:on-touch-transform gesture)))

(fn handle-transform-end [_ctx gesture _session opts]
  (local controls (active-controls))
  (local handler (and controls controls.on-touch-transform-end))
  (when handler
    (controls:on-touch-transform-end {:gesture gesture
                                      :canceled? (and opts opts.canceled?)})))

(local router
  (TouchRouter {:on-multitouch-start handle-transform-start
                :on-multitouch-motion handle-transform-motion
                :on-multitouch-end handle-transform-end}))

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
