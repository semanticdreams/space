(local glm (require :glm))
(local exports {})

(fn screen-pos->hud [screen-pos hud]
  (local x (or (and screen-pos screen-pos.x) 0))
  (local y (or (and screen-pos screen-pos.y) 0))
  (if (and hud hud.screen-pos-ray)
      (do
        (local ray (hud:screen-pos-ray {:x x :y y}))
        (if (and ray ray.origin ray.direction)
            (do
              (local dz (or ray.direction.z 0))
              (local t (if (not (= dz 0)) (/ (- 0 ray.origin.z) dz) 0))
              (+ ray.origin (* ray.direction t)))
            (glm.vec3 x y 0)))
      (glm.vec3 x y 0)))

(fn resolve-target-from-receiver [receiver]
  (receiver.target-fn))

(fn find-matching-receiver [receivers target]
  (when target
    (each [_ receiver (ipairs receivers)]
      (local candidate (resolve-target-from-receiver receiver))
      (when (= candidate target)
        (lua "return receiver")))))

(fn default-receive [target payload]
  (when (and target target.add-panel-child)
    (target:add-panel-child payload)))

(fn available-receivers-excluding [receivers exclude-target]
  (local available [])
  (each [_ receiver (ipairs receivers)]
    (local target (resolve-target-from-receiver receiver))
    (when (and target (not (= target exclude-target)))
      (local entry {:id receiver.id
                    :label receiver.label
                    :icon (or receiver.icon "open_with")
                    :target target
                    :receive (or receiver.receive
                                 (fn [_recv payload]
                                   (default-receive target payload)))
                    :rollback (or receiver.rollback
                                  (fn [_recv el]
                                    (if (and target target.remove-panel-child)
                                        (target:remove-panel-child el)
                                        (do
                                          (when (and el el.drop)
                                            (el:drop))
                                          true))))})
      (table.insert available entry)))
  available)

(fn show-move-menu [self options]
  (local opts (or options {}))
  (local current-target opts.current-target)
  (local event opts.event)
  (local on-transfer opts.on-transfer)
  (local menu-manager (or opts.menu-manager app.menu-manager))
  (local hud (or opts.hud app.hud))

  (assert menu-manager "PanelTransfer.show-move-menu requires menu manager")
  (assert hud "PanelTransfer.show-move-menu requires HUD")
  (assert on-transfer "PanelTransfer.show-move-menu requires :on-transfer callback")

  (local available (available-receivers-excluding self.receivers current-target))

  (when (> (length available) 0)
    (local screen-pos (or (and event event.screen) {:x 0 :y 0}))
    (local position (screen-pos->hud screen-pos hud))
    (local actions
      (icollect [_ receiver (ipairs available)]
        {:name (.. "Move to " receiver.label)
         :icon receiver.icon
         :fn (fn [_btn _evt]
               (on-transfer receiver))}))
    (menu-manager:open {:actions actions
                        :position position}))
  nil)

(fn transfer-panel [_self destination current element payload]
  (local new-element (destination.receive destination payload))
  (if (not new-element)
      (error (.. "Failed to transfer panel to " (or destination.label destination.id)))
      (do
        (local target-element (or element.__scene_wrapper element))
        (local removed (if (and current current.remove-panel-child target-element)
                            (current:remove-panel-child target-element)
                            (do
                              (when (and element element.drop)
                                (element:drop))
                              true)))
        (if removed
            new-element
            (do
              (var rolled-back false)
              (if destination.rollback
                  (set rolled-back (destination:rollback new-element))
                  (if (and destination.target destination.target.remove-panel-child)
                      (set rolled-back (destination.target:remove-panel-child new-element))
                      (do
                        (when (and new-element new-element.drop)
                          (new-element:drop))
                        (set rolled-back true))))
              (if (not rolled-back)
                  (error (.. "Panel transfer rollback failed for " (or destination.label destination.id) " - panel was received but could not be removed"))
                  (error "Failed to detach panel from source during transfer")))))))

(fn PanelTransfer []
  (local receivers [])
  {:receivers receivers
   :register-receiver (fn [_self receiver]
                        (assert (= (type receiver.id) :string) "Panel receiver requires string :id")
                        (assert (= (type receiver.label) :string) "Panel receiver requires string :label")
                        (assert (= (type receiver.target-fn) :function) "Panel receiver requires function :target-fn")
                        (when receiver.receive
                          (assert (= (type receiver.receive) :function) "Panel receiver :receive must be a function"))
                        (when receiver.rollback
                          (assert (= (type receiver.rollback) :function) "Panel receiver :rollback must be a function"))
                        (when receiver.receive
                          (assert receiver.rollback "Panel receiver with :receive requires :rollback"))
                        (table.insert receivers receiver)
                        receiver)
   :unregister-receiver (fn [_self receiver-id]
                          (for [i (length receivers) 1 -1]
                            (when (= (. receivers i :id) receiver-id)
                              (table.remove receivers i))))
   :available-receivers (fn [_self] (available-receivers-excluding receivers nil))
   :find-receiver-for-target (fn [_self target] (find-matching-receiver receivers target))
   :show-move-menu show-move-menu
   :transfer-panel transfer-panel})

(set exports.PanelTransfer PanelTransfer)
(set exports.default-receive default-receive)

(setmetatable exports {:__call (fn [_ ...] (PanelTransfer ...))})
exports
