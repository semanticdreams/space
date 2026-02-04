(local KMOD_LSHIFT 1)
(local KMOD_RSHIFT 2)
(local KMOD_LCTRL 64)
(local KMOD_RCTRL 128)
(local KMOD_LALT 256)
(local KMOD_RALT 512)

(fn bit-set? [value mask]
  (and mask (> mask 0)
       (>= (math.fmod (math.floor (/ value mask)) 2) 1)))

(fn shift-held? [mod]
  (local value (or mod 0))
  (or (bit-set? value KMOD_LSHIFT)
      (bit-set? value KMOD_RSHIFT)))

(fn ctrl-held? [mod]
  (local value (or mod 0))
  (or (bit-set? value KMOD_LCTRL)
      (bit-set? value KMOD_RCTRL)))

(fn alt-held? [mod]
  (local value (or mod 0))
  (or (bit-set? value KMOD_LALT)
      (bit-set? value KMOD_RALT)))

{:bit-set? bit-set?
 :shift-held? shift-held?
 :ctrl-held? ctrl-held?
 :alt-held? alt-held?}
