(local TerrainRecords (require :scene-terrain-records))
(local LightSystemModule (require :light-system))
(local SkyboxState (require :skybox-state))
(local BackgroundState (require :background-state))
(local ActivitySceneState (require :activity-scene-state))

(local M {})

;; ── Canonical sandbox session helpers ──────────────────────────────

(fn resolve-sandbox-scene-state [world context]
  "Return the canonical sandbox session scene state for a HomeWorld.
  Fails loudly when world.state exists but the sandbox session scene
  is missing (corrupt or uninitialized state).
  Returns nil only when world itself is nil (truly missing entry)."
  (when world
    (assert world.state (.. (or context "WorldData") " requires world.state"))
    (assert (= (type world.state.activity) :table)
            (.. (or context "WorldData") " requires world.state.activity"))
    (local scene (ActivitySceneState.scene-state world.state.activity "sandbox"))
    (assert scene
            (.. (or context "WorldData")
                " requires activity.sessions.sandbox.scene"))
    scene))

(fn ensure-sandbox-scene-state [world]
  "Ensure the sandbox session scene state exists and return it."
  (assert world "WorldData requires world")
  (assert world.state "WorldData requires world.state")
  (when (not (= (type world.state.activity) :table))
    (set world.state.activity {}))
  (ActivitySceneState.ensure-session-scene!
    world.state.activity
    "sandbox"
    ActivitySceneState.default-sandbox-state))

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn find-tab [world-manager world-id]
  (var resolved nil)
  (when (and world-manager world-manager.list-tabs world-id)
    (each [_ tab (ipairs (world-manager:list-tabs))]
      (when (and (not resolved) (= tab.id world-id))
        (set resolved tab))))
  resolved)

(fn resolve-world-entry [world-manager world-id]
  (if (and world-manager world-manager.get-world-entry)
      (world-manager:get-world-entry world-id)
      (find-tab world-manager world-id)))

(fn resolve-world [world-manager world-id]
  (local entry (resolve-world-entry world-manager world-id))
  (and entry entry.world))

(fn resolve-runtime [world-manager world-id]
  (local world (resolve-world world-manager world-id))
  (if (and world world.get-runtime)
      (world:get-runtime)
      nil))

(fn resolve-scene [world-manager world-id]
  (local runtime (resolve-runtime world-manager world-id))
  (and runtime runtime.scene))

(fn resolve-active-scene [world-manager world-id]
  (local active-id
    (or (and world-manager world-manager.active-world-id
             (world-manager:active-world-id))
        (and world-manager world-manager.active-world
             (let [entry (world-manager:active-world)]
               (and entry entry.id)))
        (and app app.active-world-entry app.active-world-entry.id)))
  (if (= active-id world-id)
      (resolve-scene world-manager world-id)
      (let [entry (resolve-world-entry world-manager world-id)]
        (if (and entry entry.active?)
            (resolve-scene world-manager world-id)
            nil))))

(fn resolve-hud [world-id]
  (when (and app
             app.active-world-entry
             (= app.active-world-entry.id world-id)
             app.hud)
    app.hud))

(fn active-theme-key []
  (if (and app app.themes app.themes.get-active-theme-name)
      (SkyboxState.normalize-theme-key
        (app.themes.get-active-theme-name)
        "WorldData active theme")
      nil))

(fn world-name [world-manager world-id]
  (local entry (resolve-world-entry world-manager world-id))
  (or (and entry entry.name) world-id))

(fn scene-state-panels [world-manager world-id]
  (local world (resolve-world world-manager world-id))
  (local sandbox-scene (resolve-sandbox-scene-state world))
  (or (and sandbox-scene sandbox-scene.panels) []))

(fn hud-state-panels [world-manager world-id]
  (local world (resolve-world world-manager world-id))
  (or (and world world.state world.state.hud world.state.hud.panels) []))

(fn terrain-state-records [world-manager world-id]
  (local world (resolve-world world-manager world-id))
  (local sandbox-scene (resolve-sandbox-scene-state world))
  (or (and sandbox-scene sandbox-scene.terrains) []))

