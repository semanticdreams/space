(local TouchSession (require :touch-session))
(local logging (require :logging))

(local SDL_BUTTON_LEFT 1)
(local default-drag-threshold 12)

(fn payload-touch-id [payload]
  (and payload (rawget payload "touch-id")))

(fn payload-finger-id [payload]
  (and payload (rawget payload "finger-id")))

(fn ensure-mouse-signal [name]
  (local events (and app.engine app.engine.events))
  (assert events "TouchRouter requires app.engine.events")
  (local signal (rawget events name))
  (assert signal (.. "TouchRouter requires engine event signal " name))
  signal)

(fn make-touch-mouse-payload [payload]
  (local out {:button SDL_BUTTON_LEFT
              :state true
              :clicks 1
              :x (or (and payload payload.x) 0)
              :y (or (and payload payload.y) 0)
              :xrel (or (and payload payload.xrel) 0)
              :yrel (or (and payload payload.yrel) 0)
              :which -1
              :mod 0
              :timestamp (and payload payload.timestamp)
              :pressure (and payload payload.pressure)
              :suppress-click? (and payload payload.suppress-click?)
              :canceled? (and payload payload.canceled?)
              :synthetic? true
              :source :touch})
  (tset out "touch-id" (payload-touch-id payload))
  (tset out "finger-id" (payload-finger-id payload))
  out)

(fn payload-from-contact [contact payload]
  (local out {:x (or (and contact contact.x) (and payload payload.x) 0)
              :y (or (and contact contact.y) (and payload payload.y) 0)
              :xrel (or (and contact contact.xrel) (and payload payload.xrel) 0)
              :yrel (or (and contact contact.yrel) (and payload payload.yrel) 0)
              :timestamp (or (and payload payload.timestamp) (and contact contact.timestamp))
              :pressure (or (and contact contact.pressure) (and payload payload.pressure))})
  (tset out "touch-id" (or (and contact (rawget contact "touch-id")) (payload-touch-id payload)))
  (tset out "finger-id" (or (and contact (rawget contact "finger-id")) (payload-finger-id payload)))
  out)

(fn emit-mouse-button-down [payload]
  (local signal (ensure-mouse-signal "mouse-button-down"))
  (signal:emit (make-touch-mouse-payload payload)))

(fn emit-mouse-motion [payload]
  (local signal (ensure-mouse-signal "mouse-motion"))
  (signal:emit (make-touch-mouse-payload payload)))

(fn emit-mouse-button-up [payload]
  (local mouse-payload (make-touch-mouse-payload payload))
  (set mouse-payload.state false)
  (local signal (ensure-mouse-signal "mouse-button-up"))
  (signal:emit mouse-payload))

(fn default-drag-candidate [_ctx payload _session]
  (local targets (and app.touch-gesture-targets app.touch-gesture-targets.select-object))
  (if targets
      (app.touch-gesture-targets:select-object payload {:method :on-touch-drag-start})
      nil))

(fn touch-end-method [target canceled?]
  (if canceled?
      (or (and target target.on-touch-drag-cancel)
          (and target target.on-touch-drag-end))
      (and target target.on-touch-drag-end)))

