(local SDL_BUTTON_LEFT 1)
(local SDL_BUTTON_RIGHT 3)
(local default-pointer-threshold 100) ; squared pixels
(local default-double-click-window 500) ; milliseconds
(local Intersectables (require :intersectables))

(fn square [v]
  (* v v))

(fn distance-squared [a b]
  (if (and a b)
      (+ (square (- a.x b.x)) (square (- a.y b.y)))
      math.huge))

(fn copy-list [items]
  (local clone [])
  (each [_ item (ipairs items)]
    (table.insert clone item))
  clone)

(fn contains? [items target]
  (var found false)
  (each [_ item (ipairs items)]
    (when (= item target)
      (set found true)))
  found)

(fn add-unique! [items target]
  (when (and target (not (contains? items target)))
    (table.insert items target)))

(fn remove-first! [items target]
  (var idx nil)
  (each [i item (ipairs items)]
    (when (and (not idx) (= item target))
      (set idx i)))
  (when idx
    (table.remove items idx)))

(fn Clickables [opts]
  (local intersector
         (or (and opts opts.intersectables)
             app.intersectables
             (Intersectables)))
  (local self {:left-click-objects []
               :right-click-objects []
               :double-click-objects []
               :left-click-void-callbacks []
               :right-click-void-callbacks []
               :active-entry nil
               :active? false
               :mouse-down-pos nil
               :last-click-time nil
               :last-click-pos nil
               :pointer-threshold default-pointer-threshold
               :double-click-window default-double-click-window})

  (fn pointer-pos [payload]
    (intersector:pointer payload))

  (fn near-pointer? [self a b]
    (and a b (< (distance-squared a b) self.pointer-threshold)))

  (fn build-target-list [self button]
    (if (= button SDL_BUTTON_LEFT)
        (let [targets (copy-list self.double-click-objects)]
          (each [_ obj (ipairs self.left-click-objects)]
            (table.insert targets obj))
          targets)
        (if (= button SDL_BUTTON_RIGHT)
            self.right-click-objects
            [])))

  (fn notify-pressed [entry pressed?]
    (local obj (and entry entry.object))
    (when (and obj obj.on-pressed)
      (obj:on-pressed pressed?)))

  (fn set-active-entry [self entry]
    (local previous self.active-entry)
    (when (and previous (not (= previous entry)))
      (notify-pressed previous false))
    (set self.active-entry entry)
    (set self.active? (not (= entry nil)))
    (when (and entry (not (= previous entry)))
      (notify-pressed entry true)))

  (fn clear-active [self]
    (set-active-entry self nil))

  (fn build-event [payload screen-pos ray entry]
    {:screen screen-pos
     :timestamp payload.timestamp
     :button payload.button
     :mod payload.mod
     :ray ray
     :point (and entry entry.point)
     :distance (and entry entry.distance)})

  (fn fire-void-callbacks [self payload screen-pos pointer]
    (local callbacks
      (if (= payload.button SDL_BUTTON_LEFT)
          self.left-click-void-callbacks
          (if (= payload.button SDL_BUTTON_RIGHT)
              self.right-click-void-callbacks
              [])))
    (when (> (length callbacks) 0)
      (local ray (intersector:resolve-ray pointer nil))
      (local event (build-event payload screen-pos ray nil))
      (each [_ cb (ipairs callbacks)]
        (cb event))))

  (fn remember-click [self payload screen-pos]
    (when payload.timestamp
      (set self.last-click-time payload.timestamp)
      (set self.last-click-pos screen-pos)))

  (fn clear-last-click [self]
    (set self.last-click-time nil)
    (set self.last-click-pos nil))

  (fn double-click? [self obj payload screen-pos]
    (and obj
         payload.timestamp
         self.last-click-time
         (contains? self.double-click-objects obj)
         (< (math.abs (- payload.timestamp self.last-click-time)) self.double-click-window)
         (near-pointer? self screen-pos self.last-click-pos)))

  (fn dispatch-click [self payload screen-pos pointer]
    (local entry self.active-entry)
    (local obj (and entry entry.object))
    (when obj
      (local ray (intersector:resolve-ray pointer (or entry.pointer-target obj.pointer-target)))
      (when ray
        (local event (build-event payload screen-pos ray entry))
        (if (= payload.button SDL_BUTTON_LEFT)
            (do
              (local handler obj.on-click)
              (when handler
                (obj:on-click event))
              (if (double-click? self obj payload screen-pos)
                  (do
                    (local double-handler obj.on-double-click)
                    (when double-handler
                      (obj:on-double-click event))
                    (clear-last-click self))
                  (remember-click self payload screen-pos)))
            (do
              (when (= payload.button SDL_BUTTON_RIGHT)
                (local handler obj.on-right-click)
                (when handler
                  (obj:on-right-click event))))))))

  (fn on-mouse-button-down [self payload]
    (local pointer (pointer-pos payload))
    (set self.mouse-down-pos pointer)
    (if (and payload.button)
        (let [targets (build-target-list self payload.button)
              entry (intersector:select-entry targets pointer {:include-point true})]
          (when entry
            (set entry.button payload.button))
          (set-active-entry self entry))
        (clear-active self)))

  (fn on-mouse-button-up [self payload]
    (local screen-pos (pointer-pos payload))
    (when (and payload.button (near-pointer? self screen-pos self.mouse-down-pos))
      (if (and self.active-entry (= payload.button self.active-entry.button))
          (dispatch-click self payload screen-pos screen-pos)
          (fire-void-callbacks self payload screen-pos screen-pos)))
    (clear-active self)
    (set self.mouse-down-pos nil))

  (fn register [self obj]
    (add-unique! self.left-click-objects obj))

  (fn unregister [self obj]
    (remove-first! self.left-click-objects obj))

  (fn register-right-click [self obj]
    (add-unique! self.right-click-objects obj))

  (fn unregister-right-click [self obj]
    (remove-first! self.right-click-objects obj))

  (fn register-double-click [self obj]
    (add-unique! self.double-click-objects obj))

  (fn unregister-double-click [self obj]
    (remove-first! self.double-click-objects obj))

  (fn register-left-click-void-callback [self cb]
    (add-unique! self.left-click-void-callbacks cb))

  (fn unregister-left-click-void-callback [self cb]
    (remove-first! self.left-click-void-callbacks cb))

  (fn register-right-click-void-callback [self cb]
    (add-unique! self.right-click-void-callbacks cb))

  (fn unregister-right-click-void-callback [self cb]
    (remove-first! self.right-click-void-callbacks cb))

  (fn drop [self]
    (set self.left-click-objects [])
    (set self.right-click-objects [])
    (set self.double-click-objects [])
    (set self.left-click-void-callbacks [])
    (set self.right-click-void-callbacks [])
    (clear-active self)
    (clear-last-click self)
    (set self.mouse-down-pos nil))

  (set self.register register)
  (set self.unregister unregister)
  (set self.register-right-click register-right-click)
  (set self.unregister-right-click unregister-right-click)
  (set self.register-double-click register-double-click)
  (set self.unregister-double-click unregister-double-click)
  (set self.register-left-click-void-callback register-left-click-void-callback)
  (set self.unregister-left-click-void-callback unregister-left-click-void-callback)
  (set self.register-right-click-void-callback register-right-click-void-callback)
  (set self.unregister-right-click-void-callback unregister-right-click-void-callback)
  (set self.on-mouse-button-down on-mouse-button-down)
  (set self.on-mouse-button-up on-mouse-button-up)
  (set self.drop drop)
  self
  )

Clickables