(fn scene-state-skybox [world-manager world-id]
  (local world (resolve-world world-manager world-id))
  (if (not world)
      nil
      (do
        (local sandbox-scene (resolve-sandbox-scene-state world (.. "WorldData[" world-id "]")))
        (assert sandbox-scene (.. "WorldData[" world-id "] requires sandbox scene state"))
        (SkyboxState.normalize-complete-state
          (assert sandbox-scene.skybox
                  (.. "WorldData[" world-id "] requires sandbox scene.skybox"))
          (.. "WorldData[" world-id "] sandbox scene.skybox")))))

(fn scene-state-background [world-manager world-id]
  (local world (resolve-world world-manager world-id))
  (if (not world)
      nil
      (do
        (local sandbox-scene (resolve-sandbox-scene-state world (.. "WorldData[" world-id "]")))
        (assert sandbox-scene (.. "WorldData[" world-id "] requires sandbox scene state"))
        (BackgroundState.normalize-complete-state
          (assert sandbox-scene.background
                  (.. "WorldData[" world-id "] requires sandbox scene.background"))
          (.. "WorldData[" world-id "] sandbox scene.background")))))

(fn resolve-default-light-state []
  (LightSystemModule.default-state))

(fn ensure-scene-state [world]
  "Ensure sandbox session scene state exists and return it."
  (ensure-sandbox-scene-state world))

(fn require-scene-state [world context]
  "Assert that sandbox session scene state exists and return it."
  (local label (.. (or context "WorldData")))
  (assert world (.. label " requires world"))
  (local sandbox-scene (resolve-sandbox-scene-state world label))
  (assert sandbox-scene (.. label " requires sandbox scene state"))
  sandbox-scene)

(fn emit-world-change [world-manager world-id reason]
  (when (and world-manager world-manager.changed world-manager.changed.emit)
    (world-manager.changed:emit {:world-id world-id
                                 :reason reason})))

(fn persist-world [world-manager world-id]
  (local world (resolve-world world-manager world-id))
  (when (and world world.save-state)
    (world:save-state))
  world)

(fn refresh-sandbox-slot-if-inactive [scene world-manager world-id]
  "When the active Scene slot is NOT sandbox, refresh the retained sandbox
  slot's scene-state from canonical session state so mutations survive until
  the next sandbox activation.  Also update runtime.activity-session-state
  so that Activities.snapshot-activity-sessions cannot overwrite the
  mutation with stale pending data.  Does nothing when sandbox is already
  active (the direct runtime sync handles that case)."
  (when (and scene (not (= scene.active-activity-slot-id "sandbox")))
    (local world (resolve-world world-manager world-id))
    (local canonical (resolve-sandbox-scene-state world))
    (when canonical
      ;; Ensure the retained slot exists and has scene-state so mutations
      ;; survive until the next sandbox activation.
      (local sandbox-slot (and scene.activity-slot
                               (scene:activity-slot "sandbox")))
      (when (and sandbox-slot sandbox-slot.scene-state)
        ;; Refresh retained slot state in place from canonical.
        (each [k v (pairs canonical)]
          (tset sandbox-slot.scene-state k v)))
      ;; R5-1: Also update runtime.activity-session-state.sandbox.scene
      ;; so Activities.snapshot-activity-sessions cannot save stale
      ;; pending data over the mutation.
      (local runtime (resolve-runtime world-manager world-id))
      (when (and runtime runtime.activity-session-state)
        (when (not (= (type runtime.activity-session-state.sandbox) :table))
          (tset runtime.activity-session-state :sandbox {}))
        ;; Replace sandbox.scene with the canonical scene so stale
        ;; pending data cannot overwrite the mutation during snapshot.
        (tset runtime.activity-session-state.sandbox :scene canonical)))))

(fn require-active-scene-light-method [scene method-name]
  (assert (. scene method-name)
          (.. "Active scene is missing " method-name " for world light sync")))

