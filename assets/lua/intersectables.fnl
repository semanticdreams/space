(local distance-epsilon 1e-5)

(fn copy-table [source]
  (if source
      (let [clone {}]
        (each [k v (pairs source)]
          (set (. clone k) v))
        clone)
      nil))

(fn default-pointer []
  {:x 0 :y 0})

(fn pointer-from-payload [payload]
  (if payload
      (let [pos {:x (or payload.x 0)
                 :y (or payload.y 0)}]
        (each [k v (pairs payload)]
          (when (and (not (= k :x)) (not (= k :y)))
            (set (. pos k) v)))
        pos)
      (default-pointer)))

(fn safe-space-ray [pointer]
  (when (and pointer app.screen-pos-ray)
    (let [(ok ray) (pcall app.screen-pos-ray pointer)]
      (if ok ray nil))))

(fn approx-distance= [a b]
  (< (math.abs (- a b)) distance-epsilon))

(fn entry-depth-offset-index [obj]
  (or (and obj obj.depth-offset-index)
      (and obj obj.layout obj.layout.depth-offset-index)
      0))

(fn closer-entry? [candidate current]
  (if (not candidate)
      false
      (if (not current)
          true
          (if (< candidate.distance current.distance)
              true
              (if (approx-distance= candidate.distance current.distance)
                  (> candidate.depth-offset-index current.depth-offset-index)
                  false)))))

(fn Intersectables []
  (local self {:ray-cache {}
               :last-pointer nil})

  (fn same-pointer? [a b]
    (and a b (= a.x b.x) (= a.y b.y)))

  (fn ensure-pointer-cache [self pointer]
    (if (not pointer)
        (do
          (set self.last-pointer nil)
          (set self.ray-cache {}))
        (when (not (same-pointer? self.last-pointer pointer))
          (set self.last-pointer (copy-table pointer))
          (set self.ray-cache {}))))

  (fn resolve-ray [self pointer target]
    (when pointer
      (ensure-pointer-cache self pointer)
      (local key (or target :space))
      (if (rawget self.ray-cache key)
          (rawget self.ray-cache key)
          (let [ray
                (if (and target target.screen-pos-ray)
                    (let [(ok result) (pcall target.screen-pos-ray target pointer)]
                      (if ok result (safe-space-ray pointer)))
                    (safe-space-ray pointer))]
            (rawset self.ray-cache key ray)
            ray))))

  (fn select-entry [self objects pointer opts]
    (ensure-pointer-cache self pointer)
    (var closest-hud nil)
    (var closest-scene nil)
    (local other-order [])
    (local other-closest {})

    (fn update-closest [current entry]
      (if (closer-entry? entry current)
          entry
          current))

    (fn remember-other [target entry]
      (local key (or target :space))
      (local existing (rawget other-closest key))
      (when (closer-entry? entry existing)
        (rawset other-closest key entry))
      (var seen false)
      (each [_ item (ipairs other-order)]
        (when (= item key)
          (set seen true)))
      (when (not seen)
        (table.insert other-order key)))

    (each [_ obj (ipairs (or objects []))]
      (when (and obj obj.intersect)
        (local target obj.pointer-target)
        (local ray (resolve-ray self pointer target))
        (when ray
          (let [(hit point distance) (obj:intersect ray)]
            (when (and hit distance)
              (local entry {:object obj
                            :pointer-target target
                            :distance distance
                            :depth-offset-index (entry-depth-offset-index obj)})
              (when (and opts opts.include-point)
                (set entry.point point))
              (local is-hud (and app.hud (= target app.hud)))
              (local is-scene (or is-hud (and app.scene (= target app.scene)) (not target)))
              (when is-hud
                (set closest-hud (update-closest closest-hud entry))
                (set closest-scene (update-closest closest-scene entry)))
              (when (and is-scene (not is-hud))
                (set closest-scene (update-closest closest-scene entry)))
              (when (not (or is-hud is-scene))
                (remember-other target entry)))))))

    (or closest-hud
        closest-scene
        (if (> (# other-order) 0)
            (rawget other-closest (. other-order 1))
            nil)))

  (fn pointer [self payload]
    (pointer-from-payload payload))

  (fn clear [self]
    (set self.ray-cache {})
    (set self.last-pointer nil))

  (fn drop [self]
    (clear self))

  (set self.pointer pointer)
  (set self.select-entry select-entry)
  (set self.resolve-ray resolve-ray)
  (set self.drop drop)
  self)

Intersectables
