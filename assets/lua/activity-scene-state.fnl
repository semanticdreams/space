;; Canonical scene-session state shape, default/empty factories, and validation.
;; Canonical state keys: :panels, :terrains, :lights, :skybox, :background, :containment.
;; Each subsystem normalizer is delegated to for its own state normalization.

(local SkyboxState (require :skybox-state))
(local BackgroundState (require :background-state))
(local TerrainRecords (require :scene-terrain-records))
(local PhysicsContainment (require :physics-containment))

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn clone-array [value]
  (if (= (type value) :table)
      (icollect [_ v (ipairs value)]
        (clone-table v))
      value))

(fn empty-panels [] [])

(fn empty-terrains [] [])

(fn default-sandbox-terrains []
  (TerrainRecords.default-records))

(fn empty-lights []
  {:ambient {:enabled? false
             :color [0.1 0.1 0.1]
             :intensity 1.0}
   :directional []
   :point []
   :spot []})

(fn default-sandbox-lights []
  {:ambient {:enabled? true
             :color [1.0 1.0 1.0]
             :intensity 1.0}
   :directional []
   :point []
   :spot []})

(fn empty-skybox []
  (local base (SkyboxState.default-state))
  {:enabled? false
   :name base.default.name
   :brightness base.default.brightness
   :tint-color (icollect [_ v (ipairs base.default.tint-color)] v)})

(fn default-sandbox-skybox []
  (local base (SkyboxState.default-state))
  {:enabled? true
   :name base.default.name
   :brightness base.default.brightness
   :tint-color (icollect [_ v (ipairs base.default.tint-color)] v)})

(fn empty-background []
  (BackgroundState.default-state))

(fn default-sandbox-background []
  (BackgroundState.default-state))

(fn empty-containment []
  (PhysicsContainment.serialize-config {:enabled? false}))

(fn default-sandbox-containment []
  (PhysicsContainment.serialize-config (PhysicsContainment.default-config)))

(fn empty-state []
  {:panels (empty-panels)
   :terrains (empty-terrains)
   :lights (empty-lights)
   :skybox (empty-skybox)
   :background (empty-background)
   :containment (empty-containment)})

(fn default-sandbox-state []
  {:panels (empty-panels)
   :terrains (default-sandbox-terrains)
   :lights (default-sandbox-lights)
   :skybox (default-sandbox-skybox)
   :background (default-sandbox-background)
   :containment (default-sandbox-containment)})

(fn assert-required-keys [state path]
  (local label (or path "ActivitySceneState"))
  (assert (= (type state) :table) (.. label " requires a table"))
  (assert (= (type state.panels) :table) (.. label " requires :panels table"))
  (assert (= (type state.terrains) :table) (.. label " requires :terrains table"))
  (assert (= (type state.lights) :table) (.. label " requires :lights table"))
  (assert (= (type state.skybox) :table) (.. label " requires :skybox table"))
  (assert (= (type state.background) :table) (.. label " requires :background table"))
  (assert (= (type state.containment) :table) (.. label " requires :containment table")))

(fn normalize-lights [lights path]
  (local label (.. (or path "ActivitySceneState") ".lights"))
  (assert (= (type lights) :table) (.. label " requires a table"))
  (assert (= (type lights.ambient) :table) (.. label " requires :ambient table"))
  (assert (= (type lights.ambient.enabled?) :boolean) (.. label " requires :ambient.enabled? boolean"))
  (assert (= (type lights.ambient.color) :table) (.. label " requires :ambient.color table"))
  (assert (= (length lights.ambient.color) 3) (.. label " requires :ambient.color [r g b]"))
  (each [idx v (ipairs lights.ambient.color)]
    (assert (= (type v) :number) (.. label " requires numeric :ambient.color[" (tostring idx) "]")))
  (local intensity (or lights.ambient.intensity 1.0))
  (assert (= (type intensity) :number) (.. label " requires numeric :ambient.intensity"))
  {:ambient {:enabled? lights.ambient.enabled?
             :color [(. lights.ambient.color 1) (. lights.ambient.color 2) (. lights.ambient.color 3)]
             :intensity intensity}
   :directional (clone-array (or lights.directional []))
   :point (clone-array (or lights.point []))
   :spot (clone-array (or lights.spot []))})

(fn normalize-skybox [skybox path]
  (SkyboxState.normalize-resolved-state skybox (.. (or path "ActivitySceneState") ".skybox")))

(fn normalize-background [background path]
  (BackgroundState.normalize-complete-state background (.. (or path "ActivitySceneState") ".background")))

(fn normalize-containment [containment path]
  (local label (.. (or path "ActivitySceneState") ".containment"))
  (assert (= (type containment) :table) (.. label " requires a table"))
  ;; Use the full serialization to normalize/preserve complete containment config
  (PhysicsContainment.serialize-config
    (PhysicsContainment.normalize-config containment)))

(fn normalize-state [state path]
  (local label (or path "ActivitySceneState"))
  (assert-required-keys state label)
  (local cloned
    {:panels (clone-array state.panels)
     :terrains (clone-array state.terrains)
     :lights (normalize-lights state.lights (.. label ".lights"))
     :skybox (normalize-skybox state.skybox (.. label ".skybox"))
     :background (normalize-background state.background (.. label ".background"))
     :containment (normalize-containment state.containment (.. label ".containment"))})
  cloned)

{:empty-state empty-state
 :default-sandbox-state default-sandbox-state
 :normalize-state normalize-state}
