(local glm (require :glm))
(local textures (require :textures))
(local {:VectorBuffer VectorBuffer} (require :vector-buffer))

(fn vec3 [x y z]
  (glm.vec3 x y z))

(fn clamp [value minv maxv]
  (if (< value minv)
      minv
      (if (> value maxv)
          maxv
          value)))

(fn write-vertex [vector handle offset vertex]
  (vector:set-float handle (+ offset 0) (. vertex 1))
  (vector:set-float handle (+ offset 1) (. vertex 2))
  (vector:set-float handle (+ offset 2) (. vertex 3))
  (vector:set-float handle (+ offset 3) (. vertex 4))
  (vector:set-float handle (+ offset 4) (. vertex 5))
  (vector:set-float handle (+ offset 5) (. vertex 6))
  (vector:set-float handle (+ offset 6) (. vertex 7))
  (vector:set-float handle (+ offset 7) (. vertex 8)))

(fn face-vertices [center axis-u axis-v normal half-size]
  (local u (* axis-u half-size))
  (local v (* axis-v half-size))
  (local p1 (+ center (- (- (vec3 0 0 0) u) v)))
  (local p2 (+ center (- u v)))
  (local p3 (+ center (+ u v)))
  (local p4 (+ center (+ (- (vec3 0 0 0) u) v)))
  [
   [0 0 normal.x normal.y normal.z p1.x p1.y p1.z]
   [1 0 normal.x normal.y normal.z p2.x p2.y p2.z]
   [1 1 normal.x normal.y normal.z p3.x p3.y p3.z]
   [0 0 normal.x normal.y normal.z p1.x p1.y p1.z]
   [1 1 normal.x normal.y normal.z p3.x p3.y p3.z]
   [0 1 normal.x normal.y normal.z p4.x p4.y p4.z]])

(fn make-face-specs [center half-size]
  [
   {:name "front"
    :center (+ center (vec3 0 0 half-size))
    :normal (vec3 0 0 1)
    :axis-u (vec3 1 0 0)
    :axis-v (vec3 0 1 0)}
   {:name "back"
    :center (+ center (vec3 0 0 (- half-size)))
    :normal (vec3 0 0 -1)
    :axis-u (vec3 -1 0 0)
    :axis-v (vec3 0 1 0)}
   {:name "right"
    :center (+ center (vec3 half-size 0 0))
    :normal (vec3 1 0 0)
    :axis-u (vec3 0 0 -1)
    :axis-v (vec3 0 1 0)}
   {:name "left"
    :center (+ center (vec3 (- half-size) 0 0))
    :normal (vec3 -1 0 0)
    :axis-u (vec3 0 0 1)
    :axis-v (vec3 0 1 0)}
   {:name "top"
    :center (+ center (vec3 0 half-size 0))
    :normal (vec3 0 1 0)
    :axis-u (vec3 1 0 0)
    :axis-v (vec3 0 0 -1)}
   {:name "bottom"
    :center (+ center (vec3 0 (- half-size) 0))
    :normal (vec3 0 -1 0)
    :axis-u (vec3 1 0 0)
    :axis-v (vec3 0 0 1)}])

(fn intersect-face [face ray half-size]
  (local denom (glm.dot ray.direction face.normal))
  (if (< (math.abs denom) 1e-6)
      nil
      (do
        (local t (/ (glm.dot (- face.center ray.origin) face.normal) denom))
        (if (<= t 0)
            nil
            (do
              (local point (+ ray.origin (* ray.direction (vec3 t t t))))
              (local rel (- point face.center))
              (local local-u (/ (glm.dot rel face.axis-u) half-size))
              (local local-v (/ (glm.dot rel face.axis-v) half-size))
              (if (or (> (math.abs local-u) 1.0) (> (math.abs local-v) 1.0))
                  nil
                  (do
                    (local u (clamp (* (+ local-u 1.0) 0.5) 0.0 1.0))
                    (local v (clamp (- 1.0 (* (+ local-v 1.0) 0.5)) 0.0 1.0))
                    {:distance t
                     :point point
                     :u u
                     :v v})))))))

