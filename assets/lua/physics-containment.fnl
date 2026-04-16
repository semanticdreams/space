(local glm (require :glm))
(local bt (require :bt))
(local MathUtils (require :math-utils))
(local RuntimeTimers (require :runtime-timers))

(local array->vec3 (. MathUtils :array->vec3))
(local vec3->array (. MathUtils :vec3->array))
(local default-mode "automatic-terrain-bounds")
(local default-manual-bounds {:min (glm.vec3 -500 -500 -500)
                              :max (glm.vec3 500 500 500)})
(local default-padding {:horizontal 0.0
                        :bottom 50.0
                        :top 500.0})
(local default-restitution 1.0)
(local default-debounce-ms 1000.0)
(local default-visualization {:enabled true})

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn approx= [left right]
  (< (math.abs (- left right)) 1e-6))

(fn vec3-approx= [left right]
  (and left
       right
       (approx= left.x right.x)
       (approx= left.y right.y)
       (approx= left.z right.z)))

(fn bounds-approx= [left right]
  (and left
       right
       (vec3-approx= left.min right.min)
       (vec3-approx= left.max right.max)))

(fn available? []
  (and bt app.engine app.engine.physics))

(fn vec3-value [value fallback]
  (local resolved
    (if (= value nil)
        nil
        (if (= (type value) :userdata)
            value
            (if (= (type value) :table)
                (do
                  (local (ok parsed) (pcall array->vec3 value))
                  (if ok parsed nil))
                nil))))
  (if (and resolved
           (finite-number? resolved.x)
           (finite-number? resolved.y)
           (finite-number? resolved.z))
      resolved
      fallback))

(fn normalize-bounds [value]
  (local source (or value {}))
  (local min-bound (vec3-value source.min default-manual-bounds.min))
  (local max-bound (vec3-value source.max default-manual-bounds.max))
  (assert (< min-bound.x max-bound.x) "PhysicsContainment bounds require min.x < max.x")
  (assert (< min-bound.y max-bound.y) "PhysicsContainment bounds require min.y < max.y")
  (assert (< min-bound.z max-bound.z) "PhysicsContainment bounds require min.z < max.z")
  {:min min-bound
   :max max-bound})

(fn normalize-padding [value]
  (local source (or value {}))
  (local horizontal
    (if (and (finite-number? source.horizontal) (>= source.horizontal 0))
        source.horizontal
        default-padding.horizontal))
  (local bottom
    (if (and (finite-number? source.bottom) (>= source.bottom 0))
        source.bottom
        default-padding.bottom))
  (local top
    (if (and (finite-number? source.top) (>= source.top 0))
        source.top
        default-padding.top))
  {:horizontal horizontal
   :bottom bottom
   :top top})

(fn normalize-config [value]
  (local source (or value {}))
  (local mode
    (if (= source.mode "manual-bounds")
        "manual-bounds"
        default-mode))
  (local restitution
    (if (finite-number? source.restitution)
        source.restitution
        default-restitution))
  (local debounce-ms
    (if (and (finite-number? source.debounce-ms)
             (>= source.debounce-ms 0))
        source.debounce-ms
        default-debounce-ms))
  (local visualization-source
    (if (= (type source.visualization) :table)
        source.visualization
        {}))
  (local visualization-enabled
    (if (= visualization-source.enabled nil)
        default-visualization.enabled
        (not (not visualization-source.enabled))))
  {:mode mode
   :bounds (normalize-bounds source.bounds)
   :padding (normalize-padding source.padding)
   :restitution restitution
   :debounce-ms debounce-ms
   :visualization {:enabled visualization-enabled}})

(fn serialize-config [value]
  (local config (normalize-config value))
  {:mode config.mode
   :bounds {:min (vec3->array config.bounds.min)
            :max (vec3->array config.bounds.max)}
   :padding {:horizontal config.padding.horizontal
             :bottom config.padding.bottom
             :top config.padding.top}
   :restitution config.restitution
   :debounce-ms config.debounce-ms
   :visualization {:enabled config.visualization.enabled}})

(fn default-config []
  (normalize-config {}))

(fn world-aabb-from-local-bounds [position rotation local-min local-max]
  (local min-corner (glm.vec3 500000 500000 500000))
  (local max-corner (glm.vec3 -500000 -500000 -500000))
  (for [ix 0 1]
    (for [iy 0 1]
      (for [iz 0 1]
        (local corner
          (glm.vec3 (if (= ix 0) local-min.x local-max.x)
                    (if (= iy 0) local-min.y local-max.y)
                    (if (= iz 0) local-min.z local-max.z)))
        (local world-point (+ position (rotation:rotate corner)))
        (when (< world-point.x min-corner.x)
          (set min-corner.x world-point.x))
        (when (< world-point.y min-corner.y)
          (set min-corner.y world-point.y))
        (when (< world-point.z min-corner.z)
          (set min-corner.z world-point.z))
        (when (> world-point.x max-corner.x)
          (set max-corner.x world-point.x))
        (when (> world-point.y max-corner.y)
          (set max-corner.y world-point.y))
        (when (> world-point.z max-corner.z)
          (set max-corner.z world-point.z)))))
  {:min min-corner
   :max max-corner})

