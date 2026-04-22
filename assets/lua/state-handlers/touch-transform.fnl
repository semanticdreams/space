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

{:handle-transform-start handle-transform-start
 :handle-transform-motion handle-transform-motion
 :handle-transform-end handle-transform-end}
