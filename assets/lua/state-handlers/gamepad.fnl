(local Common (require :state-handlers/common))

(local GamepadButtonDown
  {:gamepad-button-down
   (fn [ctx payload]
     (local controls ((. Common :controls-from) ctx))
     (when controls
       (controls:on-gamepad-button-down payload)))})

(local GamepadAxisMotion
  {:gamepad-axis-motion
   (fn [ctx payload]
     (local controls ((. Common :controls-from) ctx))
     (when controls
       (controls:on-gamepad-axis-motion payload)))})

(local GamepadRemoved
  {:gamepad-removed
   (fn [ctx payload]
     (local controls ((. Common :controls-from) ctx))
     (when controls
       (controls:on-gamepad-removed payload)))})

{:GamepadButtonDown GamepadButtonDown
 :GamepadAxisMotion GamepadAxisMotion
 :GamepadRemoved GamepadRemoved}
