(local glm (require :glm))
(local SDL_BUTTON_RIGHT 3)
(local Intersectables (require :intersectables))

(local default-drag-threshold 16) ; squared pixels

(fn square [v]
  (* v v))

(fn distance-squared [a b]
  (if (and a b)
      (+ (square (- a.x b.x)) (square (- a.y b.y)))
      math.huge))

(fn resolve-plane-normal []
  (local camera app.camera)
  (if (and camera camera.get-forward)
      (camera:get-forward)
      (glm.vec3 0 0 -1)))

(fn make-plane [point]
  (when point
    {:point point
     :normal (resolve-plane-normal)}))

(fn ray-plane-intersection [ray plane]
  (when (and ray plane plane.normal plane.point)
    (local direction ray.direction)
    (local denom (glm.dot plane.normal direction))
    (if (> (math.abs denom) 1e-6)
        (do
          (local difference (- plane.point ray.origin))
          (local t (/ (glm.dot difference plane.normal) denom))
          (if (>= t 0)
              (+ ray.origin (* direction (glm.vec3 t)))
              nil))
        nil)))

(fn resolve-target-layout [target]
  (or (and target target.layout) target))

(fn resolve-target-position [target]
  (local layout (resolve-target-layout target))
  (or (and target target.position)
      (and layout layout.position)
      (glm.vec3 0 0 0)))

(fn resolve-target-size [target]
  (local layout (resolve-target-layout target))
  (or (and target target.size)
      (and layout layout.size)
      (glm.vec3 0 0 0)))

(fn resolve-target-rotation [target]
  (local layout (resolve-target-layout target))
  (or (and target target.rotation)
      (and layout layout.rotation)
      (glm.quat 1 0 0 0)))

(fn apply-target-position [target position]
  (when position
    (if (and target target.set-position)
        (target:set-position position)
        (do
          (set target.position position)
          (when (and target target.mark-layout-dirty)
            (target:mark-layout-dirty))))))

(fn apply-target-size [target size]
  (when size
    (if (and target target.set-size)
        (target:set-size size)
        (do
          (set target.size size)
          (when (and target target.mark-layout-dirty)
            (target:mark-layout-dirty))))))

(fn edge-sign [value size]
  (if (< (math.abs value) (math.abs (- size value)))
      -1
      1))

(fn update-axis [edge value size min-size]
  (if (= edge 1)
      (do
        (local resolved (math.max value min-size))
        (values resolved 0))
      (do
        (local max-offset (- size min-size))
        (local min-offset (math.min value max-offset))
        (local resolved (- size min-offset))
        (values resolved min-offset))))

(fn Resizables [opts]
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
        (set self.drag nil))
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

  (fn resolve-target [_self widget options]
    (or (and options options.target)
        (and widget widget.layout)
        widget))

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
                    :min-size (and options options.min-size)
                    :on-resize-start (and options options.on-resize-start)
                    :on-resize-end (and options options.on-resize-end)})
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

  (fn start-resize [_self drag]
    (when (and drag (not drag.started?))
      (set drag.started? true)
      (local entry drag.entry)
      (var updated nil)
      (when (and entry entry.on-resize-start)
        (set updated (entry.on-resize-start entry drag)))
      (local resolved (or updated entry))
      (set drag.entry resolved)
      (local target resolved.target)
      (when target
        (local position (resolve-target-position target))
        (local rotation (resolve-target-rotation target))
        (local size (resolve-target-size target))
        (local min-size (or resolved.min-size (glm.vec3 0 0 0)))
        (local inverse (rotation:inverse))
        (local local-hit (inverse:rotate (- drag.hit-point position)))
        (set drag.position position)
        (set drag.rotation rotation)
        (set drag.size size)
        (set drag.min-size min-size)
        (set drag.edge-x (edge-sign local-hit.x size.x))
        (set drag.edge-y (edge-sign local-hit.y size.y))
        (set drag.plane (make-plane drag.hit-point)))))

  (fn ensure-resize-started [self pointer]
    (local drag self.drag)
    (when (and drag (not drag.started?))
      (if (<= self.drag-threshold 0)
          (start-resize self drag)
          (when (>= (distance-squared pointer drag.start-pointer) self.drag-threshold)
            (start-resize self drag)))))

  (fn begin-resize [self payload]
    (local pointer (self.intersector:pointer payload))
    (local selection (self.intersector:select-entry self.objects pointer {:include-point true}))
    (if selection
        (do
          (local entry (rawget self.entry-map selection.object))
          (local hit-point selection.point)
          (local target (and entry entry.target))
          (when (and entry target hit-point)
            (set self.drag {:entry entry
                            :button payload.button
                            :pointer-target (or selection.pointer-target entry.pointer-target)
                            :hit-point hit-point
                            :start-pointer pointer
                            :started? false})
            (ensure-resize-started self pointer)
            true))
        (do
          (set self.drag nil)
          false)))

  (fn update-resize [self payload]
    (local drag self.drag)
    (when (and drag drag.started?)
      (local pointer (self.intersector:pointer payload))
      (local ray (self.intersector:resolve-ray pointer drag.pointer-target))
      (local hit (ray-plane-intersection ray drag.plane))
      (when (and hit drag.entry drag.entry.target)
        (local rotation drag.rotation)
        (local inverse (rotation:inverse))
        (local local-hit (inverse:rotate (- hit drag.position)))
        (local min-size drag.min-size)
        (local (size-x offset-x)
          (update-axis drag.edge-x local-hit.x drag.size.x min-size.x))
        (local (size-y offset-y)
          (update-axis drag.edge-y local-hit.y drag.size.y min-size.y))
        (local size (glm.vec3 size-x size-y (. drag.size 3)))
        (local offset (glm.vec3 offset-x offset-y 0))
        (local world-position (+ drag.position (rotation:rotate offset)))
        (apply-target-position drag.entry.target world-position)
        (apply-target-size drag.entry.target size))))

  (fn end-resize [self]
    (when self.drag
      (local entry self.drag.entry)
      (local started? (and self.drag self.drag.started?))
      (set self.drag nil)
      (when (and started? entry entry.on-resize-end)
        (entry.on-resize-end entry))))

  (fn on-mouse-button-down [self payload]
    (when (and payload (= payload.button SDL_BUTTON_RIGHT))
      (begin-resize self payload)))

  (fn on-mouse-button-up [self payload]
    (when (and payload (= payload.button SDL_BUTTON_RIGHT))
      (end-resize self)))

  (fn on-mouse-motion [self payload]
    (when self.drag
      (local pointer (self.intersector:pointer payload))
      (ensure-resize-started self pointer)
      (when (and self.drag self.drag.started?)
        (update-resize self payload))))

  (fn drag-active? [self]
    (and self.drag self.drag.started?))

  (fn drag-engaged? [self]
    (not (= self.drag nil)))

  (fn drop [self]
    (set self.objects [])
    (set self.entries [])
    (set self.entry-map {})
    (set self.key-map {})
    (set self.drag nil))

  (set self.register register)
  (set self.unregister unregister)
  (set self.on-mouse-button-down on-mouse-button-down)
  (set self.on-mouse-button-up on-mouse-button-up)
  (set self.on-mouse-motion on-mouse-motion)
  (set self.drag-active? drag-active?)
  (set self.drag-engaged? drag-engaged?)
  (set self.drop drop)
  self)

Resizables
