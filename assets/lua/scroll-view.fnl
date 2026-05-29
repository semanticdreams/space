(local glm (require :glm))
(local {: Layout : finite-constraint? : resolve-mark-flag} (require :layout))
(local ScrollArea (require :scroll-area))
(local ScrollBar (require :scroll-bar))
(local MathUtils (require :math-utils))
(local BoundsUtils (require :bounds-utils))
(local Padding (require :padding))
(local RuntimeUpdates (require :runtime-updates))

(local scroll-epsilon 1e-5)
(local kinetic-friction-per-ms 0.006)
(local kinetic-release-window-ms 80)
(local kinetic-carry-window-ms 250)
(local kinetic-min-velocity 0.001)
(local kinetic-min-frame-delta 0.01)
(local kinetic-max-frame-ms 64)
(local kinetic-carry-factor 0.5)
(local touch-drag-threshold 3)
(local wheel-kinetic-frame-ms 16)
(local wheel-event-window-ms 120)
(local wheel-kinetic-carry-factor 0.35)

(fn clamp [value min-value max-value]
  (math.max min-value (math.min max-value value)))

(local approx (fn [a b] (MathUtils.approx a b {:epsilon scroll-epsilon})))

(fn approx-or-nil [a b]
  (if (and a b)
      (approx a b)
      (= a b)))

(fn sanitize-height [value]
  (if (and value (> value 0))
      value
      nil))

(fn normalize-scrollbar-policy [value]
  (if (or (= value nil) (= value :always-on) (= value "always-on"))
      :always-on
      (if (or (= value :always-off) (= value "always-off"))
          :always-off
          :as-needed)))

(fn scrollbar-visible? [policy enabled?]
  (if (= policy :always-on)
      true
      (if (= policy :always-off)
          false
          enabled?)))

(fn payload-touch-id [payload]
  (and payload (rawget payload "touch-id")))

(fn payload-finger-id [payload]
  (and payload (rawget payload "finger-id")))

(fn current-time-ms []
  (assert (and app app.engine app.engine.now-ms)
          "ScrollView touch kinetic scrolling requires app.engine.now-ms")
  (app.engine:now-ms))

(fn payload-timestamp-ms [payload]
  (or (and payload payload.timestamp)
      (current-time-ms)))