(fn require-active-scene-method [scene terrain-id method-name]
  (assert (. scene method-name)
          (.. "Active scene is missing " method-name " for terrain " terrain-id)))

(fn sync-active-terrain-record [world-manager world-id terrain-id record]
  (local scene (resolve-scene world-manager world-id))
  (when scene
    (if (= scene.active-activity-slot-id "sandbox")
        (do
          (require-active-scene-method scene terrain-id :replace-terrain-record)
          (assert (scene:replace-terrain-record terrain-id record)
                  (.. "Active scene failed to replace terrain " terrain-id)))
        (refresh-sandbox-slot-if-inactive scene world-manager world-id))))

(fn sync-active-terrain-removal [world-manager world-id terrain-id]
  (local scene (resolve-scene world-manager world-id))
  (when scene
    (if (= scene.active-activity-slot-id "sandbox")
        (do
          (require-active-scene-method scene terrain-id :remove-terrain)
          (assert (scene:remove-terrain terrain-id)
                  (.. "Active scene failed to remove terrain " terrain-id)))
        (refresh-sandbox-slot-if-inactive scene world-manager world-id))))

(fn sync-active-terrain-addition [world-manager world-id record]
  (local scene (resolve-scene world-manager world-id))
  (when scene
    (if (= scene.active-activity-slot-id "sandbox")
        (do
          (require-active-scene-method scene record.id :add-terrain-record)
          (assert (scene:add-terrain-record record)
                  (.. "Active scene failed to add terrain " record.id)))
        (refresh-sandbox-slot-if-inactive scene world-manager world-id))))

(fn scene-state-lights [world-manager world-id]
  (local world (resolve-world world-manager world-id))
  (if (not world)
      nil
      (do
        (local sandbox-scene (require-scene-state world (.. "WorldData[" world-id "]")))
        (LightSystemModule.normalize-complete-state
          (assert sandbox-scene.lights
                  (.. "WorldData[" world-id "] requires sandbox scene.lights"))
          (.. "WorldData[" world-id "] sandbox scene.lights")))))

(fn normalize-light-state [lights context]
  (LightSystemModule.normalize-complete-state lights context))

(fn persist-light-state! [scene-state lights context]
  "Normalize lights and store into scene-state.lights. Updates in place
  to maintain canonical session references when the same table is shared."
  (local normalized (normalize-light-state lights (or context "WorldData.persist-light-state!")))
  ;; Update in place: keep the same table identity for shared references.
  (each [k v (pairs normalized)]
    (tset scene-state.lights k v))
  ;; Remove keys that are no longer present.
  (each [k _ (pairs scene-state.lights)]
    (when (= (. normalized k) nil)
      (tset scene-state.lights k nil)))
  scene-state.lights)

(fn sync-active-light-state [world-manager world-id lights]
  (local scene (resolve-scene world-manager world-id))
  (when scene
    (if (= scene.active-activity-slot-id "sandbox")
        (do
          (require-active-scene-light-method scene :set-light-state)
          (scene:set-light-state lights))
        (refresh-sandbox-slot-if-inactive scene world-manager world-id))))

(fn sync-active-skybox-state [world-manager world-id skybox]
  (local scene (resolve-scene world-manager world-id))
  (when scene
    (if (= scene.active-activity-slot-id "sandbox")
        (do
          ;; R5-2: Update the active sandbox slot's scene-state.skybox with the
          ;; complete policy skybox BEFORE applying the resolved renderer state.
          ;; This ensures capture-activity-slot-state reads the complete policy,
          ;; not a stale or resolved-only skybox.
          (local sandbox-slot (and scene.activity-slot
                                   (scene:activity-slot "sandbox")))
          (when sandbox-slot
            (when (not (= (type sandbox-slot.scene-state) :table))
              (set sandbox-slot.scene-state {}))
            (tset sandbox-slot.scene-state :skybox skybox))
          (assert scene.set-skybox-state
                  "Active scene is missing set-skybox-state for world skybox sync")
          (scene:set-skybox-state
            (SkyboxState.resolve-for-theme skybox (active-theme-key))))
        (refresh-sandbox-slot-if-inactive scene world-manager world-id))))

