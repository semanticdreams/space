(local glm (require :glm))
(local SDL_BUTTON_LEFT 1)
(local default-drag-threshold 16) ; squared pixels
(local Intersectables (require :intersectables))

(fn safe-offset [target-point hit-point]
  (if (and target-point hit-point)
      (- target-point hit-point)
      (glm.vec3 0 0 0)))

(fn square [v]
  (* v v))

(fn distance-squared [a b]
  (if (and a b)
      (+ (square (- a.x b.x)) (square (- a.y b.y)))
      math.huge))

(fn normalize-or [v fallback]
  (if (and v (> (glm.length v) 1e-6))
      (glm.normalize v)
      fallback))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn assert-finite-vec3 [vec label]
  (when (or (not vec)
            (not (finite-number? vec.x))
            (not (finite-number? vec.y))
            (not (finite-number? vec.z)))
    (error (.. "Movables received non-finite " label))))

(fn resolve-plane-normal []
  (local camera app.camera)
  (normalize-or
    (and camera camera.get-forward (camera:get-forward))
    (glm.vec3 0 0 -1)))

(fn make-plane [point]
  (when point
    {:point point
     :normal (resolve-plane-normal)}))

(fn ray-plane-intersection [ray plane]
  (when (and ray plane plane.normal plane.point)
    (local direction ray.direction)
    (assert-finite-vec3 ray.origin "ray origin")
    (assert-finite-vec3 direction "ray direction")
    (assert-finite-vec3 plane.point "plane point")
    (assert-finite-vec3 plane.normal "plane normal")
    (local denom (glm.dot plane.normal direction))
    (if (> (math.abs denom) 1e-6)
        (let [difference (- plane.point ray.origin)
              t (/ (glm.dot difference plane.normal) denom)]
          (if (>= t 0)
              (+ ray.origin (* direction (glm.vec3 t)))
              nil))
        nil)))