(fn ScrollView [opts]
  (local options (or opts {}))
  (assert options.child "ScrollView requires :child")

  (fn build [ctx]
    (local padding
      (if (= options.padding false)
          nil
          (or options.padding [0.15 0.15])))
    (local scroll-child
      (if padding
          (Padding {:edge-insets padding
                    :child options.child})
          options.child))
    (local scroll-builder
      (ScrollArea {:child scroll-child
                   :name (or options.name "scroll-area")
                   :scroll-offset options.scroll-offset}))
    (local scroll (scroll-builder ctx))
    (local initial-offset (scroll:get-scroll-offset))
    (local initial-y (or (and initial-offset initial-offset.y) 0))
    (local scrollbar-width (math.max 0 (or options.scrollbar-width 0.85)))
    (local scrollbar-policy (normalize-scrollbar-policy options.scrollbar-policy))
    (local pointer-target (or options.pointer-target
                              (and ctx ctx.pointer-target)))
    (local touch-gesture-targets
      (or (and ctx ctx.touch-gesture-targets)
          app.touch-gesture-targets))
    (local state {:scroll scroll
                  :scrollbar nil
                  :scrollbar-width scrollbar-width
                  :scrollbar-policy scrollbar-policy
                  :scrollbar-visible? true
                  :scroll-offset (math.max 0 initial-y)
                  :max-offset 0
                  :visible-ratio 1
                  :scroll-enabled? false
                  :viewport-size (glm.vec3 0 0 0)
                  :viewport-height (sanitize-height options.viewport-height)
                  :touch-drag nil
                  :kinetic nil
                  :pending-kinetic nil
                  :wheel-scroll nil
                  :initialized? false
                  :pending-reset? false
                  :user-set-offset? (not (= options.scroll-offset nil))
                  :growth-anchor (or options.growth-anchor :top)})
    (local hoverables (assert ctx.hoverables "ScrollView requires ctx.hoverables"))
    (local focus-manager (and ctx ctx.focus ctx.focus.manager))
    (local view {:scroll scroll
                 :state state
                 :pointer-target pointer-target
                 :focus-manager focus-manager})
    (var kinetic-subscription nil)

    (fn sync-scrollbar [opts]
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (when state.scrollbar
        (local effective
          (if (> state.max-offset 0)
              (math.min state.scroll-offset state.max-offset)
              0))
        (local normalized
          (if (> state.max-offset 0)
              (clamp (/ effective state.max-offset) 0 1)
              0))
        (state.scrollbar:set-scroll-state {:value normalized
                                           :visible-ratio state.visible-ratio
                                           :enabled? state.scroll-enabled?
                                           :visible? state.scrollbar-visible?}
                                          {:mark-layout-dirty? mark-layout-dirty?})))

    (fn set-scroll-offset-value [value opts]
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (local max-offset (or state.max-offset 0))
      (local unclamped (math.max 0 (or value 0)))
      (local desired
        (if (> max-offset scroll-epsilon)
            (math.min unclamped max-offset)
            unclamped))
      (when (not (approx desired state.scroll-offset))
        (set state.scroll-offset desired)
        (scroll:set-scroll-offset (glm.vec3 0 desired 0)
                                  {:mark-layout-dirty? mark-layout-dirty?}))
      (sync-scrollbar {:mark-layout-dirty? mark-layout-dirty?}))

    (fn stop-kinetic! []
      (set state.kinetic nil)
      (when kinetic-subscription
        (kinetic-subscription:drop)
        (set kinetic-subscription nil)))

    (fn take-kinetic-velocity! []
      (local velocity (or (and state.kinetic state.kinetic.velocity) 0))
      (stop-kinetic!)
      velocity)

    (fn clear-pending-kinetic! []
      (set state.pending-kinetic nil))

    (fn clear-wheel-scroll! []
      (set state.wheel-scroll nil))

    (fn pending-kinetic-matches? [pending payload]
      (and pending
           payload
           (= (rawget pending "touch-id") (payload-touch-id payload))
           (= (rawget pending "finger-id") (payload-finger-id payload))))

    (fn take-pending-kinetic-velocity! [payload]
      (local pending state.pending-kinetic)
      (local timestamp (payload-timestamp-ms payload))
      (local velocity
        (if (and (pending-kinetic-matches? pending payload)
                 (<= (- timestamp (or pending.timestamp timestamp))
                     kinetic-carry-window-ms))
            (or pending.velocity 0)
            0))
      (clear-pending-kinetic!)
      velocity)

    (fn should-stop-at-scroll-bound? [velocity]
      (or (and (< velocity 0)
               (<= state.scroll-offset scroll-epsilon))
          (and (> velocity 0)
               (>= state.scroll-offset (- state.max-offset scroll-epsilon)))))

    (fn on-kinetic-frame [delta-ms]
      (local kinetic state.kinetic)
      (if (not kinetic)
          (stop-kinetic!)
          (do
            (local elapsed-ms (math.max (or delta-ms 0) 0))
            (local frame-ms (clamp elapsed-ms 0 kinetic-max-frame-ms))
            (local velocity kinetic.velocity)
            (if (or (<= elapsed-ms 0)
                    (< (math.abs velocity) kinetic-min-velocity)
                    (should-stop-at-scroll-bound? velocity))
                (stop-kinetic!)
                (do
                  (local frame-velocity
                    (* velocity (math.exp (* -1 kinetic-friction-per-ms frame-ms))))
                  (local next-velocity
                    (* velocity (math.exp (* -1 kinetic-friction-per-ms elapsed-ms))))
                  (local frame-delta
                    (/ (- velocity frame-velocity) kinetic-friction-per-ms))
                  (local previous-offset state.scroll-offset)
                  (if (< (math.abs frame-delta) kinetic-min-frame-delta)
                      (stop-kinetic!)
                      (do
                        (set-scroll-offset-value (+ state.scroll-offset frame-delta))
                        (set kinetic.velocity next-velocity)
                        (when (or (approx previous-offset state.scroll-offset)
                                  (< (math.abs next-velocity) kinetic-min-velocity)
                                  (should-stop-at-scroll-bound? next-velocity))
                          (stop-kinetic!)))))))))

    (fn start-kinetic! [velocity]
      (stop-kinetic!)
      (when (and state.scroll-enabled?
                 (> (math.abs velocity) kinetic-min-velocity)
                 (not (should-stop-at-scroll-bound? velocity)))
        (set state.kinetic {:velocity velocity})
        (set kinetic-subscription
             (RuntimeUpdates.FrameSubscription {:callback on-kinetic-frame}))
        (kinetic-subscription:start)))

    (fn node-in-scroll? [node]
      (local layout (and node node.layout))
      (local clip (and layout layout.clip-region))
      (and layout clip (= clip.layout scroll.layout)))

    (fn ensure-node-visible [node]
      (when (and node (node-in-scroll? node))
        (local layout node.layout)
        (local scroll-layout scroll.layout)
        (local viewport (or scroll-layout.size (glm.vec3 0 0 0)))
        (when (> viewport.y 0)
          (local bounds {:position layout.position
                         :rotation layout.rotation
                         :size layout.size})
          (local parent {:position scroll-layout.position
                         :rotation scroll-layout.rotation
                         :size viewport})
          (local local-bounds (BoundsUtils.bounds-aabb-min-max parent bounds))
          (when local-bounds
            (local min local-bounds.min)
            (local max local-bounds.max)
            (local delta-y
              (if (< min.y 0)
                  min.y
                  (if (> max.y viewport.y)
                      (- max.y viewport.y)
                      0)))
            (when (not (approx delta-y 0))
              (set state.user-set-offset? true)
              (set-scroll-offset-value (+ state.scroll-offset delta-y)))))))

    (fn apply-normalized-value [normalized opts]
      (stop-kinetic!)
      (clear-wheel-scroll!)
      (local clamped (clamp (or normalized 0) 0 1))
      (local max-offset state.max-offset)
      (if (> max-offset 0)
          (set-scroll-offset-value (* max-offset clamped) opts)
          (set-scroll-offset-value 0 opts)))

    (fn update-scroll-metrics [viewport-size opts]
      (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
      (set state.viewport-size viewport-size)
      (local content (scroll:get-content-size))
      (local content-height (or (and content content.y) 0))
      (local viewport-height (or viewport-size.y 0))
      (local max-offset (math.max 0 (- content-height viewport-height)))
      (local previous-max (or state.max-offset 0))
      (set state.max-offset max-offset)
      (when (and (= state.growth-anchor :bottom)
                 (or (and (not state.user-set-offset?)
                          (or (not state.initialized?)
                              (and (<= previous-max scroll-epsilon)
                                   (> max-offset scroll-epsilon))))
                     (and state.pending-reset? (not state.user-set-offset?))))
        (set state.scroll-offset 0)
        (scroll:set-scroll-offset (glm.vec3 0 0 0)
                                  {:mark-layout-dirty? mark-layout-dirty?})
        (set state.pending-reset? false))
      (when (and (not (= state.growth-anchor :bottom))
                 (not state.user-set-offset?)
                 (or state.pending-reset?
                     (and (not state.initialized?)
                          (> max-offset scroll-epsilon)
                          (<= previous-max scroll-epsilon))))
        (set state.scroll-offset max-offset)
        (scroll:set-scroll-offset (glm.vec3 0 max-offset 0)
                                  {:mark-layout-dirty? mark-layout-dirty?})
        (set state.pending-reset? false))
      (when (and (not (= state.growth-anchor :bottom))
                 state.initialized?
                 (not (approx max-offset previous-max)))
        (local distance-to-bottom (math.max 0 (- previous-max state.scroll-offset)))
        (local anchored-offset (math.max 0 (- max-offset distance-to-bottom)))
        (when (not (approx anchored-offset state.scroll-offset))
          (set state.scroll-offset anchored-offset)
          (scroll:set-scroll-offset (glm.vec3 0 anchored-offset 0)
                                    {:mark-layout-dirty? mark-layout-dirty?})))
      (when (not state.initialized?)
        (set state.initialized? true))
      (local ratio
        (if (> content-height 0)
            (clamp (/ viewport-height content-height) 0 1)
            1))
      (set state.visible-ratio ratio)
      (set state.scroll-enabled? (> max-offset scroll-epsilon))
      (set state.scrollbar-visible?
           (scrollbar-visible? state.scrollbar-policy state.scroll-enabled?))
      (local corrected (math.min state.scroll-offset max-offset))
      (when (not (approx corrected state.scroll-offset))
        (set state.scroll-offset corrected)
        (scroll:set-scroll-offset (glm.vec3 0 corrected 0)
                                  {:mark-layout-dirty? mark-layout-dirty?}))
      (sync-scrollbar {:mark-layout-dirty? mark-layout-dirty?}))

    (fn wheel-step []
      (local height (or (and state.viewport-size state.viewport-size.y) 0))
      (if (> height 0)
          (math.max 0.25 (* height 0.25))
          1.0))

    (fn wheel-integer-differs? [value integer-value]
      (and (not (= integer-value nil))
           (not (approx (or value 0) integer-value))))

    (fn continuous-wheel? [payload]
      (and payload
           (or (wheel-integer-differs? payload.x (rawget payload "integer-x"))
               (wheel-integer-differs? payload.y (rawget payload "integer-y")))))

    (fn wheel-event-velocity [scroll-delta payload]
      (local timestamp (payload-timestamp-ms payload))
      (local previous-timestamp (and state.wheel-scroll state.wheel-scroll.timestamp))
      (local recent-previous?
        (and previous-timestamp
             (<= (- timestamp previous-timestamp) wheel-event-window-ms)))
      (local elapsed-ms
        (if recent-previous?
            (math.max 1 (- timestamp previous-timestamp))
            wheel-kinetic-frame-ms))
      (set state.wheel-scroll {:timestamp timestamp})
      (/ scroll-delta elapsed-ms))

    (fn combine-wheel-velocity [event-velocity carry-velocity]
      (local event (or event-velocity 0))
      (local carry (or carry-velocity 0))
      (if (and (> (math.abs carry) kinetic-min-velocity)
               (> (* event carry) 0))
          (+ event (* carry wheel-kinetic-carry-factor))
          event))

    (fn on-mouse-wheel [_self payload]
      (if (not state.scroll-enabled?)
          false
          (do
            (local delta-y (or (and payload payload.y) 0))
            (if (= delta-y 0)
                false
                (do
                  (local step (wheel-step))
                  (local scroll-delta (* delta-y step))
                  (local continuous? (continuous-wheel? payload))
                  (local carry-velocity
                    (if continuous?
                        (take-kinetic-velocity!)
                        (do
                          (stop-kinetic!)
                          0)))
                  (when (not continuous?)
                    (clear-wheel-scroll!))
                  (set-scroll-offset-value (+ state.scroll-offset scroll-delta))
                  (when continuous?
                    (local event-velocity (wheel-event-velocity scroll-delta payload))
                    (start-kinetic!
                      (combine-wheel-velocity event-velocity carry-velocity)))
                  true)))))

    (fn active-touch-drag-matches? [payload]
      (local touch-drag (. state "touch-drag"))
      (and touch-drag
           payload
           (= (rawget touch-drag "touch-id") (payload-touch-id payload))
           (= (rawget touch-drag "finger-id") (payload-finger-id payload))))

    (fn clear-touch-drag! []
      (set (. state "touch-drag") nil))

    (fn combine-release-velocity [drag-velocity carry-velocity]
      (local drag (or drag-velocity 0))
      (local carry (or carry-velocity 0))
      (if (> (math.abs drag) kinetic-min-velocity)
          (if (and (> (math.abs carry) kinetic-min-velocity)
                   (> (* drag carry) 0))
              (+ drag (* carry kinetic-carry-factor))
              drag)
          0))

    (fn pointer-from-payload [payload]
      {:x (or (and payload payload.x) 0)
       :y (or (and payload payload.y) 0)})

    (fn ray-for-touch-payload [payload]
      (local pointer (pointer-from-payload payload))
      (if (and pointer-target pointer-target.screen-pos-ray)
          (pointer-target:screen-pos-ray pointer)
          (do
            (assert app.screen-pos-ray
                    "ScrollView touch drag requires app.screen-pos-ray or pointer-target.screen-pos-ray")
            (app.screen-pos-ray pointer))))

    (fn touch-local-y [payload]
      (local ray (assert (ray-for-touch-payload payload)
                         "ScrollView touch drag requires a pointer ray"))
      (local layout scroll.layout)
      (local normal (layout.rotation:rotate (glm.vec3 0 0 1)))
      (local denom (glm.dot ray.direction normal))
      (assert (> (math.abs denom) scroll-epsilon)
              "ScrollView touch drag ray is parallel to scroll plane")
      (local distance (/ (glm.dot (- layout.position ray.origin) normal)
                         denom))
      (local point (+ ray.origin (* ray.direction distance)))
      (local inverse (layout.rotation:inverse))
      (local local-point (inverse:rotate (- point layout.position)))
      local-point.y)

    (fn touch-start-payload [payload]
      (if (and payload (not (= payload.start-x nil)) (not (= payload.start-y nil)))
          {:x payload.start-x :y payload.start-y}
          payload))

    (fn record-touch-drag! [touch-drag payload]
      (local current-local-y (touch-local-y payload))
      (local dy (- current-local-y (or (. touch-drag :last-local-y) current-local-y)))
      (local timestamp (payload-timestamp-ms payload))
      (local elapsed-ms (math.max 1 (- timestamp (or touch-drag.last-timestamp-ms timestamp))))
      (local previous-offset state.scroll-offset)
      (set (. touch-drag :last-local-y) current-local-y)
      (set-scroll-offset-value (- state.scroll-offset dy))
      (local actual-delta (- state.scroll-offset previous-offset))
      (if (> (math.abs actual-delta) scroll-epsilon)
          (do
            (set touch-drag.velocity (/ actual-delta elapsed-ms))
            (set touch-drag.last-movement-timestamp-ms timestamp))
          (when (>= elapsed-ms kinetic-release-window-ms)
            (set touch-drag.velocity 0)))
      (set touch-drag.last-timestamp-ms timestamp)
      actual-delta)

    (fn on-touch-drag-candidate-start [_self payload]
      (local velocity (take-kinetic-velocity!))
      (if (> (math.abs velocity) kinetic-min-velocity)
          (do
            (local pending {:velocity velocity
                            :timestamp (payload-timestamp-ms payload)})
            (tset pending "touch-id" (payload-touch-id payload))
            (tset pending "finger-id" (payload-finger-id payload))
            (set state.pending-kinetic pending))
          (clear-pending-kinetic!))
      true)

    (fn on-touch-drag-candidate-end [_self _payload]
      (clear-pending-kinetic!)
      true)

    (fn on-touch-drag-start [_self payload]
      (if (not state.scroll-enabled?)
          false
          (do
            (local pending-velocity (take-pending-kinetic-velocity! payload))
            (local carry-velocity
              (if (> (math.abs pending-velocity) kinetic-min-velocity)
                  pending-velocity
                  (take-kinetic-velocity!)))
            (local timestamp (payload-timestamp-ms payload))
            (local touch-drag {:last-local-y (touch-local-y (touch-start-payload payload))
                               :last-timestamp-ms timestamp
                               :last-movement-timestamp-ms timestamp
                               :velocity 0
                               :carry-velocity carry-velocity})
            (tset touch-drag "touch-id" (payload-touch-id payload))
            (tset touch-drag "finger-id" (payload-finger-id payload))
            (set (. state "touch-drag") touch-drag)
            true)))

    (fn on-touch-drag [_self payload]
      (if (not (active-touch-drag-matches? payload))
          false
          (do
            (set state.user-set-offset? true)
            (local touch-drag (. state "touch-drag"))
            (record-touch-drag! touch-drag payload)
            true)))

    (fn on-touch-drag-end [_self payload]
      (if (active-touch-drag-matches? payload)
          (do
            (local touch-drag (. state "touch-drag"))
            (local timestamp (payload-timestamp-ms payload))
            (local idle-ms (- timestamp (or touch-drag.last-movement-timestamp-ms timestamp)))
            (local velocity
              (if (<= idle-ms kinetic-release-window-ms)
                  (combine-release-velocity touch-drag.velocity touch-drag.carry-velocity)
                  0))
            (clear-touch-drag!)
            (clear-pending-kinetic!)
            (clear-wheel-scroll!)
            (start-kinetic! velocity)
            true)
          false))

    (fn on-touch-drag-cancel [_self payload]
      (if (active-touch-drag-matches? payload)
          (do
            (clear-touch-drag!)
            (clear-pending-kinetic!)
            (clear-wheel-scroll!)
            (stop-kinetic!)
            true)
          false))

    (local scrollbar
      ((ScrollBar {:width scrollbar-width
                   :on-value-changed (fn [_bar value]
                                       (apply-normalized-value value))})
       ctx))

    (set state.scrollbar scrollbar)

    (fn clamp-height [value]
      (if state.viewport-height
          (math.min value state.viewport-height)
          value))

    (fn resolve-viewport-height [content-height constraints]
      (local max-height
        (when (finite-constraint? constraints 2)
          constraints.max.y))
      (local unconstrained-height (clamp-height content-height))
      (if max-height
          (math.min unconstrained-height max-height)
          unconstrained-height))

    (fn initial-viewport-height [constraints]
      (if (finite-constraint? constraints 2)
          constraints.max.y
          (or state.viewport-height 0)))

    (fn measure-scroll-content [available-size viewport-height reserved-width]
      (local viewport-width (math.max 0 (- available-size.x reserved-width)))
      (local viewport-size (glm.vec3 viewport-width
                                viewport-height
                                available-size.z))
      (local content-size (scroll:measure-content-for-viewport viewport-size))
      (local content-height (or (and content-size content-size.y) 0))
      (local needs-scroll? (> (- content-height viewport-height) scroll-epsilon))
      {:content-size content-size
       :viewport-size viewport-size
       :reserved-width reserved-width
       :needs-scroll? needs-scroll?})

    (fn resolve-constrained-measure [available-size constraints]
      (local initial-reserved-width
        (if (= state.scrollbar-policy :always-on)
            (math.min scrollbar-width available-size.x)
            0))
      (var viewport-height
        (initial-viewport-height constraints))
      (var resolution
        (measure-scroll-content available-size viewport-height initial-reserved-width))
      (local resolved-height
        (resolve-viewport-height resolution.content-size.y constraints))
      (when (not (approx viewport-height resolved-height))
        (set viewport-height resolved-height)
        (set resolution
             (measure-scroll-content available-size viewport-height initial-reserved-width)))
      (when (and (= state.scrollbar-policy :as-needed)
                 resolution.needs-scroll?)
        (local reserved-width (math.min scrollbar-width available-size.x))
        (set resolution
             (measure-scroll-content available-size viewport-height reserved-width)))
      resolution)

    (fn measurer [self]
      (scroll.layout:measurer)
      (local content-size (or scroll.layout.measure (glm.vec3 0 0 0)))
      (local viewport-height (clamp-height content-size.y))
      (local needs-scroll? (> (- content-size.y viewport-height) scroll-epsilon))
      (local bar-visible? (scrollbar-visible? state.scrollbar-policy needs-scroll?))
      (local reserved-width (if bar-visible? scrollbar-width 0))
      (set self.measure
           (glm.vec3 (+ content-size.x reserved-width)
                 (clamp-height content-size.y)
                 content-size.z)))

    (fn constrained-measurer [self constraints]
      (local max-size (and constraints constraints.max))
      (if max-size
          (do
            (local resolution (resolve-constrained-measure max-size constraints))
            (local content-size (or resolution.content-size (glm.vec3 0 0 0)))
            (set self.measure
                 (glm.vec3 (math.min max-size.x (+ content-size.x resolution.reserved-width))
                           resolution.viewport-size.y
                           content-size.z)))
          (measurer self)))

    (fn layouter [self]
      (local scroll-layout scroll.layout)
      (local scrollbar-layout scrollbar.layout)
      (local viewport-height (clamp-height self.size.y))
      (local initial-reserved-width
        (if (= state.scrollbar-policy :always-on)
            (math.min scrollbar-width self.size.x)
            0))
      (var viewport-resolution (measure-scroll-content self.size viewport-height initial-reserved-width))
      (when (and (= state.scrollbar-policy :as-needed)
                 viewport-resolution.needs-scroll?)
        (set viewport-resolution
             (measure-scroll-content self.size
                                     viewport-height
                                     (math.min scrollbar-width self.size.x))))
      (local reserved-width viewport-resolution.reserved-width)
      (local viewport-size viewport-resolution.viewport-size)
      (local viewport-width viewport-size.x)
      (local y-gap (math.max 0 (- self.size.y viewport-height)))
      (local viewport-offset (glm.vec3 0 y-gap 0))
      (set scroll-layout.size viewport-size)
      (set scroll-layout.position (+ self.position (self.rotation:rotate viewport-offset)))
      (set scroll-layout.rotation self.rotation)
      (set scroll-layout.depth-offset-index self.depth-offset-index)
      (set scroll-layout.clip-region self.clip-region)
      (update-scroll-metrics viewport-size {:mark-layout-dirty? false})
      (scroll-layout:layouter)
      (local bar-offset (glm.vec3 viewport-width 0 0))
      (local bar-position (+ self.position (self.rotation:rotate bar-offset)))
      (set scrollbar-layout.size (glm.vec3 reserved-width self.size.y self.size.z))
      (set scrollbar-layout.position bar-position)
      (set scrollbar-layout.rotation self.rotation)
      (set scrollbar-layout.depth-offset-index self.depth-offset-index)
      (set scrollbar-layout.clip-region self.clip-region)
      (scrollbar-layout:layouter))

    (local layout
      (Layout {:name (or options.name "scroll-view")
               :children [scroll.layout scrollbar.layout]
               :measurer measurer
               :constrained-measurer constrained-measurer
               :layouter layouter}))

    (set view.layout layout)
    (local touch-target
      {:pointer-target pointer-target
       :layout scroll.layout
       :touch-drag-threshold touch-drag-threshold
       :intersect (fn [_self ray]
                    (scroll.layout:intersect ray))
       :on-touch-drag-candidate-start (fn [_self payload]
                                        (view:on-touch-drag-candidate-start payload))
       :on-touch-drag-candidate-end (fn [_self payload]
                                      (view:on-touch-drag-candidate-end payload))
       :on-touch-drag-candidate-cancel (fn [_self payload]
                                         (view:on-touch-drag-candidate-end payload))
       :on-touch-drag-start (fn [_self payload]
                              (view:on-touch-drag-start payload))
       :on-touch-drag (fn [_self payload]
                        (view:on-touch-drag payload))
       :on-touch-drag-end (fn [_self payload]
                            (view:on-touch-drag-end payload))
       :on-touch-drag-cancel (fn [_self payload]
                               (view:on-touch-drag-cancel payload))})
    (set view.intersect
         (fn [_self ray]
           (local bar-layout scrollbar.layout)
           (if (and state.scrollbar-visible? bar-layout)
               (bar-layout:intersect ray)
               (values false nil nil))))

    (fn register-hoverables []
      (hoverables:register view))

    (fn unregister-hoverables []
      (hoverables:unregister view))

    (fn register-touch-target []
      (when touch-gesture-targets
        (touch-gesture-targets:register touch-target)))

    (fn unregister-touch-target []
      (when touch-gesture-targets
        (touch-gesture-targets:unregister touch-target)))

    (when focus-manager
      (set view.__focus-listener
           (focus-manager.focus-focus.connect
             (fn [event]
               (local current (and event event.current))
               (when (and current (= event.reason :tab))
                 (ensure-node-visible current))))))

    (fn drop [_self]
      (stop-kinetic!)
      (unregister-hoverables)
      (unregister-touch-target)
      (when view.__focus-listener
        (when (and focus-manager focus-manager.focus-focus)
          (focus-manager.focus-focus.disconnect view.__focus-listener true))
        (set view.__focus-listener nil))
      (set (. scroll.layout :scroll-controller) nil)
      (layout:drop)
      (scroll:drop)
      (scrollbar:drop))

    (fn set-scroll-offset [_self offset opts]
      (stop-kinetic!)
      (clear-wheel-scroll!)
      (set state.user-set-offset? true)
      (set state.pending-reset? false)
      (set-scroll-offset-value (or offset 0) opts))

    (fn get-scroll-offset [_self]
      state.scroll-offset)

    (fn reset-scroll-position [_self opts]
      (stop-kinetic!)
      (clear-wheel-scroll!)
      (set state.user-set-offset? false)
      (set state.pending-reset? true)
      (if (= state.growth-anchor :bottom)
          (set-scroll-offset-value 0 opts)
          (set-scroll-offset-value state.max-offset opts)))

    (fn set-viewport-height [_self height opts]
      (local mark-measure-dirty? (resolve-mark-flag opts :mark-measure-dirty? true))
      (local desired (sanitize-height height))
      (when (not (approx-or-nil desired state.viewport-height))
        (set state.viewport-height desired)
        (when mark-measure-dirty?
          (layout:mark-measure-dirty))
        ))

    (set view.ensure-visible
         (fn [_self node]
           (ensure-node-visible node)))
    (set (. scroll.layout :scroll-controller) view)
    (set view.drop drop)
    (set view.set-scroll-offset set-scroll-offset)
    (set view.get-scroll-offset get-scroll-offset)
    (set view.reset-scroll-position reset-scroll-position)
    (set view.set-viewport-height set-viewport-height)
    (set view.on-mouse-wheel on-mouse-wheel)
    (set view.on-touch-drag-candidate-start on-touch-drag-candidate-start)
    (set view.on-touch-drag-candidate-end on-touch-drag-candidate-end)
    (set view.on-touch-drag-start on-touch-drag-start)
    (set view.on-touch-drag on-touch-drag)
    (set view.on-touch-drag-end on-touch-drag-end)
    (set view.on-touch-drag-cancel on-touch-drag-cancel)
    (set view.scrollbar scrollbar)
    (set view.scroll-area scroll)
    (register-hoverables)
    (register-touch-target)
    view))

ScrollView