(fn sync-active-background-state [world-manager world-id background]
  (local scene (resolve-scene world-manager world-id))
  (when scene
    (if (= scene.active-activity-slot-id "sandbox")
        (do
          (assert scene.set-background-state
                  "Active scene is missing set-background-state for world background sync")
          (scene:set-background-state background))
        (refresh-sandbox-slot-if-inactive scene world-manager world-id))))

(fn list-light-types [world-manager world-id]
  (local lights (scene-state-lights world-manager world-id))
  (icollect [_ spec (ipairs (LightSystemModule.list-type-specs))]
    (do
      (local type-key spec.key)
      (local count (LightSystemModule.state-count lights type-key))
      [{:type-key type-key
        :label spec.label
        :plural-label (. spec :plural-label)
        :max-count (. spec :max-count)
        :count count}
       (.. spec.label " (" (tostring count) "/" (tostring (. spec :max-count)) ")")])))

(fn list-lights [world-manager world-id type-key]
  (local lights (scene-state-lights world-manager world-id))
  (local produced [])
  (if (not lights)
      produced
      (if (= type-key "ambient")
          (when lights.ambient
            (local record lights.ambient)
            (local light-id (or record.id "ambient"))
            (table.insert produced [{:light-id light-id
                                     :type-key type-key
                                     :record record
                                     :label "ambient"
                                     :source "state"}
                                    "ambient"]))
          (each [_ record (ipairs (or (. lights type-key) []))]
            (local light-id (or record.id "unknown"))
            (local label (.. type-key " [" light-id "]"))
            (table.insert produced [{:light-id light-id
                                     :type-key type-key
                                     :record record
                                     :label label
                                     :source "state"}
                                    label]))))
  produced)

(fn find-light [world-manager world-id type-key light-id]
  (var resolved nil)
  (each [_ item (ipairs (list-lights world-manager world-id type-key))]
    (local entry (. item 1))
    (when (and (not resolved) (= (and entry entry.light-id) light-id))
      (set resolved entry)))
  resolved)

(fn next-light-id [world-manager world-id type-key]
  (local used {})
  (each [_ item (ipairs (list-lights world-manager world-id type-key))]
    (local entry (. item 1))
    (when (and entry entry.light-id)
      (set (. used entry.light-id) true)))
  (if (= type-key "ambient")
      "ambient"
      (do
        (var idx 1)
        (var candidate (.. type-key "-" (tostring idx)))
        (while (. used candidate)
          (set idx (+ idx 1))
          (set candidate (.. type-key "-" (tostring idx))))
        candidate)))

(fn find-terrain-state-index [world-manager world-id terrain-id]
  (local terrains (terrain-state-records world-manager world-id))
  (var resolved nil)
  (each [idx record (ipairs terrains)]
    (when (and (not resolved) (= (and record record.id) terrain-id))
      (set resolved idx)))
  resolved)

(fn list-scene-panels [world-manager world-id]
  (local scene (resolve-scene world-manager world-id))
  (local produced [])
  (if (and scene scene.scene-children (= scene.active-activity-slot-id "sandbox"))
      (each [idx metadata (ipairs (or scene.scene-children []))]
        (local persistence (and metadata metadata.persistence))
        (local kind (or (and persistence persistence.kind) "unknown"))
        (local label (.. kind " [" idx "]"))
        (table.insert produced [{:index idx
                                 :kind kind
                                 :metadata metadata
                                 :label label
                                 :source "runtime"}
                                label]))
      (each [idx panel (ipairs (scene-state-panels world-manager world-id))]
        (local kind (or (and panel panel.kind) "unknown"))
        (local label (.. kind " [" idx "]"))
        (table.insert produced [{:index idx
                                 :kind kind
                                 :panel panel
                                 :label label
                                 :source "state"}
                                label])))
  produced)