(fn terrain-bounds [metadata]
  (local element (and metadata metadata.element))
  (local layout (and element element.layout))
  (assert (and element element.get-local-bounds)
          "PhysicsContainment automatic bounds require terrain element:get-local-bounds")
  (assert layout
          "PhysicsContainment automatic bounds require terrain element layout")
  (local local-bounds (element:get-local-bounds))
  (assert (and local-bounds local-bounds.min local-bounds.max)
          "PhysicsContainment automatic bounds require terrain local bounds")
  (world-aabb-from-local-bounds
    layout.position
    layout.rotation
    local-bounds.min
    local-bounds.max))

(fn combine-bounds [left right]
  (if (not left)
      right
      (if (not right)
          left
          {:min (glm.vec3 (math.min left.min.x right.min.x)
                          (math.min left.min.y right.min.y)
                          (math.min left.min.z right.min.z))
           :max (glm.vec3 (math.max left.max.x right.max.x)
                          (math.max left.max.y right.max.y)
                          (math.max left.max.z right.max.z))})))

(fn automatic-terrain-bounds [scene]
  (var combined nil)
  (each [_ metadata (ipairs (or (and scene scene.scene-terrains) []))]
    (set combined (combine-bounds combined (terrain-bounds metadata))))
  combined)

(fn padded-bounds [bounds padding]
  {:min (glm.vec3 (- bounds.min.x padding.horizontal)
                  (- bounds.min.y padding.bottom)
                  (- bounds.min.z padding.horizontal))
   :max (glm.vec3 (+ bounds.max.x padding.horizontal)
                  (+ bounds.max.y padding.top)
                  (+ bounds.max.z padding.horizontal))})

(fn resolve-active-bounds [config scene]
  (local terrain
    (if (= config.mode "automatic-terrain-bounds")
        (automatic-terrain-bounds scene)
        nil))
  (if terrain
      (padded-bounds terrain config.padding)
      config.bounds))

(fn plane-specs [bounds]
  [{:key "min-x" :normal (bt.Vector3 1 0 0) :constant bounds.min.x}
   {:key "max-x" :normal (bt.Vector3 -1 0 0) :constant (- bounds.max.x)}
   {:key "min-y" :normal (bt.Vector3 0 1 0) :constant bounds.min.y}
   {:key "max-y" :normal (bt.Vector3 0 -1 0) :constant (- bounds.max.y)}
   {:key "min-z" :normal (bt.Vector3 0 0 1) :constant bounds.min.z}
   {:key "max-z" :normal (bt.Vector3 0 0 -1) :constant (- bounds.max.z)}])

(fn drop-installed []
  (local existing app.__physics-global-containment)
  (when (and existing existing.visualization existing.visualization.drop)
    (existing.visualization:drop))
  (when (and existing existing.planes)
    (each [_ plane (ipairs existing.planes)]
      (when (and plane plane.body plane.physics)
        (pcall (fn []
                 (plane.physics:removeRigidBody plane.body))))))
  (set app.__physics-global-containment nil))

(fn containment-corners [bounds]
  (local min bounds.min)
  (local max bounds.max)
  {:a (glm.vec3 min.x min.y min.z)
   :b (glm.vec3 max.x min.y min.z)
   :c (glm.vec3 max.x min.y max.z)
   :d (glm.vec3 min.x min.y max.z)
   :e (glm.vec3 min.x max.y min.z)
   :f (glm.vec3 max.x max.y min.z)
   :g (glm.vec3 max.x max.y max.z)
   :h (glm.vec3 min.x max.y max.z)})

(fn resolve-active-theme []
  (and app.themes
       app.themes.get-active-theme
       (app.themes.get-active-theme)))

(fn resolve-visualization-color []
  (do
    (local theme (resolve-active-theme))
    (local containment-theme (and theme theme.physics-containment))
    (local visualization-theme (and containment-theme containment-theme.visualization))
    (local theme-color (and visualization-theme visualization-theme.color))
    (or theme-color
        (error "PhysicsContainment visualization requires theme physics-containment.visualization.color"))))

(fn create-visualization [scene bounds config]
  (local lines (and scene scene.build-context scene.build-context.lines))
  (if (or (not lines)
          (not config.visualization.enabled))
      nil
      (do
        (local corners (containment-corners bounds))
        (local edge-color (resolve-visualization-color))
        (local edge-segments [])

        (fn add-segment [segments start end]
          (table.insert segments {:start start
                                  :end end}))

        ;; box edges
        (add-segment edge-segments corners.a corners.b)
        (add-segment edge-segments corners.b corners.c)
        (add-segment edge-segments corners.c corners.d)
        (add-segment edge-segments corners.d corners.a)
        (add-segment edge-segments corners.e corners.f)
        (add-segment edge-segments corners.f corners.g)
        (add-segment edge-segments corners.g corners.h)
        (add-segment edge-segments corners.h corners.e)
        (add-segment edge-segments corners.a corners.e)
        (add-segment edge-segments corners.b corners.f)
        (add-segment edge-segments corners.c corners.g)
        (add-segment edge-segments corners.d corners.h)
        (local edge-batch (lines:create-line-batch {:segments edge-segments
                                                    :color edge-color}))

        {:drop (fn [_self]
                 (when (and edge-batch edge-batch.drop)
                   (edge-batch:drop)))
         :line-count (length edge-segments)})))