(fn pick-face [faces pointer half-size]
  (if (not app.scene)
      nil
      (do
        (local (ok ray-or-error) (pcall (fn [] (app.scene:screen-pos-ray pointer))))
        (if (or (not ok) (not ray-or-error))
            nil
            (do
              (local ray ray-or-error)
              (var nearest nil)
              (each [_ face (ipairs faces)]
                (local hit (intersect-face face ray half-size))
                (when (and hit (or (not nearest) (< hit.distance nearest.distance)))
                  (set nearest {:face face
                                :distance hit.distance
                                :u hit.u
                                :v hit.v
                                :point hit.point})))
              nearest)))))

(fn pointer->pixel [hit width height]
  {:x (math.floor (* hit.u (- width 1)))
   :y (math.floor (* hit.v (- height 1)))} )

(fn create-face-surface [browser id url texture-name width height max-fps]
  (local create-surface (assert (. browser "create-surface")
                                "engine.browser.create-surface is required"))
  (local created
    (create-surface {:id id
                     :url url
                     :texture-name texture-name
                     :width width
                     :height height
                     :max-fps max-fps}))
  (assert created (.. "failed to create browser surface: " id))
  (local texture (textures.get-texture texture-name))
  (assert texture (.. "failed to resolve browser texture: " texture-name))
  texture)

