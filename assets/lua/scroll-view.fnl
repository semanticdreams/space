(local glm (require :glm))
(local {: Layout : resolve-mark-flag} (require :layout))
(local ScrollArea (require :scroll-area))
(local ScrollBar (require :scroll-bar))
(local MathUtils (require :math-utils))
(local BoundsUtils (require :bounds-utils))
(local Padding (require :padding))

(local scroll-epsilon 1e-5)

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
                  :initialized? false
                  :pending-reset? false
                  :user-set-offset? (not (= options.scroll-offset nil))})
    (local hoverables (assert ctx.hoverables "ScrollView requires ctx.hoverables"))
    (local focus-manager (and ctx ctx.focus ctx.focus.manager))
    (local view {:scroll scroll
                 :state state
                 :pointer-target pointer-target
                 :focus-manager focus-manager})

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
      (when (or (and (not state.user-set-offset?)
                     (or (not state.initialized?)
                         (and (<= previous-max scroll-epsilon)
                              (> max-offset scroll-epsilon))))
                (and state.pending-reset? (not state.user-set-offset?)))
        (set state.scroll-offset max-offset)
        (scroll:set-scroll-offset (glm.vec3 0 max-offset 0)
                                  {:mark-layout-dirty? mark-layout-dirty?})
        (set state.pending-reset? false))
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

    (fn on-mouse-wheel [_self payload]
      (if (not state.scroll-enabled?)
          false
          (do
            (local delta-y (or (and payload payload.y) 0))
            (if (= delta-y 0)
                false
                (do
                  (local step (wheel-step))
                  (set-scroll-offset-value (+ state.scroll-offset (* delta-y step)))
                  true)))))

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

    (fn layouter [self]
      (local scroll-layout scroll.layout)
      (local scrollbar-layout scrollbar.layout)
      (local content (scroll:get-content-size))
      (local content-height (or (and content content.y) 0))
      (local viewport-height (clamp-height self.size.y))
      (local needs-scroll? (> (- content-height viewport-height) scroll-epsilon))
      (local bar-visible? (scrollbar-visible? state.scrollbar-policy needs-scroll?))
      (local reserved-width
        (if bar-visible?
            (math.min scrollbar-width self.size.x)
            0))
      (local viewport-width (math.max 0 (- self.size.x reserved-width)))
      (local viewport-size (glm.vec3 viewport-width
                               viewport-height
                               self.size.z))
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
               :layouter layouter}))

    (set view.layout layout)
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

    (when focus-manager
      (set view.__focus-listener
           (focus-manager.focus-focus.connect
             (fn [event]
               (local current (and event event.current))
               (when (and current (= event.reason :tab))
                 (ensure-node-visible current))))))

    (fn drop [_self]
      (unregister-hoverables)
      (when view.__focus-listener
        (when (and focus-manager focus-manager.focus-focus)
          (focus-manager.focus-focus.disconnect view.__focus-listener true))
        (set view.__focus-listener nil))
      (set (. scroll.layout :scroll-controller) nil)
      (layout:drop)
      (scroll:drop)
      (scrollbar:drop))

    (fn set-scroll-offset [_self offset opts]
      (set state.user-set-offset? true)
      (set state.pending-reset? false)
      (set-scroll-offset-value (or offset 0) opts))

    (fn get-scroll-offset [_self]
      state.scroll-offset)

    (fn reset-scroll-position [_self opts]
      (set state.user-set-offset? false)
      (set state.pending-reset? true)
      (set-scroll-offset-value state.max-offset opts))

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
    (set view.scrollbar scrollbar)
    (register-hoverables)
    view))

ScrollView