(fn TouchRouter [opts]
  (local options (or opts {}))
  (local session (TouchSession))
  (local drag-threshold (or options.drag-threshold default-drag-threshold))
  (local defer-mouse-when-drag-candidate? (not (= options.defer-mouse-when-drag-candidate? false)))
  (local select-drag-candidate (or options.select-drag-candidate default-drag-candidate))
  (local allow-touch? (or options.allow-touch? (fn [_payload] true)))
  (local on-multitouch-start options.on-multitouch-start)
  (local on-multitouch-motion options.on-multitouch-motion)
  (local on-multitouch-end options.on-multitouch-end)
  (var primary-key nil)
  (var mouse-active? false)
  (var mouse-deferred? false)
  (var blocked-multitouch? false)
  (var drag-candidate nil)
  (var captured-target nil)
  (var multitouch-active? false)

  (fn primary-contact []
    (and primary-key (session:get primary-key)))

  (fn set-primary! [ctx payload]
    (set primary-key (session:key-from-payload payload))
    (set drag-candidate (select-drag-candidate ctx payload session))
    (set mouse-active? false)
    (set mouse-deferred? false)
    (if (and drag-candidate defer-mouse-when-drag-candidate?)
        (set mouse-deferred? true)
        (do
          (emit-mouse-button-down payload)
          (set mouse-active? true))))

  (fn clear-single! []
    (set primary-key nil)
    (set drag-candidate nil)
    (set captured-target nil)
    (set mouse-active? false)
    (set mouse-deferred? false))

  (fn reset-blocked-if-idle []
    (when (<= (session:count) 0)
      (set blocked-multitouch? false)))

  (fn trace [event payload fields]
    (local base {:event event
                 :touch-id (payload-touch-id payload)
                 :finger-id (payload-finger-id payload)
                 :session-count (session:count)
                 :blocked-multitouch blocked-multitouch?
                 :multitouch-active multitouch-active?
                 :mouse-active mouse-active?
                 :mouse-deferred mouse-deferred?
                 :has-primary (not (= primary-key nil))
                 :has-captured-target (not (not captured-target))
                 :has-drag-candidate (not (not drag-candidate))
                 :timestamp (and payload payload.timestamp)})
    (when fields
      (each [k v (pairs fields)]
        (tset base k v)))
    (logging.debug base "[touch-router] state"))

  (fn release-mouse! [payload opts]
    (when mouse-active?
      (local resolved (payload-from-contact (primary-contact) payload))
      (when (and opts opts.suppress-click?)
        (set resolved.suppress-click? true))
      (when (and opts opts.canceled?)
        (set resolved.canceled? true))
      (emit-mouse-button-up resolved)
      (set mouse-active? false)))

  (fn dispatch-deferred-click! [payload]
    (local resolved (payload-from-contact (primary-contact) payload))
    (emit-mouse-button-down resolved)
    (emit-mouse-button-up resolved)
    (set mouse-deferred? false))

  (fn finish-captured! [payload canceled?]
    (when captured-target
      (local handler (touch-end-method captured-target canceled?))
      (when handler
        (handler captured-target (payload-from-contact (primary-contact) payload)))
      (set captured-target nil)
      (set drag-candidate nil)))

  (fn cancel-single! [payload]
    (finish-captured! payload true)
    (release-mouse! payload {:suppress-click? true
                             :canceled? true})
    (set mouse-deferred? false))

  (fn try-start-capture! [payload]
    (local contact (primary-contact))
    (if (and drag-candidate
             contact
             (>= (session:movement-distance contact) drag-threshold))
        (do
          (local handler (. drag-candidate :on-touch-drag-start))
          (local resolved (payload-from-contact contact payload))
          (if (and handler (drag-candidate:on-touch-drag-start resolved))
              (do
                (release-mouse! resolved {:suppress-click? true})
                (set mouse-deferred? false)
                (set captured-target drag-candidate)
                (set drag-candidate nil)
                (when (and captured-target captured-target.on-touch-drag)
                  (captured-target:on-touch-drag resolved))
                true)
              false))
        false))

  (fn current-gesture []
    (session:gesture-payload))

  (fn start-multitouch! [ctx]
    (if (and on-multitouch-start (= (session:count) 2))
        (do
          (local gesture (current-gesture))
          (if (on-multitouch-start ctx gesture session)
              (do
                (set multitouch-active? true)
                true)
              false))
        false))

  (fn stop-multitouch! [ctx canceled?]
    (when multitouch-active?
      (when on-multitouch-end
        (on-multitouch-end ctx (current-gesture) session {:canceled? canceled?}))
      (set multitouch-active? false)))

  (fn reset-router! [payload]
    (stop-multitouch! nil true)
    (when primary-key
      (cancel-single! payload))
    (clear-single!)
    (set blocked-multitouch? false)
    (session:clear)
    true)

  (fn handle-active-multitouch-down [ctx]
    (if (> (session:count) 2)
        (do
          (stop-multitouch! ctx true)
          (set blocked-multitouch? true)
          true)
        true))

  (fn handle-single-touch-down [ctx payload]
    (local key (session:key-from-payload payload))
    (if blocked-multitouch?
        true
        (if (not primary-key)
            (do
              (set-primary! ctx payload)
              true)
            (if (= key primary-key)
                true
                (do
                  (cancel-single! payload)
                  (if (start-multitouch! ctx)
                      true
                      (do
                        (set blocked-multitouch? true)
                        true)))))))

  (fn on-touch-down [_self ctx payload]
    (if (not payload)
        false
        (if (not (allow-touch? payload))
            (do
              (trace "touch-down-blocked" payload {:reason "allow-touch-false"})
              (when (> (session:count) 0)
                (reset-router! payload))
              false)
            (do
              (session:on-touch-down payload)
              (reset-blocked-if-idle)
              (trace "touch-down" payload nil)
              (if multitouch-active?
                  (handle-active-multitouch-down ctx)
                  (handle-single-touch-down ctx payload))))))

  (fn handle-active-multitouch-motion [ctx]
    (if (> (session:count) 2)
        (do
          (stop-multitouch! ctx true)
          (set blocked-multitouch? true)
          true)
        (do
          (when on-multitouch-motion
            (on-multitouch-motion ctx (current-gesture) session))
          true)))

  (fn handle-single-touch-motion [payload]
    (local key (session:key-from-payload payload))
    (if blocked-multitouch?
        true
        (if (not (= key primary-key))
            false
            (if captured-target
                (do
                  (when captured-target.on-touch-drag
                    (captured-target:on-touch-drag
                      (payload-from-contact (primary-contact) payload)))
                  true)
                (if (try-start-capture! payload)
                    true
                    (if mouse-active?
                        (do
                          (emit-mouse-motion
                            (payload-from-contact (primary-contact) payload))
                          true)
                        false))))))

  (fn on-touch-motion [_self ctx payload]
    (if (not payload)
        false
        (if (not (allow-touch? payload))
            (do
              (trace "touch-motion-blocked" payload {:reason "allow-touch-false"})
              (when (> (session:count) 0)
                (reset-router! payload))
              false)
            (do
              (session:on-touch-motion payload)
              (trace "touch-motion" payload nil)
              (if multitouch-active?
                  (handle-active-multitouch-motion ctx)
                  (handle-single-touch-motion payload))))))

  (fn complete-single! [payload canceled?]
    (if captured-target
        (finish-captured! payload canceled?)
        (if canceled?
            (do
              (release-mouse! payload {:suppress-click? true
                                       :canceled? true})
              (set mouse-deferred? false))
            (if mouse-deferred?
                (dispatch-deferred-click! payload)
                (release-mouse! payload)))))

  (fn handle-active-multitouch-finished [ctx canceled?]
    (when (< (session:count) 2)
      (stop-multitouch! ctx canceled?)
      (if (> (session:count) 0)
          (set blocked-multitouch? true)
          (set blocked-multitouch? false)))
    true)

  (fn handle-single-touch-finished [payload canceled? primary?]
    (if blocked-multitouch?
        (do
          (when (and primary? (<= (session:count) 0))
            (clear-single!))
          (reset-blocked-if-idle)
          true)
        (if primary?
            (do
              (complete-single! payload canceled?)
              (clear-single!)
              (when (> (session:count) 0)
                (set blocked-multitouch? true))
              (reset-blocked-if-idle)
              true)
            false)))

  (fn on-touch-finished [_self ctx payload canceled?]
    (if (not payload)
        false
        (if (not (allow-touch? payload))
            (do
              (trace (if canceled? "touch-canceled-blocked" "touch-up-blocked")
                     payload
                     {:reason "allow-touch-false"})
              (when (> (session:count) 0)
                (reset-router! payload))
              false)
            (do
              (local key (session:key-from-payload payload))
              (local primary? (= key primary-key))
              (session:on-touch-up payload)
              (trace (if canceled? "touch-canceled" "touch-up")
                     payload
                     {:primary primary?})
              (if multitouch-active?
                  (handle-active-multitouch-finished ctx canceled?)
                  (handle-single-touch-finished payload canceled? primary?))))))

  (fn on-touch-up [self ctx payload]
    (on-touch-finished self ctx payload false))

  (fn on-touch-canceled [self ctx payload]
    (on-touch-finished self ctx payload true))

  (fn reset [_self]
    (reset-router! nil))

  {:on-touch-down on-touch-down
   :on-touch-motion on-touch-motion
   :on-touch-up on-touch-up
   :on-touch-canceled on-touch-canceled
   :reset reset})

TouchRouter
