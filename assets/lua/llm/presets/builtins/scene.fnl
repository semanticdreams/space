(local glm (require :glm))
(local WorldData (require :graph/world-data))

(fn active-world-id [app]
  (assert app.world-manager "scene preset tool requires app.world-manager")
  (local world-id (app.world-manager:active-world-id))
  (assert world-id "scene preset tool requires an active world")
  world-id)

(fn rgb-from-hex [value]
  (assert (= (type value) "string") "scene color must be a string")
  (local trimmed (string.gsub value "^#" ""))
  (assert (= (# trimmed) 6) "scene color must be #RRGGBB")
  [(/ (tonumber (string.sub trimmed 1 2) 16) 255.0)
   (/ (tonumber (string.sub trimmed 3 4) 16) 255.0)
   (/ (tonumber (string.sub trimmed 5 6) 16) 255.0)])

(fn find-selectable [selector id]
  (var found nil)
  (each [_ selectable (ipairs (or selector.selectables []))]
    (when (and (not found)
               (or (= selectable.id id)
                   (= selectable.key id)
                   (= (and selectable.owner selectable.owner.id) id)
                   (= (and selectable.owner selectable.owner.key) id)))
      (set found selectable)))
  found)

(fn register-scene-presets [mgr]
  (mgr:register
    {:name "scene-object-tools"
     :group "scene"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :scene}]
     :tool-ids ["scene.add-cuboid" "scene.add-physics-body" "scene.select-object"]
     :system-prompt "Use scene object tools to add and manipulate 3D objects in the scene."})

  (mgr:register
    {:name "scene-terrain-tools"
     :group "scene"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :scene}]
     :tool-ids ["scene.add-terrain" "scene.raycast-terrain"]})

  (mgr:register
    {:name "scene-terrain-destructive-tools"
     :group "scene"
     :default-state :auto
     :risk :destructive
     :contexts [{:surface :scene}]
     :tool-ids ["scene.remove-terrain"]})

  (mgr:register
    {:name "scene-lighting-tools"
     :group "scene"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :scene}]
     :tool-ids ["scene.add-light" "scene.set-light-state"]
     :system-prompt "Use lighting tools to add and configure scene lights."})

  (mgr:register
    {:name "scene-skybox-tools"
     :group "scene"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :scene}]
     :tool-ids ["scene.set-skybox" "scene.set-background"]})

  (mgr:register
    {:name "scene-camera-tools"
     :group "scene"
     :default-state :auto
     :risk :normal
     :contexts [{:surface :scene}]
     :tool-ids ["scene.set-camera" "scene.reset-camera" "scene.screen-ray"]
     :system-prompt "Use camera tools to control the scene viewport."})

  (mgr:register
    {:name "scene-state-tools"
     :group "scene"
     :default-state :auto
     :risk :destructive
     :contexts [{:surface :scene}]
     :tool-ids ["scene.get-state" "scene.restore-state"]
     :system-prompt "Scene state operations can overwrite current data and require approval."}))

