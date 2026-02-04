(local glm (require :glm))
(local Rectangle (require :rectangle))
(local Stack (require :stack))
(local MathUtils (require :math-utils))

(local value-epsilon 1e-6)

(fn clamp [value min-value max-value]
  (math.max min-value (math.min max-value value)))

(local approx (fn [a b] (MathUtils.approx a b {:epsilon value-epsilon})))

(fn ScrollBar [opts]
  (local options (or opts {}))

  (fn build [ctx]
    (local track-color (or options.track-color (glm.vec4 0.15 0.15 0.15 0.55)))
    (local thumb-color (or options.thumb-color (glm.vec4 0.75 0.75 0.8 1.0)))
    (local track-builder (Rectangle {:color track-color}))
    (local thumb-builder (Rectangle {:color thumb-color}))
    (local stack ((Stack {:children [track-builder thumb-builder]}) ctx))
    (local track (. stack.children 1))
    (local thumb (. stack.children 2))
    (local layout stack.layout)
    (local base-layouter layout.layouter)
    (local pointer-target
      (or options.pointer-target
          (and ctx ctx.pointer-target)))
    (local thickness (math.max 0.2 (or options.width options.thickness 0.75)))
    (local min-thumb (math.max 0.2 (or options.min-thumb-length 0.6)))
    (local thumb-target {:position (glm.vec3 0 0 0)})
    (local state {:track track
                  :thumb thumb
                  :pointer-target pointer-target
                  :thickness thickness
                  :min-thumb min-thumb
                  :value (clamp (or options.value 0) 0 1)
                  :visible-ratio 1
                  :enabled? false
                  :visible? true
                  :frame nil
                  :movable-entry nil
                  :thumb-target thumb-target
                  :on-change options.on-value-changed})
    (local bar {:track track
                :thumb thumb
                :state state})

    (fn apply-thumb-transform []
      (local frame state.frame)
      (when (and frame state.enabled?)
        (local offset (* state.value frame.travel))
        (local local-offset (glm.vec3 0 offset 0))
        (local rotated (frame.rotation:rotate local-offset))
        (local world-position (+ frame.origin rotated))
        (local thumb-layout state.thumb.layout)
        (when thumb-layout
          (set thumb-layout.position world-position)
          (set thumb-layout.rotation frame.rotation)
          (set thumb-layout.size (glm.vec3 frame.width frame.thumb-length frame.depth))
          (set thumb-layout.clip-region frame.clip-region))
        (set thumb-target.position world-position)))

    (fn set-value [self value emit?]
      (local clamped (clamp value 0 1))
      (if (approx clamped state.value)
          nil
          (do
            (set state.value clamped)
            (apply-thumb-transform)
            (when (and emit? state.on-change)
              (state.on-change self clamped)))))

    (fn value-from-position [position]
      (local frame state.frame)
      (if (and frame state.enabled? position)
          (let [relative (- position frame.origin)
                local-pos (frame.inverse-rotation:rotate relative)
                axis (math.max 0 (math.min local-pos.y frame.travel))]
            (if (> frame.travel 0)
                (/ axis frame.travel)
                0))
          state.value))

    (set thumb-target.set-position
         (fn [_target position]
           (when (and state.enabled? position)
             (set-value bar (value-from-position position) true))))

    (fn register-movable []
      (when (and ctx ctx.movables (not state.movable-entry))
        (set state.movable-entry
             (ctx.movables:register state.thumb
                                      {:target thumb-target
                                       :handle state.thumb.layout
                                       :pointer-target pointer-target
                                       :key thumb-target}))))

    (fn unregister-movable []
      (when (and ctx ctx.movables state.movable-entry)
        (ctx.movables:unregister thumb-target)
        (set state.movable-entry nil)))

    (fn measurer [self]
      (track.layout:measurer)
      (thumb.layout:measurer)
      (set self.measure (glm.vec3 state.thickness 0 0))
      )

    (fn layouter [self]
      (if (not state.visible?)
          (do
            (track:set-visible false {:mark-layout-dirty? false})
            (thumb:set-visible false {:mark-layout-dirty? false})
            (local track-layout track.layout)
            (local thumb-layout thumb.layout)
            (when track-layout
              (set track-layout.size (glm.vec3 0 0 0))
              (set track-layout.position self.position))
            (when thumb-layout
              (set thumb-layout.size (glm.vec3 0 0 0))
              (set thumb-layout.position self.position))
            (set thumb-target.position self.position)
            (unregister-movable))
          (do
            (base-layouter self)
            (track:set-visible true {:mark-layout-dirty? false})
            (local track-layout track.layout)
            (local thumb-layout thumb.layout)
            (local track-width (math.max self.size.x state.thickness))
            (local track-height (math.max 0 self.size.y))
            (set track-layout.size (glm.vec3 track-width track-height self.size.z))
            (set track-layout.position self.position)
            (set track-layout.rotation self.rotation)
            (set track-layout.clip-region self.clip-region)
            (track.layout:layouter)
            (local ratio (clamp state.visible-ratio 0 1))
            (local thumb-length
                  (if (> track-height 0)
                      (math.max state.min-thumb
                                (math.min track-height (* track-height ratio)))
                      0))
            (local travel (math.max 0 (- track-height thumb-length)))
            (local frame {:origin self.position
                          :rotation self.rotation
                          :inverse-rotation (self.rotation:inverse)
                          :width track-width
                          :depth self.size.z
                          :thumb-length thumb-length
                          :travel travel
                          :depth-index self.depth-offset-index
                          :clip-region self.clip-region})
            (set state.frame frame)
            (if (and track-height (> thumb-length 0) state.enabled?)
                (thumb:set-visible true {:mark-layout-dirty? false})
                (do
                  (thumb:set-visible false {:mark-layout-dirty? false})
                  (when thumb-layout
                    (set thumb-layout.size (glm.vec3 0 0 0))
                    (set thumb-layout.position self.position))
                  (set thumb-target.position self.position)))
            (when (and thumb-layout state.enabled?)
              (set thumb-layout.size (glm.vec3 track-width thumb-length self.size.z))
              (set thumb-layout.clip-region self.clip-region))
            (apply-thumb-transform)
            (when state.enabled?
              (thumb.layout:layouter))
            (register-movable)))
      )

    (set layout.name (or options.name "scroll-bar"))
    (set layout.measurer measurer)
    (set layout.layouter layouter)
    (set bar.layout layout)

    (fn set-scroll-state [_self data opts]
      (local ratio (clamp (or data.visible-ratio state.visible-ratio) 0 1))
      (local visible? (if (not (= data.visible? nil))
                          (not (not data.visible?))
                          state.visible?))
      (local enabled? (if (not (= data.enabled? nil))
                          (not (not data.enabled?))
                          (< ratio 0.999)))
      (local mark-layout-dirty?
            (if (and opts (not (= opts.mark-layout-dirty? nil)))
                (not (not opts.mark-layout-dirty?))
                true))
      (set state.visible-ratio ratio)
      (set state.visible? visible?)
      (set state.enabled? enabled?)
      (set-value bar (or data.value state.value) false)
      (when mark-layout-dirty?
        (layout:mark-layout-dirty)))

    (fn drop [_self]
      (unregister-movable)
      (stack:drop))

    (set bar.drop drop)
    (set bar.set-scroll-state set-scroll-state)
    (set bar.set-value (fn [_self value]
                         (set-value bar value false)))
    (register-movable)
    bar)

  build)

ScrollBar