(fn list-hud-panels [world-manager world-id]
  (local hud (resolve-hud world-id))
  (local produced [])
  (if hud
      (do
        (local tiles (and hud hud.tiles hud.tiles.children))
        (each [idx metadata (ipairs (or tiles []))]
          (local persistence (and metadata metadata.persistence))
          (local kind (or (and persistence persistence.kind) "unknown"))
          (local label (.. kind " [tiles:" idx "]"))
          (table.insert produced [{:index idx
                                   :layer "tiles"
                                   :kind kind
                                   :metadata metadata
                                   :label label
                                   :source "runtime"}
                                  label]))
        (local float (and hud hud.float hud.float.children))
        (each [idx metadata (ipairs (or float []))]
          (local persistence (and metadata metadata.persistence))
          (local kind (or (and persistence persistence.kind) "unknown"))
          (local label (.. kind " [float:" idx "]"))
          (table.insert produced [{:index idx
                                   :layer "float"
                                   :kind kind
                                   :metadata metadata
                                   :label label
                                   :source "runtime"}
                                  label])))
      (do
        (var tiles-index 0)
        (var float-index 0)
        (each [_ panel (ipairs (hud-state-panels world-manager world-id))]
          (local layer (or panel.layer "tiles"))
          (local kind (or panel.kind "unknown"))
          (local index (if (= layer "float")
                           (do
                             (set float-index (+ float-index 1))
                             float-index)
                           (do
                             (set tiles-index (+ tiles-index 1))
                             tiles-index)))
          (local label (.. kind " [" layer ":" index "]"))
          (table.insert produced [{:index index
                                   :layer layer
                                   :kind kind
                                   :panel panel
                                   :label label
                                   :source "state"}
                                  label]))))
  produced)

(fn list-terrains [world-manager world-id]
  (local scene (resolve-scene world-manager world-id))
  (local produced [])
  (if (and scene scene.scene-terrains (= scene.active-activity-slot-id "sandbox"))
      (each [_ entry (ipairs (or scene.scene-terrains []))]
        (local record (and entry entry.record))
        (local terrain-id (or (and record record.id) "unknown"))
        (local kind (or (and record record.kind) "unknown"))
        (local name (and record record.name))
        (local label (or name (.. "terrain [" terrain-id "]")))
        (table.insert produced [{:terrain-id terrain-id
                                 :kind kind
                                 :record record
                                 :entry entry
                                 :label label
                                 :source "runtime"}
                                label]))
      (each [_ record (ipairs (terrain-state-records world-manager world-id))]
        (local terrain-id (or record.id "unknown"))
        (local kind (or record.kind "unknown"))
        (local name (and record record.name))
        (local label (or name (.. "terrain [" terrain-id "]")))
        (table.insert produced [{:terrain-id terrain-id
                                 :kind kind
                                 :record record
                                 :label label
                                 :source "state"}
                                label])))
  produced)

(fn find-scene-panel [world-manager world-id panel-index]
  (var resolved nil)
  (each [_ item (ipairs (list-scene-panels world-manager world-id))]
    (local entry (. item 1))
    (when (and (not resolved) (= (and entry entry.index) panel-index))
      (set resolved entry)))
  resolved)

(fn find-hud-panel [world-manager world-id layer panel-index]
  (var resolved nil)
  (each [_ item (ipairs (list-hud-panels world-manager world-id))]
    (local entry (. item 1))
    (when (and (not resolved)
               (= (and entry entry.layer) layer)
               (= (and entry entry.index) panel-index))
      (set resolved entry)))
  resolved)

(fn find-terrain [world-manager world-id terrain-id]
  (var resolved nil)
  (each [_ item (ipairs (list-terrains world-manager world-id))]
    (local entry (. item 1))
    (when (and (not resolved) (= (and entry entry.terrain-id) terrain-id))
      (set resolved entry)))
  resolved)