(fn register-scene-adapters [adapters]
  (local empty-schema {:type "object" :properties {}})

  (adapters:register
    {:id "scene.add-cuboid"
     :mcp-name "space_scene_add_cuboid"
     :description "Add a cuboid mesh to the scene."
     :inputSchema {:type "object"
                   :properties {:x {:type "number" :description "X position"}
                                :y {:type "number" :description "Y position"}
                                :z {:type "number" :description "Z position"}
                                :width {:type "number" :description "Width (default 1)"}
                                :height {:type "number" :description "Height (default 1)"}
                                :depth {:type "number" :description "Depth (default 1)"}
                                :color {:type "string" :description "Hex color"}}
                   :required []}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.scene "space_scene_add_cuboid requires app.scene")
                   (local element
                     (app.scene:add-physics-body
                       {:position (glm.vec3 (or args.x 0) (or args.y 0) (or args.z 0))
                        :size (glm.vec3 (or args.width 4) (or args.height 4) (or args.depth 4))}))
                   (assert element "space_scene_add_cuboid failed to create a cuboid")
                   "created"))})

  (adapters:register
    {:id "scene.add-physics-body"
     :mcp-name "space_scene_add_physics_body"
     :description "Add a physics body to the scene."
     :inputSchema {:type "object"
                   :properties {:shape {:type "string" :description "Shape type (box, sphere, cylinder)"}
                                :x {:type "number"} :y {:type "number"} :z {:type "number"}
                                :mass {:type "number" :description "Mass in kg (default 1)"}}
                   :required ["shape"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.scene "space_scene_add_physics_body requires app.scene")
                   (assert (or (= args.shape "box") (= args.shape "cuboid"))
                           (.. "unsupported physics body shape: " (tostring args.shape)))
                   (local element
                     (app.scene:add-physics-body
                       {:position (glm.vec3 (or args.x 0) (or args.y 0) (or args.z 0))}))
                   (assert element "space_scene_add_physics_body failed to create a body")
                   "created"))})

  (adapters:register
    {:id "scene.select-object"
     :mcp-name "space_scene_select_object"
     :description "Select an object in the scene."
     :inputSchema {:type "object" :properties {:id {:type "string" :description "Object ID to select"}} :required ["id"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.object-selector "space_scene_select_object requires app.object-selector")
                   (local selectable (find-selectable app.object-selector args.id))
                   (assert selectable (.. "selectable object not found: " args.id))
                   (app.object-selector:set-selected [selectable])
                   "selected"))})

  (adapters:register
    {:id "scene.add-terrain"
     :mcp-name "space_scene_add_terrain"
     :description "Add terrain to the scene."
     :inputSchema {:type "object"
                   :properties {:kind {:type "string" :description "Terrain kind (flat, heightfield, perlin)"}
                                :size {:type "number" :description "Terrain size"}}
                   :required []}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.scene "space_scene_add_terrain requires app.scene")
                   (local record (WorldData.add-terrain app.world-manager (active-world-id app) (or args.kind "flat-terrain")))
                   (assert record "space_scene_add_terrain failed to add terrain")
                   (tostring record.id)))})

  (adapters:register
    {:id "scene.raycast-terrain"
     :mcp-name "space_scene_raycast_terrain"
     :description "Raycast against the terrain to get height at a point."
     :inputSchema {:type "object" :properties {:x {:type "number"} :z {:type "number"}} :required ["x" "z"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.scene "space_scene_raycast_terrain requires app.scene")
                   (local info (app.scene:terrain-surface-under-point (glm.vec3 args.x 0 args.z)))
                   (assert info (.. "no terrain surface at x=" (tostring args.x) " z=" (tostring args.z)))
                   (tostring info.world-surface-y)))})

  (adapters:register
    {:id "scene.remove-terrain"
     :mcp-name "space_scene_remove_terrain"
     :description "Remove terrain from the scene. This is destructive."
     :inputSchema {:type "object" :properties {:id {:type "string" :description "Terrain ID to remove"}} :required ["id"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.scene "space_scene_remove_terrain requires app.scene")
                   (WorldData.remove-terrain app.world-manager (active-world-id app) args.id)
                   "removed"))})

  (adapters:register
    {:id "scene.add-light"
     :mcp-name "space_scene_add_light"
     :description "Add a light source to the scene."
     :inputSchema {:type "object"
                   :properties {:kind {:type "string" :description "Light type (point, directional, spot)"}
                                :x {:type "number"} :y {:type "number"} :z {:type "number"}
                                :color {:type "string" :description "Hex color"}
                                :intensity {:type "number"}}
                   :required ["kind"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.scene "space_scene_add_light requires app.scene")
                   (local record (WorldData.add-light app.world-manager (active-world-id app) args.kind))
                   (tostring record.id)))})

  (adapters:register
    {:id "scene.set-light-state"
     :mcp-name "space_scene_set_light_state"
     :description "Enable or disable a scene light."
     :inputSchema {:type "object"
                   :properties {:kind {:type "string" :description "Light kind"}
                                :id {:type "string" :description "Light ID"}
                                :enabled {:type "boolean" :description "Enable or disable"}}
                   :required ["kind" "id" "enabled"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.world-manager "space_scene_set_light_state requires app.world-manager")
                   (WorldData.update-light-record
                     app.world-manager
                     (active-world-id app)
                     args.kind
                     args.id
                     (fn [record]
                       (set record.enabled? args.enabled)))
                   "updated"))})

  (adapters:register
    {:id "scene.set-skybox"
     :mcp-name "space_scene_set_skybox"
     :description "Set the scene skybox texture or color."
     :inputSchema {:type "object"
                   :properties {:asset {:type "string" :description "Skybox asset name"}
                                :brightness {:type "number" :description "Skybox brightness"}}
                   :required ["asset"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.scene "space_scene_set_skybox requires app.scene")
                   (WorldData.update-skybox
                     app.world-manager
                     (active-world-id app)
                     {:enabled? true
                      :default {:name args.asset
                                :brightness (or args.brightness 0.1)
                                :tint-color [1.0 1.0 1.0]}
                      :by-theme {}})
                   "set"))})

  (adapters:register
    {:id "scene.set-background"
     :mcp-name "space_scene_set_background"
     :description "Set the scene background color."
     :inputSchema {:type "object" :properties {:color {:type "string" :description "Hex color"}} :required ["color"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.scene "space_scene_set_background requires app.scene")
                   (WorldData.update-background app.world-manager (active-world-id app) {:color (rgb-from-hex args.color)})
                   "set"))})

  (adapters:register
    {:id "scene.set-camera"
     :mcp-name "space_scene_set_camera"
     :description "Set the camera position and orientation."
     :inputSchema {:type "object"
                   :properties {:x {:type "number"} :y {:type "number"} :z {:type "number"}
                                :yaw {:type "number"} :pitch {:type "number"}}
                   :required ["x" "y" "z"]}
      :make-run (fn [app]
                  (fn [args]
                    (local camera (app.presentation-camera {:required? true}))
                    (camera:set-position (glm.vec3 args.x args.y args.z))
                    (when (or args.yaw args.pitch)
                      (camera:set-rotation (or args.yaw 0) (or args.pitch 0)))
                    "set"))})

  (adapters:register
    {:id "scene.reset-camera"
     :mcp-name "space_scene_reset_camera"
     :description "Reset the camera to default position."
     :inputSchema empty-schema
      :make-run (fn [app]
                  (fn [_args]
                    (local camera (app.presentation-camera {:required? true}))
                    (camera:reset)
                    "reset"))})

  (adapters:register
    {:id "scene.screen-ray"
     :mcp-name "space_scene_screen_ray"
     :description "Cast a ray from screen coordinates into the scene."
     :inputSchema {:type "object" :properties {:x {:type "number"} :y {:type "number"}} :required ["x" "y"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.scene "space_scene_screen_ray requires app.scene")
                   (local ray (app.scene:screen-pos-ray {:x args.x :y args.y}))
                   (.. "origin=(" ray.origin.x "," ray.origin.y "," ray.origin.z ") dir=(" ray.direction.x "," ray.direction.y "," ray.direction.z ")")))})

  (adapters:register
    {:id "scene.get-state"
     :mcp-name "space_scene_get_state"
     :description "Get the full scene state for backup purposes."
     :inputSchema empty-schema
     :make-run (fn [app]
                 (fn [_args]
                   (assert app.scene "space_scene_get_state requires app.scene")
                   (app.scene:capture-state)))})

  (adapters:register
    {:id "scene.restore-state"
     :mcp-name "space_scene_restore_state"
     :description "Restore scene state from a backup. This overwrites current data."
     :inputSchema {:type "object"
                   :properties {:state {:type "object" :description "Scene state to restore"}}
                   :required ["state"]}
     :make-run (fn [app]
                 (fn [args]
                   (assert app.scene "space_scene_restore_state requires app.scene")
                   (app.scene:restore-state args.state)
                   "restored"))})

  true)

(fn register [mgr]
  (local adapters (. mgr :tool-adapters))
  (when adapters
    (register-scene-adapters adapters))
  (register-scene-presets mgr)
  true)

{:register register}
