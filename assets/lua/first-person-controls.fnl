(local glm (require :glm))
(local default-key-mapping
  {:move-left 97        ; a
   :move-right 101      ; e
   :move-forward 44     ; ,
   :move-backward 111   ; o
   :look-up 1073741906  ; arrow up
   :look-down 1073741905; arrow down
   :look-right 1073741904; arrow right
   :look-left 1073741903 ; arrow left
   :speed 32})          ; space

(local SDL_BUTTON_LEFT 1)
(local SDL_BUTTON_RIGHT 3)
(local SDLK_ESCAPE 27)
(local SDLK_LCTRL 1073742048)

(fn clone-table [source]
  (local copy {})
  (when source
    (each [k v (pairs source)]
      (set (. copy k) v)))
  copy)

(fn merge-key-mappings [custom]
  (local merged (clone-table default-key-mapping))
  (when custom
    (each [k v (pairs custom)]
      (set (. merged k) v)))
  merged)

(fn vec2-add [a b]
  (glm.vec2 (+ a.x b.x) (+ a.y b.y)))

(fn vec2-scale [v scalar]
  (glm.vec2 (* v.x scalar) (* v.y scalar)))

(fn vec2-any? [v]
  (or (not (= v.x 0)) (not (= v.y 0))))

(fn vec2-length [v]
  (math.sqrt (+ (* v.x v.x) (* v.y v.y))))

(fn vec2-clamp [v max-value]
  (local clamp (fn [component]
                 (math.min max-value (math.max (- max-value) component))))
  (glm.vec2 (clamp v.x) (clamp v.y)))

(fn signed-power-shape [value exponent]
  (if (= value 0)
      0
      (* value (^ (math.abs value) exponent))))