(fn BrowserCubeSurface [opts]
  (local options (or opts {}))
  (assert (and app app.engine app.engine.browser)
          "BrowserCubeSurface requires app.engine.browser")
  (assert (and app.scene app.scene.build-context)
          "BrowserCubeSurface requires app.scene.build-context")

  (local browser app.engine.browser)
  (local set-focus (assert (. browser "set-focus") "engine.browser.set-focus is required"))
  (local send-mouse-move (assert (. browser "send-mouse-move") "engine.browser.send-mouse-move is required"))
  (local send-mouse-click (assert (. browser "send-mouse-click") "engine.browser.send-mouse-click is required"))
  (local send-mouse-wheel (assert (. browser "send-mouse-wheel") "engine.browser.send-mouse-wheel is required"))
  (local destroy-surface (assert (. browser "destroy-surface") "engine.browser.destroy-surface is required"))
  (local ctx app.scene.build-context)
  (local center (or options.center (vec3 0 4 -24)))
  (local size (or options.size 8.0))
  (local half-size (/ size 2.0))
  (local width (or options.width 1024))
  (local height (or options.height 1024))
  (local max-fps (or options.max-fps 30))
  (local default-smoke-url
    "data:text/html,%3Chtml%3E%3Cbody%20style%3D%27margin%3A0%3Bbackground%3A%23f8fafc%3Bfont-family%3Asans-serif%3Bdisplay%3Aflex%3Balign-items%3Acenter%3Bjustify-content%3Acenter%3Bheight%3A100vh%3B%27%3E%3Cdiv%20style%3D%27font-size%3A96px%3Bcolor%3A%230f172a%3Bfont-weight%3A700%3B%27%3ECEF%20OK%3C/div%3E%3C/body%3E%3C/html%3E")
  (local base-url (or options.url default-smoke-url))
  (local urls (or options.urls []))
  (local id-prefix (or options.id-prefix "browser-cube"))

  (local faces (make-face-specs center half-size))
  (var mesh-entries [])
  (var surface-ids [])
  (var handlers {})
  (var active-face nil)
  (var hover-face nil)

  (fn focus-face [face-id]
    (each [_ face (ipairs faces)]
      (set-focus face.surface-id (= face.surface-id face-id))))

(fn send-move [face pixel leave?]
    (send-mouse-move face.surface-id pixel.x pixel.y (or leave? false)))

  (fn on-motion [payload]
    (local hit (pick-face faces {:x payload.x :y payload.y} half-size))
    (if hit
        (do
          (set hover-face hit.face)
          (local pixel (pointer->pixel hit width height))
          (send-move hit.face pixel false)
          (if active-face
              (do
                (set active-face.last-pixel pixel)
                (set active-face.last-pointer {:x payload.x :y payload.y}))))
        (when hover-face
          (send-mouse-move hover-face.surface-id 0 0 true)
          (set hover-face nil))))

  (fn on-button-down [payload]
    (local hit (pick-face faces {:x payload.x :y payload.y} half-size))
    (when hit
      (set active-face hit.face)
      (set active-face.last-pointer {:x payload.x :y payload.y})
      (set active-face.last-pixel (pointer->pixel hit width height))
      (focus-face active-face.surface-id)
      (send-mouse-click active-face.surface-id
                        active-face.last-pixel.x
                        active-face.last-pixel.y
                        payload.button
                        false
                        (or payload.clicks 1))))

  (fn on-button-up [payload]
    (local face active-face)
    (if (not face)
        nil
        (do
          (local pixel face.last-pixel)
          (send-mouse-click face.surface-id
                            pixel.x
                            pixel.y
                            payload.button
                            true
                            (or payload.clicks 1))
          (set active-face nil))))

  (fn on-wheel [payload]
    (local mouse (and app.engine app.engine.input app.engine.input.mouse))
    (when mouse
      (local hit (pick-face faces {:x mouse.x :y mouse.y} half-size))
      (when hit
        (local pixel (pointer->pixel hit width height))
        (send-mouse-wheel hit.face.surface-id pixel.x pixel.y payload.x payload.y))))

  (each [idx face (ipairs faces)]
    (local url (if (> (length urls) 0) (. urls idx) base-url))
    (local surface-id (.. id-prefix "-" face.name))
    (local texture-name (.. "browser/" surface-id))
    (local texture (create-face-surface browser surface-id url texture-name width height max-fps))
    (set face.surface-id surface-id)
    (set face.texture-name texture-name)
    (table.insert surface-ids surface-id)

    (local vertices (face-vertices face.center face.axis-u face.axis-v face.normal half-size))
    (local vector (VectorBuffer))
    (local handle (vector:allocate (* (length vertices) 8)))
    (for [i 1 (length vertices)]
      (local offset (* (- i 1) 8))
      (write-vertex vector handle offset (. vertices i)))

    (local batch {:vector vector
                  :texture texture
                  :visible? true
                  :force-opaque true
                  :unlit true
                  :model (glm.mat4 1)})
    (ctx:register-mesh-batch batch)
    (table.insert mesh-entries {:vector vector
                                :handle handle
                                :batch batch}))

  (set handlers.mouse-motion (app.engine.events.mouse-motion:connect on-motion))
  (set handlers.mouse-button-down (app.engine.events.mouse-button-down:connect on-button-down))
  (set handlers.mouse-button-up (app.engine.events.mouse-button-up:connect on-button-up))
  (set handlers.mouse-wheel (app.engine.events.mouse-wheel:connect on-wheel))

  (fn drop [_self]
    (when handlers.mouse-motion
      (app.engine.events.mouse-motion:disconnect handlers.mouse-motion true)
      (set handlers.mouse-motion nil))
    (when handlers.mouse-button-down
      (app.engine.events.mouse-button-down:disconnect handlers.mouse-button-down true)
      (set handlers.mouse-button-down nil))
    (when handlers.mouse-button-up
      (app.engine.events.mouse-button-up:disconnect handlers.mouse-button-up true)
      (set handlers.mouse-button-up nil))
    (when handlers.mouse-wheel
      (app.engine.events.mouse-wheel:disconnect handlers.mouse-wheel true)
      (set handlers.mouse-wheel nil))

    (when hover-face
      (send-mouse-move hover-face.surface-id 0 0 true)
      (set hover-face nil))

    (each [_ entry (ipairs mesh-entries)]
      (ctx:unregister-mesh-batch entry.batch)
      (entry.vector:delete entry.handle))
    (set mesh-entries [])

    (each [_ surface-id (ipairs surface-ids)]
      (destroy-surface surface-id))
    (set surface-ids []))

  {:drop drop
   :faces faces})

BrowserCubeSurface