(fn install-plane [physics spec restitution]
  (local shape (bt.StaticPlaneShape spec.normal spec.constant))
  (local transform (bt.Transform))
  (transform:setIdentity)
  (local motion-state (bt.DefaultMotionState transform))
  (local zero (bt.Vector3 0 0 0))
  (local info (bt.RigidBodyConstructionInfo 0 motion-state shape zero))
  (set info.m-restitution restitution)
  (local body (bt.RigidBody info))
  (physics:addRigidBody body)
  {:key spec.key
   :shape shape
   :motion-state motion-state
   :body body
   :physics physics
   :constant spec.constant})

(fn ensure-installed [opts]
  (if (not (available?))
      false
      (do
        (local options (or opts {}))
        (local config (normalize-config (or options.config app.physics-containment-config)))
        (local scene (or options.scene app.physics-containment-scene))
        (when (and scene scene.update)
          (scene:update))
        (local bounds (resolve-active-bounds config scene))
        (local physics app.engine.physics)
        (local existing app.__physics-global-containment)
        (local already-installed?
          (and existing
               (= existing.physics physics)
               (= existing.restitution config.restitution)
               (bounds-approx= existing.bounds bounds)
               (= existing.mode config.mode)))
        (set app.physics-containment-config (serialize-config config))
        (set app.physics-containment-scene scene)
        (if already-installed?
            true
            (do
              (drop-installed)
              (local planes
                (icollect [_ spec (ipairs (plane-specs bounds))]
                  (install-plane physics spec config.restitution)))
              (set app.__physics-global-containment
                   {:physics physics
                    :bounds bounds
                    :mode config.mode
                    :restitution config.restitution
                    :planes planes
                    :visualization (create-visualization scene bounds config)})
              true)))))

(fn refresh-visualization [opts]
  (local existing app.__physics-global-containment)
  (if (not existing)
      false
      (do
        (local options (or opts {}))
        (local config (normalize-config (or options.config app.physics-containment-config)))
        (local scene (or options.scene app.physics-containment-scene))
        (set app.physics-containment-config (serialize-config config))
        (set app.physics-containment-scene scene)
        (when (and existing.visualization existing.visualization.drop)
          (existing.visualization:drop))
        (set existing.visualization (create-visualization scene existing.bounds config))
        true)))

(fn ensure-refresh-debouncer []
  (if app.__physics_containment_refresh_debouncer
      app.__physics_containment_refresh_debouncer
      (do
        (set app.__physics_containment_refresh_debouncer
             (RuntimeTimers.Debouncer
               {:delay-ms default-debounce-ms
                :callback
                (fn [payload]
                  (when payload
                    (ensure-installed {:scene payload.scene
                                       :config payload.config})))}))
        app.__physics_containment_refresh_debouncer)))

(fn schedule-refresh [opts]
  (local options (or opts {}))
  (local config (normalize-config (or options.config app.physics-containment-config)))
  (local scene (or options.scene app.physics-containment-scene))
  (set app.physics-containment-config (serialize-config config))
  (set app.physics-containment-scene scene)
  (if (<= config.debounce-ms 0)
      (do
        (when app.__physics_containment_refresh_debouncer
          (app.__physics_containment_refresh_debouncer:cancel))
        (ensure-installed {:scene scene
                           :config config}))
      (do
        (local debouncer (ensure-refresh-debouncer))
        (debouncer:cancel)
        (debouncer:set-delay-ms config.debounce-ms)
        (debouncer:trigger {:scene scene
                            :config config})))
  true)

(fn clear []
  (when app.__physics_containment_refresh_debouncer
    (app.__physics_containment_refresh_debouncer:drop)
    (set app.__physics_containment_refresh_debouncer nil))
  (drop-installed)
  (set app.physics-containment-scene nil)
  true)

{:available? available?
 :default-mode default-mode
 :default-manual-bounds default-manual-bounds
 :default-padding default-padding
 :default-restitution default-restitution
 :default-debounce-ms default-debounce-ms
 :default-visualization default-visualization
 :default-config default-config
 :normalize-config normalize-config
 :serialize-config serialize-config
 :automatic-terrain-bounds automatic-terrain-bounds
 :resolve-active-bounds resolve-active-bounds
 :ensure-installed ensure-installed
 :refresh-visualization refresh-visualization
 :schedule-refresh schedule-refresh
 :clear clear}