(fn update-light-record [world-manager world-id type-key light-id updater]
  (local world (resolve-world world-manager world-id))
  (assert world (.. "Cannot update light in missing world " world-id))
  (local scene-state (require-scene-state world (.. "WorldData.update-light-record[" world-id "]")))
  (local lights (persist-light-state! scene-state
                                      scene-state.lights
                                      (.. "WorldData.update-light-record[" world-id "]")))
  (if (= type-key "ambient")
      (do
        (local current lights.ambient)
        (assert current (.. "Missing ambient light in world " world-id))
        (local next-record (clone-table current))
        (updater next-record)
        (set next-record.id "ambient")
        (set lights.ambient next-record)
        (local normalized (persist-light-state! scene-state
                                                lights
                                                (.. "WorldData.update-light-record[" world-id "]")))
        (sync-active-light-state world-manager world-id normalized)
        (persist-world world-manager world-id)
        (emit-world-change world-manager world-id "light-updated")
        (. normalized :ambient))
      (do
        (local items (or (. lights type-key) []))
        (set (. lights type-key) items)
        (var found-index nil)
        (each [idx record (ipairs items)]
          (when (and (not found-index) (= (and record record.id) light-id))
            (set found-index idx)))
        (local current (and found-index (. items found-index)))
        (assert current
                (.. "Cannot update missing " type-key " light " light-id
                    " in world " world-id))
        (local next-record (clone-table current))
        (updater next-record)
        (set next-record.id light-id)
        (set (. items found-index) next-record)
        (local normalized (persist-light-state! scene-state
                                                lights
                                                (.. "WorldData.update-light-record[" world-id "]")))
        (sync-active-light-state world-manager world-id normalized)
        (persist-world world-manager world-id)
        (emit-world-change world-manager world-id "light-updated")
        (. (. normalized type-key) found-index))))

(fn add-light [world-manager world-id type-key]
  (local world (resolve-world world-manager world-id))
  (assert world (.. "Cannot add light to missing world " world-id))
  (local scene-state (require-scene-state world (.. "WorldData.add-light[" world-id "]")))
  (local lights (persist-light-state! scene-state
                                      scene-state.lights
                                      (.. "WorldData.add-light[" world-id "]")))
  (local spec (LightSystemModule.type-spec type-key))
  (assert spec (.. "Unsupported light type " (tostring type-key)))
  (assert (not (= type-key "ambient"))
          "Ambient light is a required singleton and cannot be added")
  (local count (LightSystemModule.state-count lights type-key))
  (assert (< count (. spec :max-count))
          (.. "Cannot add more than " (tostring (. spec :max-count))
              " " type-key " lights"))
  (local light-id (next-light-id world-manager world-id type-key))
  (local record (LightSystemModule.default-record-for-type type-key
                                                           {:id light-id
                                                            :index (+ count 1)
                                                            :defaults (resolve-default-light-state)}))
  (when (not (. lights type-key))
    (set (. lights type-key) []))
  (table.insert (. lights type-key) record)
  (local normalized (persist-light-state! scene-state
                                          lights
                                          (.. "WorldData.add-light[" world-id "]")))
  (sync-active-light-state world-manager world-id normalized)
  (persist-world world-manager world-id)
  (emit-world-change world-manager world-id "light-added")
  (. (. normalized type-key) (+ count 1)))

(fn remove-light [world-manager world-id type-key light-id]
  (local world (resolve-world world-manager world-id))
  (assert world (.. "Cannot remove light from missing world " world-id))
  (local scene-state (require-scene-state world (.. "WorldData.remove-light[" world-id "]")))
  (local lights (persist-light-state! scene-state
                                      scene-state.lights
                                      (.. "WorldData.remove-light[" world-id "]")))
  (if (= type-key "ambient")
      (error "Ambient light is required and cannot be removed")
      (do
        (local items (or (. lights type-key) []))
        (var found-index nil)
        (each [idx record (ipairs items)]
          (when (and (not found-index) (= (and record record.id) light-id))
            (set found-index idx)))
        (assert found-index
                (.. "Cannot remove missing " type-key " light " light-id
                    " from world " world-id))
        (table.remove items found-index)
        (local normalized (persist-light-state! scene-state
                                                lights
                                                (.. "WorldData.remove-light[" world-id "]")))
        (sync-active-light-state world-manager world-id normalized)
        (persist-world world-manager world-id)
        (emit-world-change world-manager world-id "light-removed")
        true)))

