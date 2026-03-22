(local TerrainRecords (require :scene-terrain-records))

(local M {})

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

(fn resolve-hud [world-id]
  (when (and app
             app.active-world-entry
             (= app.active-world-entry.id world-id)
             app.hud)
    app.hud))

(fn world-name [world-manager world-id]
  (local entry (resolve-world-entry world-manager world-id))
  (or (and entry entry.name) world-id))

(fn scene-state-panels [world-manager world-id]
  (local world (resolve-world world-manager world-id))
  (or (and world world.state world.state.scene world.state.scene.panels) []))

(fn hud-state-panels [world-manager world-id]
  (local world (resolve-world world-manager world-id))
  (or (and world world.state world.state.hud world.state.hud.panels) []))

(fn terrain-state-records [world-manager world-id]
  (local world (resolve-world world-manager world-id))
  (or (and world world.state world.state.scene world.state.scene.terrains) []))

(fn ensure-scene-state [world]
  (when (not world.state)
    (set world.state {}))
  (when (not world.state.scene)
    (set world.state.scene {}))
  (when (not world.state.scene.panels)
    (set world.state.scene.panels []))
  (when (not world.state.scene.terrains)
    (set world.state.scene.terrains []))
  world.state.scene)

(fn emit-world-change [world-manager world-id reason]
  (when (and world-manager world-manager.changed world-manager.changed.emit)
    (world-manager.changed:emit {:world-id world-id
                                 :reason reason})))

(fn persist-world [world-manager world-id]
  (local world (resolve-world world-manager world-id))
  (when (and world world.save-state)
    (world:save-state))
  world)

(fn require-active-scene-method [scene terrain-id method-name]
  (assert (. scene method-name)
          (.. "Active scene is missing " method-name " for terrain " terrain-id)))

(fn sync-active-terrain-record [world-manager world-id terrain-id record]
  (local scene (resolve-scene world-manager world-id))
  (when scene
    (require-active-scene-method scene terrain-id :replace-terrain-record)
    (assert (scene:replace-terrain-record terrain-id record)
            (.. "Active scene failed to replace terrain " terrain-id))))

(fn sync-active-terrain-removal [world-manager world-id terrain-id]
  (local scene (resolve-scene world-manager world-id))
  (when scene
    (require-active-scene-method scene terrain-id :remove-terrain)
    (assert (scene:remove-terrain terrain-id)
            (.. "Active scene failed to remove terrain " terrain-id))))

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
  (if (and scene scene.scene-children)
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
  (if (and scene scene.scene-terrains)
      (each [_ entry (ipairs (or scene.scene-terrains []))]
        (local record (and entry entry.record))
        (local terrain-id (or (and record record.id) "unknown"))
        (local kind (or (and record record.kind) "unknown"))
        (local label (.. kind " [" terrain-id "]"))
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
        (local label (.. kind " [" terrain-id "]"))
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

(fn remove-scene-panel [world-manager world-id panel-index]
  (local scene (resolve-scene world-manager world-id))
  (if (and scene scene.scene-children scene.remove-panel-child)
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
    (local scene-state (ensure-scene-state world))
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

(fn remove-terrain [world-manager world-id terrain-id]
  (local world (resolve-world world-manager world-id))
  (when world
    (local scene-state (ensure-scene-state world))
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
 :resolve-hud resolve-hud
 :world-name world-name
 :list-scene-panels list-scene-panels
 :list-hud-panels list-hud-panels
 :list-terrains list-terrains
 :find-scene-panel find-scene-panel
 :find-hud-panel find-hud-panel
 :find-terrain find-terrain
 :update-terrain-record update-terrain-record
 :remove-terrain remove-terrain
 :remove-scene-panel remove-scene-panel
 :remove-hud-panel remove-hud-panel}