(fn Movables [opts]
  (local intersector
         (or (and opts opts.intersectables)
             app.intersectables
             (Intersectables)))
  (local self {:intersector intersector
               :objects []
               :entries []
               :entry-map {}
               :key-map {}
               :drag nil
               :drag-threshold (or (and opts opts.drag-threshold) default-drag-threshold)})
  (fn end-drag [self]
    (when self.drag
      (local entry self.drag.entry)
      (local started? (and self.drag self.drag.started?))
      (set self.drag nil)
      (when (and started? entry entry.on-drag-end)
        (entry.on-drag-end entry))))

  (fn start-drag [_self drag]
    (when (and drag (not drag.started?))
      (set drag.started? true)
      (local entry drag.entry)
      (when (and entry entry.on-drag-start)
        (entry.on-drag-start entry))
      (local target (and entry entry.target))
      (local hit-point drag.hit-point)
      (when (and target hit-point)
        (local plane (make-plane hit-point))
        (local offset (safe-offset target.position hit-point))
        (set drag.plane plane)
        (set drag.offset offset))))

  (fn ensure-drag-started [self pointer]
    (local drag self.drag)
    (when (and drag (not drag.started?))
      (if (<= self.drag-threshold 0)
          (start-drag self drag)
          (when (>= (distance-squared pointer drag.start-pointer) self.drag-threshold)
            (start-drag self drag)))))

  (fn resolve-target [_self widget options]
    (or (and options options.target)
        (and widget widget.layout)
        nil))

  (fn resolve-handle [_self widget target options]
    (local handle (or (and options options.handle) widget target))
    (if (and handle handle.intersect)
        handle
        (if (and target target.intersect)
            target
            nil)))

  (fn resolve-pointer-target [_self widget handle options]
    (or (and options options.pointer-target)
        (and handle handle.pointer-target)
        (and widget widget.pointer-target)
        app.scene))

  (fn make-selection-object [_self entry]
    (local selection {})
    (set selection.pointer-target entry.pointer-target)
    (set selection.intersect
         (fn [_obj ray]
           (if (and entry.handle entry.handle.intersect)
               (entry.handle:intersect ray)
               (values false nil nil))))
    (set entry.selection selection)
    selection)

  (fn remove-entry [self entry]
    (when entry
      (when (and self.drag (= self.drag.entry entry))
        (end-drag self))
      (local selection entry.selection)
      (when selection
        (var remove-idx nil)
        (each [i obj (ipairs self.objects)]
          (when (and (not remove-idx) (= obj selection))
            (set remove-idx i)))
        (when remove-idx
          (table.remove self.objects remove-idx))
        (set (. self.entry-map selection) nil))
      (var entry-idx nil)
      (each [i candidate (ipairs self.entries)]
        (when (and (not entry-idx) (= candidate entry))
          (set entry-idx i)))
      (when entry-idx
        (table.remove self.entries entry-idx))
      (when entry.key
        (set (. self.key-map entry.key) nil))))

  (fn find-entry [self key]
    (if (not key)
        nil
        (or (rawget self.key-map key)
            (accumulate [found nil _ entry (ipairs self.entries)]
                        (if found
                            found
                            (if (or (= entry.source key)
                                    (= entry.target key))
                                entry
                                nil))))))

(fn register [self widget options]
    (local target (resolve-target self widget options))
    (local handle (resolve-handle self widget target options))
    (local pointer-target (resolve-pointer-target self widget handle options))
    (when (and target handle)
      (local entry {:source widget
                    :target target
                    :handle handle
                    :pointer-target pointer-target
                    :key (or (and options options.key) widget)
                    :on-drag-start (and options options.on-drag-start)
                    :on-drag-end (and options options.on-drag-end)})
      (when entry.key
        (remove-entry self (find-entry self entry.key)))
      (local selection (make-selection-object self entry))
      (table.insert self.objects selection)
      (table.insert self.entries entry)
      (set (. self.entry-map selection) entry)
      (when entry.key
        (set (. self.key-map entry.key) entry))
      entry))

  (fn unregister [self key]
    (remove-entry self (find-entry self key)))

  (fn begin-drag [self payload]
    (local pointer (self.intersector:pointer payload))
    (local selection (self.intersector:select-entry self.objects pointer {:include-point true}))
    (if selection
        (let [entry (rawget self.entry-map selection.object)
              hit-point selection.point
              target entry.target]
          (when (and entry target hit-point)
            (set self.drag {:entry entry
                            :button payload.button
                            :pointer-target (or selection.pointer-target entry.pointer-target)
                            :hit-point hit-point
                            :start-pointer pointer
                            :started? false})
            (ensure-drag-started self pointer)
            true))
        (do
          (set self.drag nil)
          false)))

  (fn update-drag [self payload]
    (local drag self.drag)
    (when (and drag drag.started?)
      (local pointer (self.intersector:pointer payload))
      (local ray (self.intersector:resolve-ray pointer drag.pointer-target))
      (local hit (ray-plane-intersection ray drag.plane))
      (when (and hit drag.entry drag.entry.target)
        (local new-position (+ hit drag.offset))
        (assert-finite-vec3 new-position "drag position")
        (drag.entry.target:set-position new-position))))

  (fn on-mouse-button-down [self payload]
    (when (and payload (= payload.button SDL_BUTTON_LEFT))
      (begin-drag self payload)))

  (fn on-mouse-button-up [self payload]
    (when (and payload (= payload.button SDL_BUTTON_LEFT))
      (end-drag self)))

  (fn on-mouse-motion [self payload]
    (when self.drag
      (local pointer (self.intersector:pointer payload))
      (ensure-drag-started self pointer)
      (when (and self.drag self.drag.started?)
        (update-drag self payload))))

  (fn drag-active? [self]
    (and self.drag self.drag.started?))

  (fn drag-engaged? [self]
    (not (= self.drag nil)))

  (fn drop [self]
    (end-drag self)
    (set self.objects [])
    (set self.entries [])
    (set self.entry-map {})
    (set self.key-map {}))

  (set self.register register)
  (set self.unregister unregister)
  (set self.on-mouse-button-down on-mouse-button-down)
  (set self.on-mouse-button-up on-mouse-button-up)
  (set self.on-mouse-motion on-mouse-motion)
  (set self.drag-active? drag-active?)
  (set self.drag-engaged? drag-engaged?)
  (set self.drop drop)
  self)

Movables