(fn get-skybox [world-manager world-id]
  (scene-state-skybox world-manager world-id))

(fn get-background [world-manager world-id]
  (scene-state-background world-manager world-id))

(fn update-skybox [world-manager world-id skybox]
  (local world (resolve-world world-manager world-id))
  (assert world (.. "Cannot update skybox in missing world " world-id))
  (local scene-state (require-scene-state world (.. "WorldData.update-skybox[" world-id "]")))
  (local normalized
    (SkyboxState.normalize-complete-state skybox
                                          (.. "WorldData.update-skybox[" world-id "]")))
  (set scene-state.skybox normalized)
  (sync-active-skybox-state world-manager world-id normalized)
  (persist-world world-manager world-id)
  (emit-world-change world-manager world-id "skybox-updated")
  normalized)

(fn update-background [world-manager world-id background]
  (local world (resolve-world world-manager world-id))
  (assert world (.. "Cannot update background in missing world " world-id))
  (local scene-state (require-scene-state world (.. "WorldData.update-background[" world-id "]")))
  (local normalized
    (BackgroundState.normalize-complete-state background
                                              (.. "WorldData.update-background[" world-id "]")))
  (set scene-state.background normalized)
  (sync-active-background-state world-manager world-id normalized)
  (persist-world world-manager world-id)
  (emit-world-change world-manager world-id "background-updated")
  normalized)

(fn remove-scene-panel [world-manager world-id panel-index]
  (local scene (resolve-scene world-manager world-id))
  ;; Only use runtime scene when sandbox is the active slot.
  (if (and scene scene.scene-children scene.remove-panel-child
           (= scene.active-activity-slot-id "sandbox"))
      (do
        (local metadata (. scene.scene-children panel-index))
        (local element (and metadata metadata.element))
        (if element
            (do
              (scene:remove-panel-child element)
              (when (and world-manager world-manager.changed world-manager.changed.emit)
                (world-manager.changed:emit {:world-id world-id
                                             :reason "scene-panel-removed"}))
              true)
            false))
      (do
        (local panels (scene-state-panels world-manager world-id))
        (if (and (>= panel-index 1) (<= panel-index (length panels)))
            (do
              (table.remove panels panel-index)
              (local world (resolve-world world-manager world-id))
              (when (and world world.save-state)
                (world:save-state))
              (when (and world-manager world-manager.changed world-manager.changed.emit)
                (world-manager.changed:emit {:world-id world-id
                                             :reason "scene-panel-removed"}))
              ;; R5-1: Refresh sandbox slot state and invalidate any stale
              ;; pending activity-session-state so Activities.snapshot-activity-sessions
              ;; cannot overwrite the panel removal on save.
              (refresh-sandbox-slot-if-inactive scene world-manager world-id)
              true)
            false))))

(fn remove-hud-panel [world-manager world-id layer panel-index]
  (local hud (resolve-hud world-id))
  (if (and hud hud.remove-panel-child)
      (do
        (local children (if (= layer "float")
                            (and hud hud.float hud.float.children)
                            (and hud hud.tiles hud.tiles.children)))
        (local metadata (and children (. children panel-index)))
        (local element (and metadata metadata.element))
        (if element
            (do
              (hud:remove-panel-child element)
              true)
            false))
      (do
        (local panels (hud-state-panels world-manager world-id))
        (var matched-array-index nil)
        (var layer-index 0)
        (each [idx panel (ipairs panels)]
          (when (= (or (and panel panel.layer) "tiles") layer)
            (set layer-index (+ layer-index 1))
            (when (and (not matched-array-index) (= layer-index panel-index))
              (set matched-array-index idx))))
        (if matched-array-index
            (do
              (table.remove panels matched-array-index)
              (local world (resolve-world world-manager world-id))
              (when (and world world.save-state)
                (world:save-state))
              (when (and world-manager world-manager.changed world-manager.changed.emit)
                (world-manager.changed:emit {:world-id world-id
                                             :reason "hud-panel-removed"}))
              true)
            false))))