(fn FirstPersonControls [opts]
  (local options (or opts {}))
  (local camera (or options.camera app.camera))
  (assert camera "FirstPersonControls requires a camera")

  (local key-mapping (merge-key-mappings options.key-mapping))
  (local self
    {:camera camera
     :movement-speed (or options.movement-speed 10.0)
     :look-speed (or options.look-speed 1.0)
     :mouse-look-speed (or options.mouse-look-speed 0.001)
     :mouse-move-speed (or options.mouse-move-speed 0.2)
     :speed-multiplier 1.0
     :look-speed-multiplier 1.0
     :scroll-speed (glm.vec2 0 0)
     :max-scroll-speed (or options.max-scroll-speed 5.0)
     :scroll-acceleration (or options.scroll-acceleration 2.5)
     :scroll-deceleration (or options.scroll-deceleration 0.99)
     :drag-look-start nil
     :drag-move-start nil
     :keys {}
     :key-mapping key-mapping
     :mouse-pos nil
     :on-exit options.on-exit
     :controller {:which nil :axes {}}})

  (fn reset-controller [self]
    (set self.controller.which nil)
    (set self.controller.axes {}))

  (fn action-active? [self action]
    (local key (. self.key-mapping action))
    (and key (. self.keys key)))

  (fn depth-scale [self]
    (math.max 1000.0 (math.abs self.camera.position.z)))

  (fn add-scroll [self dx dy]
    (local magnitude (* self.scroll-acceleration (depth-scale self) 0.001))
    (local delta (glm.vec2 (* dx magnitude) (* dy magnitude)))
    (set self.scroll-speed (vec2-add self.scroll-speed delta)))

  (fn reset-scroll [self]
    (set self.scroll-speed (glm.vec2 0 0)))

  (fn pointer-position []
    (if self.mouse-pos
        self.mouse-pos
        (let [viewport (or app.viewport {:x 0 :y 0 :width 0 :height 0})]
          {:x (+ viewport.x (/ viewport.width 2))
           :y (+ viewport.y (/ viewport.height 2))})))

  (fn mouse-buttons []
    (or app.engine.mouse-buttons
        {:left SDL_BUTTON_LEFT
         :right SDL_BUTTON_RIGHT}))

  (fn zoom-along-ray [amount]
    (local ray-fn app.screen-pos-ray)
    (when (and ray-fn (> amount 0))
      (let [pointer (pointer-position)]
        (let [(ok ray) (pcall ray-fn pointer)]
          (when (and ok ray)
            (local direction ray.direction)
            (when direction
              (local offset (* direction (glm.vec3 amount)))
              (self.camera:set-position (+ self.camera.position offset))
              true))))))

  (fn scroll-update [self delta]
    (when (vec2-any? self.scroll-speed)
      (local shaped-x (signed-power-shape self.scroll-speed.x 1.4))
      (local shaped-y (signed-power-shape self.scroll-speed.y 1.4))
      (local magnitude (* self.movement-speed self.speed-multiplier 0.09))
      (local zoom-x (* shaped-x magnitude))
      (local zoom-y (* shaped-y magnitude))
      (when (not (= zoom-x 0))
        (self.camera:right zoom-x))
      (if (not (. self.keys SDLK_LCTRL))
          (if (> zoom-y 0)
              (when (not (zoom-along-ray zoom-y))
                (self.camera:forward zoom-y))
              (self.camera:forward zoom-y))
          (self.camera:up zoom-y))
      (local decay (^ self.scroll-deceleration delta))
      (set self.scroll-speed (vec2-scale self.scroll-speed decay))
      (when (< (vec2-length self.scroll-speed) 0.01)
        (set self.scroll-speed (glm.vec2 0 0)))
      (set self.scroll-speed (vec2-clamp self.scroll-speed self.max-scroll-speed))))

  (fn controller-axes [self idx]
    (or (. self.controller.axes idx) 0.0))

  (fn update-controller [self delta]
    (when self.controller.which
      (local threshold 0.1)
      (fn filtered [axis]
        (local value (controller-axes self axis))
        (if (and (> value (- threshold)) (< value threshold))
            0.0
            value))
      (local move-speed 0.4)
      (local look-speed 0.003)
      (local trigger-move-speed 0.8)
      (self.camera:right (* delta move-speed (filtered 0)))
      (self.camera:forward (* delta move-speed (- 0 (filtered 1))))
      (self.camera:yaw (* delta look-speed (- 0 (filtered 2))))
      (self.camera:pitch (* delta look-speed (- 0 (filtered 3))))
      (self.camera:forward (* delta trigger-move-speed (* 0.5 (+ (filtered 5) 1.0))))
      (self.camera:forward (* delta trigger-move-speed (* -0.5 (+ (filtered 4) 1.0))))))

  (fn on-key-down [self payload]
    (set (. self.keys payload.key) true)
    (when (and (= payload.key SDLK_ESCAPE) self.on-exit)
      (self.on-exit payload)))

  (fn on-key-up [self payload]
    (set (. self.keys payload.key) nil))

  (fn on-mouse-wheel [self payload]
    (self:add-scroll payload.x payload.y))

  (fn update-mouse-pos [self payload]
    (set self.mouse-pos {:x payload.x :y payload.y}))

  (fn apply-mouse-state [self]
    (local mouse (and app.engine app.engine.input app.engine.input.mouse))
    (when mouse
      (set self.mouse-pos {:x mouse.x :y mouse.y})
      ;; Event handlers handle rotation/drag; snapshot keeps last position in sync.
      ))

  (fn handle-mouse-button [self payload fallback-state]
    (update-mouse-pos self payload)
    (local state (or payload.state fallback-state))
    (when (= payload.button SDL_BUTTON_LEFT)
      (if (= state 1)
          (set self.drag-look-start {:x payload.x :y payload.y})
          (set self.drag-look-start nil)))
    (when (= payload.button SDL_BUTTON_RIGHT)
      (if (= state 1)
          (set self.drag-move-start {:x payload.x :y payload.y})
          (set self.drag-move-start nil))))

  (fn on-mouse-button-down [self payload]
    (handle-mouse-button self payload 1))

  (fn on-mouse-button-up [self payload]
    (handle-mouse-button self payload 0))

  (fn on-mouse-motion [self payload]
    (update-mouse-pos self payload)
    (when self.drag-look-start
      (local dx (- payload.x self.drag-look-start.x))
      (local dy (- payload.y self.drag-look-start.y))
      (set self.drag-look-start {:x payload.x :y payload.y})
      (self.camera:yaw (* dx self.mouse-look-speed))
      (self.camera:pitch (* dy self.mouse-look-speed)))
    (when self.drag-move-start
      (local dx (- payload.x self.drag-move-start.x))
      (local dy (- payload.y self.drag-move-start.y))
      (set self.drag-move-start {:x payload.x :y payload.y})
      (local speed (* self.mouse-move-speed (math.abs self.camera.position.z) 0.006))
      (self.camera:right (* (- dx) speed))
      (self.camera:up (* dy speed))))

  (fn on-controller-button-down [self payload]
    (when (and (not self.controller.which) payload.which)
      (set self.controller.which payload.which))
    (when (and self.on-exit (= payload.button 20))
      (self.on-exit payload)))

  (fn on-controller-axis-motion [self payload]
    (when (or (not self.controller.which) (= self.controller.which payload.which))
      (when (not self.controller.which)
        (set self.controller.which payload.which))
      (set (. self.controller.axes payload.axis) payload.value)))

  (fn on-controller-device-removed [self payload]
    (when (= self.controller.which payload.which)
      (reset-controller self)))

  (fn drag-active? [self]
    (or self.drag-look-start self.drag-move-start))

  (fn drop [self]
    (reset-controller self)
    (self:reset-scroll)
    (set self.drag-look-start nil)
    (set self.drag-move-start nil)
    (set self.keys {}))

  (fn update [self delta]
    (if (self:action-active? :speed)
        (do
          (set self.speed-multiplier (+ self.speed-multiplier (* delta 20)))
          (set self.look-speed-multiplier 2))
        (do
          (set self.speed-multiplier (math.max 1 (- self.speed-multiplier (* delta 100))))
          (set self.look-speed-multiplier 1)))
    (self:scroll-update delta)
    (when (self:action-active? :move-left)
      (self.camera:right (* -1 delta self.movement-speed self.speed-multiplier)))
    (when (self:action-active? :move-right)
      (self.camera:right (* delta self.movement-speed self.speed-multiplier)))
    (when (self:action-active? :move-forward)
      (self.camera:forward (* delta self.movement-speed self.speed-multiplier)))
    (when (self:action-active? :move-backward)
      (self.camera:forward (* -1 delta self.movement-speed self.speed-multiplier)))
    (when (self:action-active? :move-up)
      (self.camera:up (* delta self.movement-speed self.speed-multiplier)))
    (when (self:action-active? :move-down)
      (self.camera:up (* -1 delta self.movement-speed self.speed-multiplier)))
    (when (self:action-active? :look-up)
      (self.camera:pitch (* delta self.look-speed self.look-speed-multiplier)))
    (when (self:action-active? :look-down)
      (self.camera:pitch (* -1 delta self.look-speed self.look-speed-multiplier)))
    (when (self:action-active? :look-right)
      (self.camera:yaw (* delta self.look-speed self.look-speed-multiplier)))
    (when (self:action-active? :look-left)
      (self.camera:yaw (* -1 delta self.look-speed self.look-speed-multiplier)))
    (when (self:action-active? :roll-left)
      (self.camera:roll (* delta self.look-speed self.look-speed-multiplier)))
    (when (self:action-active? :roll-right)
      (self.camera:roll (* -1 delta self.look-speed self.look-speed-multiplier)))
    (apply-mouse-state self)
    (update-controller self delta))

  (set self.add-scroll add-scroll)
  (set self.reset-scroll reset-scroll)
  (set self.scroll-update scroll-update)
  (set self.update update)
  (set self.drop drop)
  (set self.drag-active? drag-active?)
  (set self.action-active? action-active?)
  (set self.on-key-down on-key-down)
  (set self.on-key-up on-key-up)
  (set self.on-mouse-wheel on-mouse-wheel)
  (set self.on-mouse-button-down on-mouse-button-down)
  (set self.on-mouse-button-up on-mouse-button-up)
  (set self.on-mouse-motion on-mouse-motion)
  (set self.on-controller-button-down on-controller-button-down)
  (set self.on-controller-axis-motion on-controller-axis-motion)
  (set self.on-controller-device-removed on-controller-device-removed)

  self)

{: FirstPersonControls
 : default-key-mapping}
