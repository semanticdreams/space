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
  (SkyboxState.normalize-complete-state
    {:enabled? false
     :default {:name base.default.name
               :brightness base.default.brightness
               :tint-color (icollect [_ v (ipairs base.default.tint-color)] v)}
     :by-theme {}}
    "ActivitySceneState.empty-skybox"))

(fn default-sandbox-skybox []
  (local base (SkyboxState.default-state))
  (SkyboxState.normalize-complete-state
    {:enabled? true
     :default {:name base.default.name
               :brightness base.default.brightness
               :tint-color (icollect [_ v (ipairs base.default.tint-color)] v)}
     :by-theme {}}
    "ActivitySceneState.default-sandbox-skybox"))

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
  ;; R2-2: Preserve complete SkyboxState policy (:default, :by-theme) in
  ;; canonical state.  Resolve only when applying to the renderer/theme.
  (SkyboxState.normalize-complete-state skybox (.. (or path "ActivitySceneState") ".skybox")))

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

(fn ensure-session-scene! [activity-state id state-factory]
  "Ensure an activity session has a :scene entry. When one already exists, return
it unchanged. Otherwise, create it from state-factory (a function accepting the
activity-state and id, returning a canonical scene state table)."
  (assert (= (type activity-state) :table) "ActivitySceneState.ensure-session-scene! requires activity-state table")
  (assert (= (type id) :string) (.. "ActivitySceneState.ensure-session-scene! requires string id, got " (type id)))
  (assert (= (type state-factory) :function) "ActivitySceneState.ensure-session-scene! requires state-factory function")
  (when (not activity-state.sessions)
    (set activity-state.sessions {}))
  (when (not (. activity-state.sessions id))
    (set (. activity-state.sessions id) {}))
  (local session (. activity-state.sessions id))
  (when (not session.scene)
    (set session.scene (state-factory activity-state id)))
  session.scene)

(fn scene-state [activity-state id]
  "Return the canonical scene state for activity id, or nil."
  (when (and (= (type activity-state) :table)
             (= (type id) :string)
             (= (type activity-state.sessions) :table)
             (= (type (. activity-state.sessions id)) :table))
    (. activity-state.sessions id :scene)))

(fn remove-legacy-keys! [world-state]
  "Remove migrated legacy keys from top-level scene and physics. Returns true if
any keys were removed."
  (var changed? false)
  ;; Clear scene content keys
  (when (= (type world-state.scene) :table)
    (when (not (= world-state.scene.panels nil))
      (set world-state.scene.panels nil)
      (set changed? true))
    (when (not (= world-state.scene.terrains nil))
      (set world-state.scene.terrains nil)
      (set changed? true))
    (when (not (= world-state.scene.lights nil))
      (set world-state.scene.lights nil)
      (set changed? true))
    (when (not (= world-state.scene.skybox nil))
      (set world-state.scene.skybox nil)
      (set changed? true))
    (when (not (= world-state.scene.background nil))
      (set world-state.scene.background nil)
      (set changed? true)))
  ;; Clear physics containment
  (when (= (type world-state.physics) :table)
    (when (not (= world-state.physics.containment nil))
      (set world-state.physics.containment nil)
      (set changed? true)))
  changed?)

(fn migrate-legacy-world-state! [world-state]
  "Migrate legacy top-level scene and physics content into canonical activity
session slots. Idempotent: when canonical sandbox state already exists, it
is preserved and legacy keys are only cleaned up. Returns true if the world
state was changed and should be persisted."
  ;; 1. Ensure activity structure
  (when (not (= (type world-state.activity) :table))
    (set world-state.activity {}))
  (local activity-state world-state.activity)
  ;; default active_id to "sandbox" only when nil
  (when (= activity-state.active_id nil)
    (set activity-state.active_id "sandbox"))
  ;; 2. Migrate legacy scene/physics content into sandbox session
  (when (not (= (type activity-state.sessions) :table))
    (set activity-state.sessions {}))
  ;; Only create sandbox session scene from legacy if it doesn't already exist
  (when (not (. activity-state.sessions "sandbox"))
    (set (. activity-state.sessions "sandbox") {}))
  (local sandbox-session (. activity-state.sessions "sandbox"))
  (var changed? false)
  (when (not sandbox-session.scene)
    ;; Build sandbox scene from legacy values, falling back to defaults
    (local legacy-scene (or world-state.scene {}))
    (local legacy-physics (or world-state.physics {}))
    (local defaults (default-sandbox-state))
    (local panels (or legacy-scene.panels (clone-array defaults.panels)))
    (local terrains (or legacy-scene.terrains (clone-array defaults.terrains)))
    (local lights (if (= (type legacy-scene.lights) :table)
                      (normalize-lights legacy-scene.lights "ActivitySceneState.migrate")
                      defaults.lights))
    (local skybox (if (= (type legacy-scene.skybox) :table)
                      (normalize-skybox legacy-scene.skybox "ActivitySceneState.migrate")
                      defaults.skybox))
    (local background (if (= (type legacy-scene.background) :table)
                          (normalize-background legacy-scene.background "ActivitySceneState.migrate")
                          defaults.background))
    (local containment (if (= (type legacy-physics.containment) :table)
                            (normalize-containment legacy-physics.containment "ActivitySceneState.migrate")
                            defaults.containment))
    (set sandbox-session.scene
         {:panels (clone-array panels)
          :terrains (clone-array terrains)
          :lights lights
          :skybox skybox
          :background background
          :containment containment})
    (set changed? true))
  ;; Normalize existing sandbox scene state (flatten skybox.default etc.)
  (when sandbox-session.scene
    (set sandbox-session.scene
         (normalize-state sandbox-session.scene "ActivitySceneState.migrate")))
  ;; 3. Create empty scene states for Graph, Drawing, Board
  (local other-activity-ids [:graph :drawing :board])
  (each [_ activity-id (ipairs other-activity-ids)]
    (when (not (. activity-state.sessions activity-id))
      (set (. activity-state.sessions activity-id) {}))
    (local session (. activity-state.sessions activity-id))
    (when (not session.scene)
      (set session.scene (empty-state))
      (set changed? true)))
  ;; 4. Remove migrated fields from top-level
  (local removed-legacy? (remove-legacy-keys! world-state))
  (when removed-legacy?
    (set changed? true))
  changed?)

{:empty-state empty-state
 :default-sandbox-state default-sandbox-state
 :normalize-state normalize-state
 :ensure-session-scene! ensure-session-scene!
 :scene-state scene-state
 :migrate-legacy-world-state! migrate-legacy-world-state!}