(fn update-terrain-record [world-manager world-id terrain-id updater]
  (local world (resolve-world world-manager world-id))
  (when world
    (local scene-state (require-scene-state world (.. "WorldData.update-terrain-record[" world-id "]")))
    (local terrains scene-state.terrains)
    (local idx (find-terrain-state-index world-manager world-id terrain-id))
    (local resolved (find-terrain world-manager world-id terrain-id))
    (local current (or (and idx (. terrains idx))
                       (and resolved resolved.record)))
    (when current
      (local next-record (clone-table current))
      (updater next-record)
      (local normalized (TerrainRecords.normalize-record next-record))
      (set normalized.id terrain-id)
      (if idx
          (set (. terrains idx) normalized)
          (table.insert terrains normalized))
      (sync-active-terrain-record world-manager world-id terrain-id normalized)
      (persist-world world-manager world-id)
      (emit-world-change world-manager world-id "terrain-updated")
      normalized)))

(fn set-terrain-selection-target [world-manager world-id terrain-id target]
  (local scene (resolve-scene world-manager world-id))
  (when (and scene scene.set-terrain-selection-target)
    (scene:set-terrain-selection-target terrain-id target)))

(fn clear-terrain-selection-target [world-manager world-id terrain-id]
  (local scene (resolve-scene world-manager world-id))
  (when (and scene scene.clear-terrain-selection-target)
    (scene:clear-terrain-selection-target terrain-id)))

(fn get-terrain-selection-target [world-manager world-id terrain-id]
  (local scene (resolve-scene world-manager world-id))
  (if (and scene scene.get-terrain-selection-target)
      (scene:get-terrain-selection-target terrain-id)
      nil))

(fn add-terrain [world-manager world-id terrain-kind]
  (local world (resolve-world world-manager world-id))
  (when world
    (local scene-state (require-scene-state world (.. "WorldData.add-terrain[" world-id "]")))
    (local terrains scene-state.terrains)
    (local record (TerrainRecords.default-record-for-kind terrain-kind))
    (table.insert terrains record)
    (sync-active-terrain-addition world-manager world-id record)
    (persist-world world-manager world-id)
    (emit-world-change world-manager world-id "terrain-added")
    record))

(fn remove-terrain [world-manager world-id terrain-id]
  (local world (resolve-world world-manager world-id))
  (when world
    (local scene-state (require-scene-state world (.. "WorldData.remove-terrain[" world-id "]")))
    (local terrains scene-state.terrains)
    (local idx (find-terrain-state-index world-manager world-id terrain-id))
    (when idx
      (table.remove terrains idx)
      (sync-active-terrain-removal world-manager world-id terrain-id)
      (persist-world world-manager world-id)
      (emit-world-change world-manager world-id "terrain-removed")
      true)))

{:find-tab find-tab
 :resolve-world-entry resolve-world-entry
 :resolve-world resolve-world
 :resolve-runtime resolve-runtime
 :resolve-scene resolve-scene
 :resolve-active-scene resolve-active-scene
 :resolve-hud resolve-hud
 :world-name world-name
 :list-scene-panels list-scene-panels
 :list-hud-panels list-hud-panels
 :list-terrains list-terrains
 :get-skybox get-skybox
 :get-background get-background
 :list-light-types list-light-types
 :list-lights list-lights
 :find-scene-panel find-scene-panel
 :find-hud-panel find-hud-panel
 :find-terrain find-terrain
 :find-light find-light
 :add-terrain add-terrain
 :add-light add-light
 :update-skybox update-skybox
 :update-background update-background
 :update-terrain-record update-terrain-record
 :update-light-record update-light-record
 :set-terrain-selection-target set-terrain-selection-target
 :clear-terrain-selection-target clear-terrain-selection-target
 :get-terrain-selection-target get-terrain-selection-target
 :remove-terrain remove-terrain
 :remove-light remove-light
 :remove-scene-panel remove-scene-panel
 :remove-hud-panel remove-hud-panel}
