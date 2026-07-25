(local glm (require :glm))
(local {: LayoutRoot} (require :layout))
(local DemoDialogs (require :demo-dialogs))
(local DemoPhysicsBodies (require :demo-physics-bodies))
(local LayoutPhysicsBodies (require :layout-physics-bodies))
(local DemoLines (require :demo-lines))
(local DemoPoints (require :demo-points))
(local DemoAudio (require :demo-audio))
(local Container (require :container))
(local {: WidgetCuboid} (require :widget-cuboid))
(local GraphNodeCube (require :graph-node-cube))
(local Sized (require :sized))
(local SceneWorldState (require :scene-world-state))
(local GltfMesh (require :gltf-mesh))
(local BuildContext (require :build-context))
(local viewport-utils (require :viewport-utils))
(local MathUtils (require :math-utils))
(local CoordinateGuard (require :coordinate-guard))
(local logging (require :logging))
(local TerrainIssueLog (require :terrain-issue-log))
(local TerrainQuery (require :terrain-query))
(local TerrainLayoutRecord (require :terrain-layout-record))
(local LightingViewState (require :lighting-view-state))
(local SkyboxState (require :skybox-state))
(local BackgroundState (require :background-state))
(local default-position (glm.vec3 0 0 0))
(local default-rotation (glm.quat 1 0 0 0))
(local default-depth-scale 0.35)
(local default-height-depth-scale 0.2)
(local default-panel-body-options {:friction 0.95
                                   :rolling-friction 0.2
                                   :spinning-friction 0.35
                                   :linear-damping 0.04
                                   :angular-damping 0.35})
(local default-camera-distance 100.0)

(local vec3->array (. MathUtils :vec3->array))
(local quat->array (. MathUtils :quat->array))
(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))
(local safe-vec3? CoordinateGuard.safe-vec3?)

;; Built-in kinds here are only for scene-owned restore strategies.
;; Balls have already moved to the generic object protocol via add-object.
;; Physics bodies, graph-node cubes, and the demo browser should eventually
;; follow the same direction. Terrain is still special for now because scene
;; owns terrain queries, replacement, and selection infrastructure.
(local built-in-scene-kinds {:graph-node-cube true
                             :physics-cuboid true
                             :demo-browser true})

(fn normalize-or [value fallback]
  (if (and value (> (glm.length value) 1e-6))
      (glm.normalize value)
      fallback))

(local terrain-layout-record TerrainLayoutRecord.from-metadata)

(fn terrain-child-transform [record fallback-position fallback-rotation element]
  (if (= (and record record.kind) "heightfield-terrain")
      {:position (and element element.layout element.layout.position)
       :rotation (and element element.layout element.layout.rotation)}
      {:position fallback-position
       :rotation fallback-rotation}))

(fn resolve-camera-placement [self]
  (local camera self.camera)
  (assert camera "Scene camera placement requires self.camera")
  (assert camera.position "Scene camera placement requires self.camera.position")
  (local origin camera.position)
  (local fallback-forward (self.default-rotation:rotate (glm.vec3 0 0 -1)))
  (local forward
    (normalize-or (and camera camera.get-forward (camera:get-forward))
                  fallback-forward))
  (local projected (glm.vec3 forward.x 0 forward.z))
  (local target
    (normalize-or (* projected (glm.vec3 -1))
                  (glm.vec3 0 0 1)))
  (local yaw (- (math.atan target.x (- target.z))))
  (local yaw-rotation (glm.quat yaw (glm.vec3 0 1 0)))
  (local facing-rotation (* yaw-rotation (glm.quat math.pi (glm.vec3 0 1 0))))
  {:center (+ origin (* forward (glm.vec3 default-camera-distance)))
   :rotation facing-rotation})

(fn layout-origin-from-center [center rotation size]
  (local resolved-center (or center (glm.vec3 0 0 0)))
  (local resolved-rotation (or rotation (glm.quat 1 0 0 0)))
  (local resolved-size (or size (glm.vec3 0 0 0)))
  (- resolved-center (resolved-rotation:rotate (* 0.5 resolved-size))))

(fn resolve-active-theme []
  (and app.engine app.themes app.themes.get-active-theme
       (app.themes.get-active-theme)))

(fn apply-active-theme [ctx]
  (when (and ctx ctx.set-theme)
    (ctx:set-theme (resolve-active-theme))))

(fn merge-panel-body-options [opts]
  (local merged {})
  (each [key value (pairs default-panel-body-options)]
    (set (. merged key) value))
  (each [key value (pairs (or (and opts opts.body-options) {}))]
    (set (. merged key) value))
  merged)

(fn add-widget-as-cuboid [_self widget-builder opts]
  (assert widget-builder "Scene.add-widget-as-cuboid requires a widget builder")
  (local options (or opts {}))
  (local depth-scale (or options.depth-scale default-depth-scale))
  (local height-depth-scale (or options.height-depth-scale default-height-depth-scale))

  (fn cuboid-builder [ctx runtime-opts]
    (local wc-opts {:child widget-builder
                    :min-depth 10
                    :depth-scale depth-scale
                    :height-depth-scale height-depth-scale})
    (when options.side-color
      (set wc-opts.side-color options.side-color))
    ((WidgetCuboid wc-opts)
     ctx runtime-opts)))

  (fn collect-positioned-movables [children]
  (var entries [])
  (each [_ metadata (ipairs (or children []))]
    (local element (and metadata metadata.element))
    (local layout (and element element.layout))
    (when layout
        (table.insert entries {:target layout
                               :handle element
                               :owner element})))
  entries)

(fn collect-scene-object-movables [entity]
  (var entries [])
  (each [_ entry (ipairs (or (and entity entity.scene-objects) []))]
    (local movable (and entry entry.movable))
    (local element (and entry entry.element))
    (local layout (and element element.layout))
    (when (and movable layout)
      (table.insert entries {:target layout
                             :handle (or movable.handle element)
                             :key (or movable.key element)
                             :owner (or movable.owner element)
                             :pointer-target movable.pointer-target
                             :on-drag-start movable.on-drag-start
                             :on-drag-end movable.on-drag-end})))
  entries)

(fn resolve-min-size [layout]
  (and layout layout.min-size))

(fn to-graph-position [position]
  (if position
      (glm.vec3 position.x position.y 0)
      (glm.vec3 0 0 0)))

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn vec4->array [value]
  (if value
      [value.x value.y value.z value.w]
      nil))

(fn capture-panel-layout-state [metadata]
  (local element (and metadata metadata.element))
  (local layout (and element element.layout))
  (if (not (and element layout))
      nil
      (do
        (local size (or layout.size layout.measure))
        {:position (vec3->array layout.position)
         :rotation (quat->array layout.rotation)
         :size (and size (vec3->array size))})))

(fn find-scene-metadata-by-element [children element]
  (var found nil)
  (when (and children element)
    (each [_ metadata (ipairs children)]
      (when (and (not found)
                 (= (and metadata metadata.element) element))
        (set found metadata))))
  found)

(fn clone-terrain-binding [binding]
  (if (= binding nil)
      nil
      (do
        (assert (= (type binding) :table)
                "Scene terrain binding must be a table")
        (local out (clone-table binding))
        (if (= out.enabled? nil)
            (set out.enabled? true))
        out)))

(fn resolve-terrain-binding [opts object-config]
  (local explicit (and opts opts.terrain-binding))
  (local object-binding (and object-config object-config.terrain-binding))
  (clone-terrain-binding (or explicit object-binding nil)))

(fn find-metadata-index-by-element [children element]
  (var found nil)
  (when (and children element)
    (each [idx metadata (ipairs children)]
      (when (and (not found)
                 (= (and metadata metadata.element) element))
        (set found idx))))
  found)

(fn insert-layout-child [parent-layout idx child-layout]
  (assert parent-layout "Scene.insert-layout-child requires parent layout")
  (assert child-layout "Scene.insert-layout-child requires child layout")
  (local insert-index (or idx (+ (length parent-layout.children) 1)))
  (set child-layout.parent parent-layout)
  (child-layout:set-root parent-layout.root)
  (set child-layout.depth-offset-index parent-layout.depth-offset-index)
  (set child-layout.clip-region parent-layout.clip-region)
  (child-layout:set-parent-culled (parent-layout:effective-culled?))
  (table.insert parent-layout.children insert-index child-layout))

(fn find-terrain-entry [scene-terrains terrain-id]
  (var resolved nil)
  (when scene-terrains
    (each [idx metadata (ipairs scene-terrains)]
      (local record (and metadata metadata.record))
      (when (and (not resolved)
                 (= (and record record.id) terrain-id))
        (set resolved {:index idx
                       :metadata metadata}))))
  resolved)

(fn require-terrain-runtime-entry [scene terrain-id]
  (local entity scene.entity)
  (local terrain-entry (find-terrain-entry scene.scene-terrains terrain-id))
  (assert entity (.. "Scene terrain runtime missing entity for terrain " terrain-id))
  (assert terrain-entry (.. "Scene terrain runtime missing terrain entry for " terrain-id))
  (local current-metadata terrain-entry.metadata)
  (local current-element (and current-metadata current-metadata.element))
  (local child-index (find-metadata-index-by-element entity.children current-element))
  (assert current-element (.. "Scene terrain runtime missing element for terrain " terrain-id))
  (assert child-index (.. "Scene terrain runtime missing child index for terrain " terrain-id))
  {:entity entity
   :terrain-entry terrain-entry
   :current-metadata current-metadata
   :current-element current-element
   :child-index child-index})

(fn require-terrain-selection-method [element terrain-id method-name]
  (assert (. element method-name)
          (.. "Scene terrain runtime missing "
              method-name
              " for terrain "
              terrain-id)))

(fn collect-positioned-resizables [children]
  (var entries [])
  (each [_ metadata (ipairs (or children []))]
    (local element (and metadata metadata.element))
    (local layout (and element element.layout))
    (when layout
      (local min-size (resolve-min-size layout))
      (table.insert entries {:target layout
                             :handle layout
                             :key element
                             :min-size min-size
                             :owner element})))
  entries)

(fn copy-movables [entries]
  (var copied [])
  (each [_ entry (ipairs (or entries []))]
    (when entry
      (table.insert copied entry)))
  copied)

(fn compute-entity-movables [self entity]
  (local base (or entity.__scene_base_movables []))
  (local entries (copy-movables base))
  (local scene-object-movables (collect-scene-object-movables entity))
  (local scene-object-targets {})
  (each [_ entry (ipairs scene-object-movables)]
    (table.insert entries entry)
    (when (and entry entry.target)
      (set (. scene-object-targets entry.target) true)))
  (local physics-movables (LayoutPhysicsBodies.collect-movables entity))
  (local physics-targets {})
  (each [_ entry (ipairs physics-movables)]
    (when entry
      (table.insert entries entry)))
  (each [_ entry (ipairs physics-movables)]
    (when (and entry entry.target)
      (set (. physics-targets entry.target) true)))
  (each [_ entry (ipairs (collect-positioned-movables self.scene-children))]
    (when (and (not (. physics-targets entry.target))
               (not (. scene-object-targets entry.target)))
      (table.insert entries entry)))
  entries)

(fn compute-entity-resizables [self entity]
  (local base (or entity.__scene_base_resizables []))
  (local entries (copy-movables base))
  (each [_ entry (ipairs (collect-positioned-resizables self.scene-children))]
    (table.insert entries entry))
  entries)

(fn make-default-builder [opts]
  (local options (or opts {}))
  (local terrain-records
    (SceneWorldState.resolve-terrain-records options.terrains))
  (local terrain-entries
    (SceneWorldState.build-terrain-entries terrain-records))
  (local scene-children [])
  (local terrain-children [])

  (fn build [ctx]
    (local container-children [])
    (each [_ entry (ipairs terrain-entries)]
      (local terrain-builder entry.builder)
      (local terrain-record entry.record)
      (local terrain-position entry.position)
      (local terrain-rotation entry.rotation)
      (table.insert container-children
                    (fn [child-ctx]
                      (local element (terrain-builder child-ctx))
                      (table.insert terrain-children {:element element
                                                      :record terrain-record})
                      (local transform
                        (terrain-child-transform terrain-record
                                                 terrain-position
                                                 terrain-rotation
                                                 element))
                      {:element element
                       :position transform.position
                       :rotation transform.rotation})))
    (local builder
      (Container {:children
                  container-children}))
    (local entity (builder ctx))
    (set entity.scene-children scene-children)
    (set entity.scene-terrains terrain-children)
    ;(DemoLines.attach ctx entity)
    ;(DemoPoints.attach ctx entity)
    (DemoAudio.attach entity)
    (set entity.movables (collect-positioned-movables scene-children))
    entity))

(fn Scene [opts]
  (local options (or opts {}))
  (local layout-root (LayoutRoot {:log-dirt? true}))
  (local focus-manager options.focus-manager)
  (local focus-root (and focus-manager (focus-manager:get-root-scope)))
  (local focus-scope
    (or options.focus-scope
        (and focus-manager
             (focus-manager:create-scope {:name (or options.focus-scope-name "scene")}))))
  (local ctx
    (BuildContext {:theme (resolve-active-theme)
                       :clickables app.clickables
                       :hoverables app.hoverables
                       :touch-gesture-targets app.touch-gesture-targets
                       :system-cursors app.system-cursors
                       :icons options.icons
                       :states options.states
                       :object-selector options.object-selector
                       :layout-root layout-root
                       :movables options.movables
                       :focus-manager focus-manager
                       :focus-parent focus-root
                       :focus-scope focus-scope}))
  (local self {:layout-root layout-root
                :build-context ctx
                :activity-slots {}
                :active-activity-slot-id nil
                :active-activity-slot nil
                :debug-id (or options.debug-id "scene")
                :projection nil
                :projection-version 0
                :viewport nil
                :entity nil
                :builder nil
                :graph options.graph
                :graph-map options.graph-map
                 :panel-restorers {}
                 :demo-browser nil
                 :scene-children nil
                 :queued-cube-panels []
                :scene-terrains nil
                :physics-body-count 0
                :default-position (or options.position default-position)
                :default-rotation (or options.rotation default-rotation)
                :on-terrains-changed options.on-terrains-changed
                :reference-point default-position
                :focus-manager focus-manager
                :focus-scope focus-scope
                :camera options.camera
                :interaction-surface :scene
                :default-panel-location "float"})

  (set ctx.pointer-target self)
  (set ctx.panel-target self)

  (fn clone-vec3 [value]
    (and value
         (glm.vec3 value.x value.y value.z)))

  (fn clone-quat [value]
    (and value
         (glm.quat value.w value.x value.y value.z)))

  (fn count-label [items]
    (if (= items nil)
        "nil"
        (tostring (length items))))

  (fn terrain-entry-id [entry]
    (or (and entry entry.record entry.record.id)
        (and entry entry.id)
        "?"))

  (fn terrain-id-summary [items]
    (if (= items nil)
        "nil"
        (do
          (local ids [])
          (local total (length items))
          (each [idx entry (ipairs items)]
            (when (<= idx 5)
              (table.insert ids (terrain-entry-id entry))))
          (local joined (table.concat ids ","))
          (if (> total 5)
              (.. joined ",...")
              joined))))

  (fn log-terrain-diagnostic [self level event extra]
    (local entity self.entity)
    (local entity-terrains (and entity entity.scene-terrains))
    (local entity-children (and entity entity.children))
    (local extra-text
      (if extra
          (.. " " extra)
          ""))
    (local message
      (string.format
        "[scene] terrain-diagnostic scene=%s event=%s builder=%s entity=%s scene-terrains=%s entity.scene-terrains=%s shared=%s scene-children=%s entity.children=%s runtime=%s ids=%s%s"
        self.debug-id
        event
        (tostring (not (= self.builder nil)))
        (tostring (not (= entity nil)))
        (count-label self.scene-terrains)
        (count-label entity-terrains)
        (tostring (= self.scene-terrains entity-terrains))
        (count-label self.scene-children)
        (count-label entity-children)
        (count-label self.__terrain-runtime-state)
        (terrain-id-summary self.scene-terrains)
        extra-text))
    (if (= level :warn)
        (TerrainIssueLog.warn message)
        (TerrainIssueLog.info message))
    (set self.__terrain-last-diagnostic event))

  (fn vec3-approx= [left right]
    (and left
         right
         (< (math.abs (- left.x right.x)) 1e-6)
         (< (math.abs (- left.y right.y)) 1e-6)
         (< (math.abs (- left.z right.z)) 1e-6)))

  (fn quat-approx= [left right]
    (and left
         right
         (< (math.abs (- left.w right.w)) 1e-6)
         (< (math.abs (- left.x right.x)) 1e-6)
         (< (math.abs (- left.y right.y)) 1e-6)
         (< (math.abs (- left.z right.z)) 1e-6)))

  (fn capture-terrain-runtime-state [self]
    (icollect [_ metadata (ipairs (or self.scene-terrains []))]
      (do
        (local record (and metadata metadata.record))
        (local layout (and metadata metadata.element metadata.element.layout))
        {:id (and record record.id)
         :position (clone-vec3 (and layout layout.position))
         :rotation (clone-quat (and layout layout.rotation))})))

  (fn terrain-runtime-state= [left right]
    (and (= (length (or left [])) (length (or right [])))
         (accumulate [same? true idx entry (ipairs (or left []))]
           (if (not same?)
               false
               (do
                 (local other (. right idx))
                 (and other
                      (= entry.id other.id)
                      (vec3-approx= entry.position other.position)
                      (quat-approx= entry.rotation other.rotation)))))))

  (fn notify-terrains-changed [self]
    (set self.__terrain-runtime-state (capture-terrain-runtime-state self))
    (log-terrain-diagnostic self :info "notify-terrains-changed")
    (when self.on-terrains-changed
      (self.on-terrains-changed self)))

  (fn sync-terrain-runtime-state [self]
    (local current (capture-terrain-runtime-state self))
    (when (not (terrain-runtime-state= self.__terrain-runtime-state current))
      (set self.__terrain-runtime-state current)
      (when self.on-terrains-changed
        (self.on-terrains-changed self))))
  (apply-active-theme ctx)

  ;; Activity slot infrastructure
  (fn make-slot-focus-scope [activity-id]
    (and focus-manager
         (focus-manager:create-scope {:name (.. "scene:" activity-id)
                                      :directional-traversal-boundary? true})))

  (fn make-slot-pointer-target [slot]
    {:interaction-surface :scene
     :activity-slot slot
     :screen-pos-ray (fn [_target pos opts]
                       (self:screen-pos-ray pos opts))})

  (fn make-slot-build-context [slot slot-layout-root slot-focus-scope]
    (local slot-ctx
      (BuildContext {:theme (resolve-active-theme)
                     :clickables app.clickables
                     :hoverables app.hoverables
                     :touch-gesture-targets app.touch-gesture-targets
                     :system-cursors app.system-cursors
                     :icons options.icons
                     :states options.states
                     :object-selector options.object-selector
                     :layout-root slot-layout-root
                     :movables options.movables
                     :focus-manager focus-manager
                     :focus-parent focus-scope
                     :focus-scope slot-focus-scope}))
    (set slot-ctx.pointer-target slot.pointer-target)
    (set slot-ctx.panel-target slot)
    (apply-active-theme slot-ctx)
    slot-ctx)

  (fn make-activity-slot [activity-id]
    (local slot-focus-scope (make-slot-focus-scope activity-id))
    (local slot-layout-root (LayoutRoot {:log-dirt? true}))
    (local slot
      {:activity-id activity-id
       :interaction-surface :scene
       :surface :scene
       :ctx nil
       :build-context nil
       :layout-root slot-layout-root
       :focus-scope slot-focus-scope
       :pointer-target nil
       :root nil
       :entity nil
       :scene-children nil
       :scene-terrains nil
       :queued-cube-panels []
       :panel-restorers {}
       :demo-browser nil
       :physics-body-count 0
       :scene-state nil
       :visible? false
       :interactive? false})
    (set slot.pointer-target (make-slot-pointer-target slot))
    (set slot.ctx (make-slot-build-context slot slot-layout-root slot-focus-scope))
    (set slot.build-context slot.ctx)
    (set slot.activate
         (fn [slot-self]
           (when (and focus-manager
                      focus-scope
                      slot-self.focus-scope
                      (not slot-self.focus-scope.parent))
             (focus-manager:attach slot-self.focus-scope focus-scope))
           (set slot-self.visible? true)
           (set slot-self.interactive? true)
           slot-self))
    (set slot.deactivate
         (fn [slot-self]
           (set slot-self.visible? false)
           (set slot-self.interactive? false)
           (when (and focus-manager
                      slot-self.focus-scope
                      slot-self.focus-scope.parent)
             (focus-manager:detach slot-self.focus-scope))
           slot-self))
    (set slot.drop
          (fn [slot-self]
            (slot-self:deactivate)
            (when (and slot-self.root slot-self.root.drop)
              (slot-self.root:drop))
            (set slot-self.root nil)
            (set slot-self.entity nil)
            (set slot-self.scene-children nil)
            (set slot-self.scene-terrains nil)
            (set slot-self.queued-cube-panels [])
            (set slot-self.demo-browser nil)
            (set slot-self.physics-body-count 0)
            (when slot-self.focus-scope
              (slot-self.focus-scope:drop)
              (set slot-self.focus-scope nil))
            true))
    (slot:deactivate)
    slot)

  (fn active-render-context []
    (if (and self.active-activity-slot
             self.active-activity-slot.visible?)
        self.active-activity-slot.ctx
        self.build-context))

  (fn ensure-activity-slot [_scene activity-id]
    (assert (= (type activity-id) :string)
            "Scene.ensure-activity-slot requires string activity id")
    (assert (> (# activity-id) 0)
            "Scene.ensure-activity-slot requires non-empty activity id")
    (local existing (. self.activity-slots activity-id))
    (if existing
        existing
        (do
          (local ActivitySceneState (require :activity-scene-state))
          (local slot (make-activity-slot activity-id))
          (set slot.scene-state (ActivitySceneState.empty-state))
          (set (. self.activity-slots activity-id) slot)
          slot)))

  (fn activity-slot [_scene activity-id]
    (assert (= (type activity-id) :string)
            "Scene.activity-slot requires string activity id")
    (. self.activity-slots activity-id))

  (fn capture-active-service-state [scene]
    (local lights
      (if (and app app.lights app.lights.get-state)
          (app.lights:get-state)
          nil))
    (local skybox
      (if (and app app.renderers app.renderers.skybox app.renderers.skybox.get-state)
          (scene:get-skybox-state)
          nil))
    (local background
      (if (and app app.renderers app.renderers.get-background-state)
          (scene:get-background-state)
          nil))
    (local PhysicsContainment (require :physics-containment))
    (local containment
      (if app.physics-containment-config
          (PhysicsContainment.serialize-config app.physics-containment-config)
          {:enabled? false}))
    {:lights lights
     :skybox skybox
     :background background
     :containment containment})

  (fn apply-state-to-services [scene state]
    (assert state "Scene.apply-state-to-services requires state")
    (local (ok err) (pcall
                    (fn []
                      (when (and state.lights
                                 app app.lights app.lights.set-state)
                        (app.lights:set-state state.lights))
                      (when (and state.skybox
                                 app app.renderers app.renderers.skybox app.renderers.skybox.set-state)
                        (app.renderers.skybox:set-state state.skybox))
                      (when (and state.background
                                 app app.renderers app.renderers.set-background-state)
                        (app.renderers:set-background-state state.background))
                      (when state.containment
                        (local PhysicsContainment (require :physics-containment))
                        (PhysicsContainment.ensure-installed {:config state.containment :scene scene})))))
    (if (not ok)
        (do
          ;; Transactional rollback: reset all services to empty
          (local ActivitySceneState (require :activity-scene-state))
          (local empty (ActivitySceneState.empty-state))
          (pcall
            (fn []
              (when (and app app.lights app.lights.set-state)
                (app.lights:set-state empty.lights))
              (when (and app app.renderers app.renderers.skybox app.renderers.skybox.set-state)
                (app.renderers.skybox:set-state empty.skybox))
              (when (and app app.renderers app.renderers.set-background-state)
                (app.renderers:set-background-state empty.background))
              (when app.engine
                (local PhysicsContainment (require :physics-containment))
                (PhysicsContainment.ensure-installed {:config empty.containment :scene scene}))))
          (error err))
        true))

  (fn reset-services-to-empty [scene]
    (local ActivitySceneState (require :activity-scene-state))
    (local empty (ActivitySceneState.empty-state))
    (apply-state-to-services scene empty))

  (fn assert-active-content-slot []
    (assert self.active-activity-slot
            "Scene content mutation requires an active activity scene slot"))

  (fn activate-activity-slot [scene activity-id]
    (local slot (ensure-activity-slot scene activity-id))
    (local was-different-slot
      (and self.active-activity-slot
           (not (= self.active-activity-slot slot))))
    ;; Capture and deactivate old slot (but keep it in a snapshot for rollback)
    (local previous-slot self.active-activity-slot)
    (local previous-slot-id self.active-activity-slot-id)
    (when was-different-slot
      ;; Capture old active services state onto the old slot
      (set self.active-activity-slot.scene-state
           (capture-active-service-state self))
      ;; Capture old slot's content state back to its slot fields
      (set self.active-activity-slot.entity self.entity)
      (set self.active-activity-slot.scene-children self.scene-children)
      (set self.active-activity-slot.scene-terrains self.scene-terrains)
      (set self.active-activity-slot.queued-cube-panels self.queued-cube-panels)
      (set self.active-activity-slot.panel-restorers self.panel-restorers)
      (set self.active-activity-slot.demo-browser self.demo-browser)
      (set self.active-activity-slot.physics-body-count self.physics-body-count)
      ;; Deactivate old physics bodies
      (when (and self.active-activity-slot.entity
                 (pcall require :layout-physics-bodies))
        (local LayoutPhysicsBodies (require :layout-physics-bodies))
        (pcall LayoutPhysicsBodies.deactivate self.active-activity-slot.entity))
      (self.active-activity-slot:deactivate)
      ;; Clear active binding
      (set self.active-activity-slot nil)
      (set self.active-activity-slot-id nil))
    ;; Reset engine services to empty before applying target state
    (reset-services-to-empty self)
    ;; Bind target slot content to Scene surface aliases BEFORE activation
    (set self.entity slot.entity)
    (set self.scene-children slot.scene-children)
    (set self.scene-terrains slot.scene-terrains)
    (set self.queued-cube-panels slot.queued-cube-panels)
    (set self.panel-restorers slot.panel-restorers)
    (set self.demo-browser slot.demo-browser)
    (set self.physics-body-count slot.physics-body-count)
    ;; Try applying target slot's stored scene state to engine services
    (local (service-ok service-err)
      (pcall
        (fn []
          (when slot.scene-state
            (apply-state-to-services self slot.scene-state)))))
    (if (not service-ok)
        (do
          ;; Rollback: reset services to empty, restore previous slot binding
          (reset-services-to-empty self)
          (when previous-slot
            ;; Restore previous slot's content and activation
            (set self.entity previous-slot.entity)
            (set self.scene-children previous-slot.scene-children)
            (set self.scene-terrains previous-slot.scene-terrains)
            (set self.queued-cube-panels previous-slot.queued-cube-panels)
            (set self.panel-restorers previous-slot.panel-restorers)
            (set self.demo-browser previous-slot.demo-browser)
            (set self.physics-body-count previous-slot.physics-body-count)
            (previous-slot:activate)
            (set self.active-activity-slot previous-slot)
            (set self.active-activity-slot-id previous-slot-id)
            ;; Restore previous services
            (when previous-slot.scene-state
              (apply-state-to-services self previous-slot.scene-state))
            ;; Reactivate physics
            (when (and previous-slot.entity
                       (pcall require :layout-physics-bodies))
              (local LayoutPhysicsBodies (require :layout-physics-bodies))
              (pcall LayoutPhysicsBodies.activate previous-slot.entity)))
          (error (.. "Scene.activate-activity-slot service application failed: " (tostring service-err)))))
    ;; Activate target slot (services succeeded)
    (slot:activate)
    (set self.active-activity-slot-id activity-id)
    (set self.active-activity-slot slot)
    ;; Build terrain from stored records if slot has no terrain yet and has records
    (when (and slot.scene-state
               slot.scene-state.terrains
               (> (length slot.scene-state.terrains) 0)
               (not self.scene-terrains))
      (pcall (fn [] (self:build-default {:terrains slot.scene-state.terrains}))))
    ;; Activate target physics bodies
    (when (and slot.entity
               (pcall require :layout-physics-bodies))
      (local LayoutPhysicsBodies (require :layout-physics-bodies))
      (pcall LayoutPhysicsBodies.activate slot.entity))
    slot)

  (fn capture-activity-slot-state [scene activity-id]
    (local slot (ensure-activity-slot scene activity-id))
    (local is-active (= self.active-activity-slot slot))
    ;; Capture panels and terrains from the slot's own content,
    ;; not from the current active slot's aliases.
    (local panels [])
    (local source-children
      (if is-active
          self.scene-children
          slot.scene-children))
    (when source-children
      (each [_ metadata (ipairs (or source-children []))]
        (local persistence (and metadata metadata.persistence))
        (when persistence
          (local capture-layout (capture-panel-layout-state metadata))
          (when capture-layout
            (local record (clone-table persistence))
            (set record.position capture-layout.position)
            (set record.rotation capture-layout.rotation)
            (set record.size (or capture-layout.size record.size))
            (table.insert panels record)))))
    ;; Preserve queued cube panels from slot's own queued list
    (local source-queued
      (if is-active
          self.queued-cube-panels
          slot.queued-cube-panels))
    (each [_ panel (ipairs (or source-queued []))]
      (table.insert panels (clone-table panel)))
    (local source-terrains
      (if is-active
          self.scene-terrains
          slot.scene-terrains))
    (local terrains
      (if (= source-terrains nil)
          nil
          (SceneWorldState.capture-terrains source-terrains)))
    ;; Capture service state: for active slot, read from live engine;
    ;; for inactive slot, use stored scene-state services.
    (local services
      (if is-active
          (capture-active-service-state self)
          (or slot.scene-state
              (do
                (local ActivitySceneState (require :activity-scene-state))
                (ActivitySceneState.empty-state)))))
    ;; Build canonical state
    (local ActivitySceneState (require :activity-scene-state))
    (local state
      {:panels panels
       :terrains (or terrains [])
       :lights services.lights
       :skybox services.skybox
       :background services.background
       :containment services.containment})
    (local canonical (ActivitySceneState.normalize-state state "Scene.capture-activity-slot-state"))
    (set slot.scene-state canonical)
    canonical)

  (fn restore-activity-slot-state [scene activity-id state]
    (assert (= (type state) :table)
            "Scene.restore-activity-slot-state requires a state table")
    (local ActivitySceneState (require :activity-scene-state))
    (local canonical (ActivitySceneState.normalize-state state "Scene.restore-activity-slot-state"))
    (local slot (ensure-activity-slot scene activity-id))
    (set slot.scene-state canonical)
    ;; If this slot is currently active, apply state and rebuild terrain immediately
    (when (= self.active-activity-slot slot)
      (apply-state-to-services self canonical)
      ;; Rebuild terrain runtime from stored records (panels deferred to Task 5).
      ;; Each canonical terrain record is built exactly once.
      (when (and canonical.terrains (> (length canonical.terrains) 0))
        (if (not self.entity)
            ;; No base entity yet — build-default creates entity and all terrains
            (self:build-default {:terrains canonical.terrains})
            ;; Entity already exists — add only missing terrain records
            (do
              (local entries (SceneWorldState.build-terrain-entries canonical.terrains))
              (each [_ entry (ipairs entries)]
                (self:add-terrain-record entry.record))))))
    true)

  (fn deactivate-activity-slot [_scene activity-id]
    (local slot (activity-slot self activity-id))
    (when slot
      (slot:deactivate)
      (when (= self.active-activity-slot slot)
        ;; Unbind content aliases; slot retains ownership
        (set self.entity nil)
        (set self.scene-children nil)
        (set self.scene-terrains nil)
        (set self.queued-cube-panels [])
        (set self.panel-restorers {})
        (set self.demo-browser nil)
        (set self.physics-body-count 0)
        (set self.active-activity-slot nil)
        (set self.active-activity-slot-id nil)))
    slot)

  (fn drop-activity-slot [_scene activity-id]
    (local slot (activity-slot self activity-id))
    (when slot
      (slot:drop)
      (when (= self.active-activity-slot slot)
        (set self.active-activity-slot nil)
        (set self.active-activity-slot-id nil))
      (set (. self.activity-slots activity-id) nil))
    true)

  (fn normalize-movable-entry [_self entry]
    (if (not entry)
        (error "Movable entry must not be nil")
        (do
          (local etype (type entry))
          (when (not (= etype :table))
            (error (.. "Movable entry must be a table, got " etype)))
          (local target entry.target)
          (when (not target)
            (error "Movable entry must include :target"))
          {:target target
           :handle entry.handle
           :pointer-target entry.pointer-target
           :key entry.key
           :owner entry.owner
           :on-drag-start entry.on-drag-start
           :on-drag-end entry.on-drag-end})))

  (fn register-movable-entries [self entity entries]
    (when (and entity app.movables)
      (local keys (or entity.__scene_movable_keys []))
      (local records (or entity.__scene_movable_records []))
      (each [_ entry (ipairs entries)]
        (local target entry.target)
        (local handle (or entry.handle target))
        (local widget (or handle target))
        (local options {})
        (set options.target target)
        (when handle (set options.handle handle))
        (when entry.pointer-target (set options.pointer-target entry.pointer-target))
        (when entry.on-drag-start (set options.on-drag-start entry.on-drag-start))
        (when entry.on-drag-end (set options.on-drag-end entry.on-drag-end))
        (local key (or entry.key widget entry))
        (when key
          (set options.key key)
          (app.movables:register widget options)
          (table.insert keys key)
          (table.insert records {:key key
                                 :owner entry.owner})))
      (set entity.__scene_movable_keys keys)
      (set entity.__scene_movable_records records)))

  (fn register-entity-movables [self entity]
    (when (and entity app.movables)
      (local entries (icollect [_ entry (ipairs (or entity.movables []))]
                               (normalize-movable-entry self entry)))
      (var filtered [])
      (each [_ entry (ipairs entries)]
        (when entry
          (when (not entry.pointer-target)
            (set entry.pointer-target self))
          (table.insert filtered entry)))
      (when (= (length filtered) 0)
        (table.insert filtered {:target entity.layout
                                :pointer-target self}))
      (register-movable-entries self entity filtered)))

  (fn normalize-resizable-entry [_self entry]
    (if (not entry)
        (error "Resizable entry must not be nil")
        (do
          (local etype (type entry))
          (when (not (= etype :table))
            (error (.. "Resizable entry must be a table, got " etype)))
          (local target entry.target)
          (when (not target)
            (error "Resizable entry must include :target"))
          {:target target
           :handle entry.handle
           :pointer-target entry.pointer-target
           :key entry.key
           :owner entry.owner
           :min-size entry.min-size
           :max-size entry.max-size
           :on-resize-start entry.on-resize-start
           :on-resize-end entry.on-resize-end})))

  (fn register-resizable-entries [self entity entries]
    (when (and entity app.resizables)
      (local keys (or entity.__scene_resizable_keys []))
      (local records (or entity.__scene_resizable_records []))
      (each [_ entry (ipairs entries)]
        (local target entry.target)
        (local handle (or entry.handle target))
        (local widget (or handle target))
        (local options {})
        (set options.target target)
        (when handle (set options.handle handle))
        (when entry.pointer-target (set options.pointer-target entry.pointer-target))
        (when entry.min-size (set options.min-size entry.min-size))
        (when entry.max-size (set options.max-size entry.max-size))
        (when entry.on-resize-start (set options.on-resize-start entry.on-resize-start))
        (when entry.on-resize-end (set options.on-resize-end entry.on-resize-end))
        (local key (or entry.key widget entry))
        (when key
          (set options.key key)
          (app.resizables:register widget options)
          (table.insert keys key)
          (table.insert records {:key key
                                 :owner entry.owner})))
      (set entity.__scene_resizable_keys keys)
      (set entity.__scene_resizable_records records)))

  (fn register-entity-resizables [self entity]
    (when (and entity app.resizables)
      (local entries (icollect [_ entry (ipairs (or entity.resizables []))]
                               (normalize-resizable-entry self entry)))
      (var filtered [])
      (each [_ entry (ipairs entries)]
        (when entry
          (when (not entry.pointer-target)
            (set entry.pointer-target self))
          (table.insert filtered entry)))
      (when (= (length filtered) 0)
        (table.insert filtered {:target entity.layout
                                :pointer-target self}))
      (register-resizable-entries self entity filtered)))

  (fn unregister-entity-movables [self entity]
    (when (and entity app.movables)
      (local keys entity.__scene_movable_keys)
      (if (and keys (> (length keys) 0))
          (each [_ key (ipairs keys)]
            (app.movables:unregister key))
          (app.movables:unregister entity))
      (set entity.__scene_movable_keys nil)
      (set entity.__scene_movable_records nil)))

  (fn unregister-entity-resizables [self entity]
    (when (and entity app.resizables)
      (local keys entity.__scene_resizable_keys)
      (if (and keys (> (length keys) 0))
          (each [_ key (ipairs keys)]
            (app.resizables:unregister key))
          (app.resizables:unregister entity))
      (set entity.__scene_resizable_keys nil)
      (set entity.__scene_resizable_records nil)))

  (fn refresh-entity-bindings [self entity]
    (when entity
      (unregister-entity-movables self entity)
      (unregister-entity-resizables self entity)
      (set entity.movables (compute-entity-movables self entity))
      (set entity.resizables (compute-entity-resizables self entity))
      (register-entity-movables self entity)
      (register-entity-resizables self entity)))

  (fn register-scene-object [self entry]
    (assert-active-content-slot)
    (local entity self.entity)
    (assert entity "Scene.register-scene-object requires an attached entity")
    (when (not entity.scene-objects)
      (set entity.scene-objects []))
    (table.insert entity.scene-objects entry)
    (refresh-entity-bindings self entity)
    true)

  (fn unregister-scene-object [self owner]
    (local entity self.entity)
    (when (and entity entity.scene-objects owner)
      (for [idx (length entity.scene-objects) 1 -1]
        (local entry (. entity.scene-objects idx))
        (when (= (and entry entry.owner) owner)
          (table.remove entity.scene-objects idx))))
    (refresh-entity-bindings self entity)
    true)

  (fn remove-key-once [keys key]
    (when keys
      (var idx-to-remove nil)
      (each [idx value (ipairs keys)]
        (when (and (not idx-to-remove)
                   (= value key))
          (set idx-to-remove idx)))
      (when idx-to-remove
        (table.remove keys idx-to-remove))))

  (fn unregister-movables-for-owner [self entity owner]
    (when (and entity app.movables owner)
      (local records entity.__scene_movable_records)
      (local keys entity.__scene_movable_keys)
      (when records
        (for [idx (length records) 1 -1]
          (local record (. records idx))
          (when (and record (= record.owner owner))
            (app.movables:unregister record.key)
            (remove-key-once keys record.key)
            (table.remove records idx))))))

  (fn unregister-resizables-for-owner [self entity owner]
    (when (and entity app.resizables owner)
      (local records entity.__scene_resizable_records)
      (local keys entity.__scene_resizable_keys)
      (when records
        (for [idx (length records) 1 -1]
          (local record (. records idx))
          (when (and record (= record.owner owner))
            (app.resizables:unregister record.key)
            (remove-key-once keys record.key)
            (table.remove records idx))))))

  (fn remove-entries-for-owner [entries owner]
    (when (and entries owner)
      (for [idx (length entries) 1 -1]
        (local entry (. entries idx))
        (when (and entry (= entry.owner owner))
          (table.remove entries idx)))))

  (fn remove-panel-child [self element]
    (local entity self.entity)
    (local children (and entity entity.children))
    (local scene-children self.scene-children)
    (var removed false)
    (var removed-element nil)
    (var removed-child nil)
    (var removed-metadata nil)
    (local candidates [])
    (var current element)
    (var guard 0)
    (while (and current (< guard 16))
      (table.insert candidates current)
      (if current.__scene_wrapper
          (set current current.__scene_wrapper)
          (set current nil))
      (set guard (+ guard 1)))
    (when (and children (> (length candidates) 0))
      (each [idx metadata (ipairs children)]
        (when (and metadata (not removed))
          (var match? false)
          (each [_ candidate (ipairs candidates)]
            (when (and (not match?) (= metadata.element candidate))
              (set match? true)))
          (when match?
            (set removed true)
            (set removed-element metadata.element)
            (set removed-child (and metadata.element metadata.element.child))
            (set removed-metadata metadata)
            (entity.layout:remove-child idx)
            (table.remove children idx)))))
    (when (and removed scene-children)
      (var scene-idx nil)
      (each [idx metadata (ipairs scene-children)]
        (when (and (not scene-idx)
                   (or (= metadata removed-metadata)
                       (= metadata.element removed-element)))
          (set scene-idx idx)))
      (when scene-idx
        (table.remove scene-children scene-idx)))
      (when removed
      (when (and entity entity.layout)
        (entity.layout:mark-measure-dirty)
        (entity.layout:mark-layout-dirty))
      (when (or (= removed-element self.demo-browser)
                (= removed-child self.demo-browser))
        (set self.demo-browser nil))
      (when (and removed-element removed-element.drop)
        (removed-element:drop))
      (LayoutPhysicsBodies.remove-runtime-layout-body-for-element entity removed-element)
      (self:unregister-scene-object removed-element)
      (when (and removed-metadata removed-metadata.object removed-metadata.object.scene-on-removed)
        (removed-metadata.object:scene-on-removed self removed-element))
      (unregister-movables-for-owner self entity removed-element)
      (unregister-resizables-for-owner self entity removed-element)
      (remove-entries-for-owner entity.movables removed-element)
      (remove-entries-for-owner entity.resizables removed-element))
    removed)

  (fn find-panel-persistence [_scene element]
    (var current element)
    (var metadata nil)
    (var guard 0)
    (while (and (not metadata) current (< guard 16))
      (set metadata (find-scene-metadata-by-element self.scene-children current))
      (set current (and (not metadata) current.__scene_wrapper))
      (set guard (+ guard 1)))
    (and metadata metadata.persistence))

  (fn capture-panel-element-state [self element]
    (local metadata (find-scene-metadata-by-element self.scene-children element))
    (if (not metadata)
        nil
        (do
          (local layout-state (capture-panel-layout-state metadata))
          (if (not layout-state)
              nil
              {:layer "scene"
               :position layout-state.position
               :rotation layout-state.rotation
               :size layout-state.size}))))

  (fn register-panel-restorer [self kind restorer owner]
    (assert-active-content-slot)
    (assert (= (type kind) :string) "Scene.register-panel-restorer requires string kind")
    (assert (= (type restorer) :function) "Scene.register-panel-restorer requires function restorer")
    (set (. self.panel-restorers kind) {:restore restorer
                                        :owner owner})
    true)

  (fn unregister-panel-restorer [self kind owner]
    (assert (= (type kind) :string) "Scene.unregister-panel-restorer requires string kind")
    (local current (. self.panel-restorers kind))
    (when current
      (if (or (= owner nil)
              (= current.owner nil)
              (= current.owner owner))
          (set (. self.panel-restorers kind) nil)))
    true)

  (fn add-panel-child [self opts]
    (assert-active-content-slot)
    (local entity self.entity)
    (var builder (and opts opts.builder))
    (when (and entity builder)
      (when (and self.add-widget-as-cuboid (not (and opts opts.skip-cuboid)))
        (set builder (self:add-widget-as-cuboid builder)))
      (local builder-options {})
      (each [key value (pairs (or opts.builder-options {}))]
        (set (. builder-options key) value))
      (var element nil)
      (var close-called? false)
      (local user-on-close builder-options.on-close)
      (fn handle-close [dialog button event]
        (when (not close-called?)
          (set close-called? true)
          (when user-on-close
            (user-on-close dialog button event))
          (self:remove-panel-child (or element dialog))))
      (set builder-options.on-close handle-close)
      ;; Scene APIs now treat opts.position as layout-origin coordinates.
      (local requested-layout-position (and opts opts.position))
      (local requested-rotation (and opts opts.rotation))
      (local placement
        (if (or (not requested-layout-position)
                (not requested-rotation))
            (resolve-camera-placement self)
            nil))
      (local resolved-rotation
        (or requested-rotation
            (and placement placement.rotation)))
      (local parent-layout entity.layout)
      (local parent-position (or (and parent-layout parent-layout.position) (glm.vec3 0 0 0)))
      (local parent-rotation (or (and parent-layout parent-layout.rotation) (glm.quat 1 0 0 0)))
      (local parent-inverse (parent-rotation:inverse))
      (local local-rotation (* parent-inverse resolved-rotation))
      (set element (builder self.build-context builder-options))
      (local metadata {:flex (or opts.flex 0)
                       :element element
                       :object (and opts opts.object)
                       :position (glm.vec3 0 0 0)
                       :rotation local-rotation
                       :terrain-binding
                       (if (and opts opts.object)
                           (clone-terrain-binding (and opts opts.terrain-binding))
                           (or (clone-terrain-binding (and opts opts.terrain-binding))
                               {:enabled? true}))
                       :persistence (and opts.persistence
                                         (clone-table opts.persistence))})
      (local children (or entity.children []))
      (when (not entity.children)
        (set entity.children children))
      (table.insert children metadata)
      (when (not entity.scene-children)
        (set entity.scene-children []))
      (when (not self.scene-children)
        (set self.scene-children entity.scene-children))
      (table.insert self.scene-children metadata)
      (when (and entity.layout element element.layout)
        (entity.layout:add-child element.layout)
        (element.layout:measurer)
        (set element.layout.rotation resolved-rotation)
        (local measure (or element.layout.measure (glm.vec3 0 0 0)))
        (set element.layout.size measure)
        (local layout-position
          (if requested-layout-position
              requested-layout-position
              (layout-origin-from-center placement.center resolved-rotation measure)))
        (set element.layout.position layout-position)
        (set metadata.position
             (parent-inverse:rotate (- layout-position parent-position)))
        (element.layout:layouter))
      (when (and self.entity
                 element
                 element.layout
                 (not (and opts opts.skip-physics)))
        (LayoutPhysicsBodies.add-runtime-layout-body self.entity {:element element
                                                                  :metadata metadata
                                                                  :body-options (merge-panel-body-options opts)}))
      (when (and entity entity.layout element element.layout)
        (entity.layout:mark-measure-dirty)
        (entity.layout:mark-layout-dirty)
        (set metadata.transform-applied? false))
      (refresh-entity-bindings self entity)
      element))

  (fn add-object [self object opts]
    (assert-active-content-slot)
    (assert object "Scene.add-object requires an object")
    (local object-config
      (if object.scene-object-options
          (object:scene-object-options)
          {}))
    (local options (or opts {}))
    (local element
      (add-panel-child self {:builder (or object-config.builder object)
                             :object object
                             :builder-options object-config.builder-options
                             :terrain-binding (resolve-terrain-binding options object-config)
                             :skip-cuboid (if (not (= options.skip-cuboid nil))
                                              options.skip-cuboid
                                              object-config.skip-cuboid)
                             :skip-physics (if (not (= options.skip-physics nil))
                                              options.skip-physics
                                              object-config.skip-physics)
                             :flex (or options.flex object-config.flex 0)
                             :position (or options.position object-config.position)
                             :rotation (or options.rotation object-config.rotation)
                             :persistence (or object-config.persistence options.persistence)}))
    (when (and element object.scene-on-added)
      (object:scene-on-added self element))
    element)

  (fn add-demo-entry [self entry]
    (assert-active-content-slot)
    (when (and entry entry.builder)
      (assert entry.persistence
              (.. "Scene.add-demo-entry requires :persistence for demo entry key "
                  (tostring entry.key)))
      (add-panel-child self {:builder entry.builder
                             :flex (or entry.flex 0)
                             :persistence entry.persistence})))

  (fn add-light-ball [self opts]
    (assert-active-content-slot)
    (local options (or opts {}))
    (local light-ball-options (clone-table options))
    (set light-ball-options.position nil)
    (set light-ball-options.rotation nil)
    (local LightBall (require :light-ball))
    (self:add-object
      (LightBall.make light-ball-options)
      {:position options.position
       :rotation options.rotation}))

  (fn add-physics-body [self opts]
    (assert-active-content-slot)
    (local options (or opts {}))
    (local size (or options.size (glm.vec3 4 4 4)))
    (local placement (resolve-camera-placement self))
    (local stack-index self.physics-body-count)
    (local stacked-center
      (+ placement.center
         (glm.vec3 0 (+ 6 (* stack-index 4)) 0)))
    (set self.physics-body-count (+ stack-index 1))
    (local builder (Sized {:size size
                           :child (DemoPhysicsBodies.new-cuboid)}))
    (local spawn-rotation (or options.rotation placement.rotation))
    (local spawn-layout-position
      (or options.position
          (layout-origin-from-center stacked-center spawn-rotation size)))
    (local element (add-panel-child self {:builder builder
                                          :skip-cuboid true
                                          :skip-physics false
                                          :position spawn-layout-position
                                          :rotation options.rotation
                                          :persistence {:kind "physics-cuboid"
                                                        :size (vec3->array size)}}))
    (when element
      (self:sync-physics-bodies))
    element)

  (fn add-graph-node-cube [self opts]
    (assert-active-content-slot)
    (local options (or opts {}))
    (local key (tostring (or options.node-key (and options.node options.node.key) "")))
    (assert (> (string.len key) 0)
            "Scene.add-graph-node-cube requires :node or :node-key")
    (assert (or self.graph-map app.graph-map)
            "Scene.add-graph-node-cube requires a graph-map on the scene or app")
    (local graph (or self.graph-map app.graph-map))
    (when options.restore?
        (when (and options.graph-map-id graph.id
                   (not= options.graph-map-id graph.id))
            (lua "return nil"))
        (local target-map-id (or options.graph-map-id graph.id))
        (each [_ metadata (ipairs (or self.scene-children []))]
            (local persistence (and metadata metadata.persistence))
            (when (and persistence
                        (= persistence.kind "graph-node-cube")
                        (= persistence.node-key key)
                        (= persistence.graph-map-id target-map-id))
                (local element metadata.element)
                (local layout (and element element.layout))
                (local parent-layout (and self.entity self.entity.layout))
                (local parent-position (or (and parent-layout parent-layout.position) (glm.vec3 0 0 0)))
                (local parent-rotation (or (and parent-layout parent-layout.rotation) (glm.quat 1 0 0 0)))
                (local parent-inverse (parent-rotation:inverse))
                (var repositioned? false)
                (when options.position
                    (set metadata.position
                         (parent-inverse:rotate (- options.position parent-position)))
                    (when layout
                        (set layout.position options.position)))
                (when options.rotation
                    (set metadata.rotation (* parent-inverse options.rotation))
                    (when layout
                        (set layout.rotation options.rotation)))
                (when options.size
                    (set persistence.size (vec3->array options.size))
                    (set metadata.size options.size)
                    (when layout
                        (set layout.size options.size)
                        (set layout.measure options.size)))
                (when options.label
                    (set persistence.label options.label))
                (when (and layout layout.layouter)
                    (layout:layouter))
                (when layout
                    (set repositioned?
                         (LayoutPhysicsBodies.reposition-element self.entity
                                                                 element
                                                                 (or options.position layout.position)
                                                                 (or options.rotation layout.rotation))))
                (when (not repositioned?)
                    (self:sync-physics-bodies))
                (lua "return element"))))
    (local node (or options.node
                     (and graph graph.lookup (graph:lookup key))
                     (if options.restore?
                        nil
                        (and graph graph.load-by-key (graph:load-by-key key)))))
    (when (not node)
        (if options.restore?
            (lua "return nil")
            (error (.. "Scene.add-graph-node-cube could not resolve node for key: " key))))
    (local label (or options.label (and node node.label) key))
    (local size (or options.size (glm.vec3 4 4 4)))
    (local placement (resolve-camera-placement self))
    (local stack-index self.physics-body-count)
    (local stacked-center
      (+ placement.center
         (glm.vec3 0 (+ 6 (* stack-index 4)) 0)))
    (set self.physics-body-count (+ stack-index 1))
    (fn on-graph-action [_cube _button _event payload]
      (local graph (or self.graph-map app.graph-map))
      (local node-key (or (and payload payload.node-key) key))
      (local existing (and node-key (graph:lookup node-key)))
      (when (not existing)
        (local loaded
          (if (and node-key graph.load-by-key)
              (graph:load-by-key node-key)
              nil))
        (when (and (not loaded) node)
          (graph:add-node
            node
            {:position (to-graph-position
                        (and payload payload.cube-position))}))))
    (local cube-builder
      (Sized {:size size
              :child (GraphNodeCube {:node node
                                     :node-key key
                                     :label label
                                     :on-graph on-graph-action})}))
    (local spawn-rotation (or options.rotation placement.rotation))
    (local spawn-layout-position
      (or options.position
          (layout-origin-from-center stacked-center spawn-rotation size)))
    (local element
      (add-panel-child self {:builder cube-builder
                             :skip-cuboid true
                             :skip-physics false
                             :position spawn-layout-position
                             :rotation options.rotation
                             :persistence {:kind "graph-node-cube"
                                           :graph-map-id graph.id
                                           :node-key key
                                           :label label
                                           :size (vec3->array size)}}))
    (when element
      (self:sync-physics-bodies))
    element)

  (fn add-demo-browser [self opts]
    (assert-active-content-slot)
    (if self.demo-browser
        self.demo-browser
        (let [options (or opts {})
              browser
              (DemoDialogs.new-browser-dialog
                {:on-open (fn [entry]
                            (self:add-demo-entry entry))})
              element (add-panel-child self {:builder browser
                                             :position options.position
                                             :rotation options.rotation
                                             :persistence {:kind "demo-browser"}})]
          (when element
            (set self.demo-browser element))
          element)))

  (fn unregister-entity [self entity]
    (unregister-entity-movables self entity)
    (unregister-entity-resizables self entity))

  (fn sync-physics-bodies [self]
    (LayoutPhysicsBodies.sync self.entity))

  (fn sync-scene-objects [self]
    (local entity self.entity)
    (when (and entity entity.scene-objects)
      (each [_ entry (ipairs entity.scene-objects)]
        (when (and entry entry.ensure-body)
          (entry:ensure-body entity))
        (when (and entry entry.sync)
          (entry:sync entity)))))

  (fn replace-terrain-record [self terrain-id record]
    (assert-active-content-slot)
    (local runtime-entry (require-terrain-runtime-entry self terrain-id))
    (local entity runtime-entry.entity)
    (local terrain-entry runtime-entry.terrain-entry)
    (local current-element runtime-entry.current-element)
    (local child-index runtime-entry.child-index)
    (TerrainIssueLog.info
      (string.format
        "[scene] replace-terrain-record terrain=%s incoming-kind=%s incoming-id=%s"
        terrain-id
        (tostring (and record record.kind))
        (tostring (and record record.id))))
    (local built-entry (SceneWorldState.build-terrain-entries [record]))
    (local terrain-spec (. built-entry 1))
    (assert terrain-spec (.. "Scene.replace-terrain-record could not build terrain " terrain-id))
    (local terrain-builder terrain-spec.builder)
    (local new-element (terrain-builder self.build-context))
    (assert (and new-element new-element.layout)
            (.. "Scene.replace-terrain-record built invalid terrain " terrain-id))
    (local current-selection-target
      (if current-element.get-selection-target
          (current-element:get-selection-target)
          nil))
    (local new-terrain-metadata {:element new-element
                                 :record terrain-spec.record})
    (local transform
      (terrain-child-transform terrain-spec.record
                               terrain-spec.position
                               terrain-spec.rotation
                               new-element))
    (local new-child-metadata {:element new-element
                               :position transform.position
                               :rotation transform.rotation
                               :transform-applied? false})
    (set (. self.scene-terrains terrain-entry.index) new-terrain-metadata)
    (entity.layout:remove-child child-index)
    (table.remove entity.children child-index)
    (table.insert entity.children child-index new-child-metadata)
    (insert-layout-child entity.layout child-index new-element.layout)
    (current-element:drop)
    (when (and current-selection-target new-element.set-selection-target)
      (new-element:set-selection-target current-selection-target))
    (when entity.layout
      (entity.layout:mark-measure-dirty)
      (entity.layout:mark-layout-dirty))
    (self:sync-physics-bodies)
    (notify-terrains-changed self)
    true)

  (fn set-terrain-selection-target [self terrain-id target]
    (local runtime-entry (require-terrain-runtime-entry self terrain-id))
    (local element runtime-entry.current-element)
    (require-terrain-selection-method element terrain-id :set-selection-target)
    (assert (element:set-selection-target target)
            (.. "Scene failed to set terrain selection for " terrain-id))
    true)

  (fn clear-terrain-selection-target [self terrain-id]
    (local runtime-entry (require-terrain-runtime-entry self terrain-id))
    (local element runtime-entry.current-element)
    (require-terrain-selection-method element terrain-id :clear-selection-target)
    (assert (element:clear-selection-target)
            (.. "Scene failed to clear terrain selection for " terrain-id))
    true)

  (fn get-terrain-selection-target [self terrain-id]
    (local runtime-entry (require-terrain-runtime-entry self terrain-id))
    (local element runtime-entry.current-element)
    (require-terrain-selection-method element terrain-id :get-selection-target)
    (element:get-selection-target))

  (fn add-terrain-record [self record]
    (assert-active-content-slot)
    (local entity self.entity)
    (assert entity "Scene.add-terrain-record requires an attached entity")
    (local built-entry (SceneWorldState.build-terrain-entries [record]))
    (local terrain-spec (. built-entry 1))
    (assert terrain-spec
            (.. "Scene.add-terrain-record could not build terrain "
                (or (and record record.id) "?")))
    (local terrain-builder terrain-spec.builder)
    (local new-element (terrain-builder self.build-context))
    (assert (and new-element new-element.layout)
            (.. "Scene.add-terrain-record built invalid terrain "
                (or (and record record.id) "?")))
    (local new-terrain-metadata {:element new-element
                                 :record terrain-spec.record})
    (local transform
      (terrain-child-transform terrain-spec.record
                               terrain-spec.position
                               terrain-spec.rotation
                               new-element))
    (local new-child-metadata {:element new-element
                               :position transform.position
                               :rotation transform.rotation
                               :transform-applied? false})
    (when (not entity.scene-terrains)
      (set entity.scene-terrains []))
    (when (not self.scene-terrains)
      (set self.scene-terrains entity.scene-terrains))
    (when (not entity.children)
      (set entity.children []))
    (table.insert self.scene-terrains new-terrain-metadata)
    (table.insert entity.children new-child-metadata)
    (insert-layout-child entity.layout (length entity.children) new-element.layout)
    (when entity.layout
      (entity.layout:mark-measure-dirty)
      (entity.layout:mark-layout-dirty))
    (self:sync-physics-bodies)
    (notify-terrains-changed self)
    true)

  (fn remove-terrain [self terrain-id]
    (assert-active-content-slot)
    (local runtime-entry (require-terrain-runtime-entry self terrain-id))
    (local entity runtime-entry.entity)
    (local terrain-entry runtime-entry.terrain-entry)
    (local current-element runtime-entry.current-element)
    (local child-index runtime-entry.child-index)
    (table.remove self.scene-terrains terrain-entry.index)
    (entity.layout:remove-child child-index)
    (table.remove entity.children child-index)
    (current-element:drop)
    (when entity.layout
      (entity.layout:mark-measure-dirty)
      (entity.layout:mark-layout-dirty))
    (self:sync-physics-bodies)
    (notify-terrains-changed self)
    true)

  (fn attach-entity [self entity]
    (log-terrain-diagnostic self :info
                            "attach-entity:begin"
                            (string.format "incoming-entity=%s"
                                           (tostring (not (= entity nil)))))
    (when self.entity
      (self:unregister-entity self.entity)
      (self.entity:drop))
    (set self.entity entity)
    (set self.scene-children nil)
    (set self.scene-terrains nil)
    (set self.demo-browser nil)
    (set self.physics-body-count 0)
    (when entity
      (set entity.__scene_base_movables (copy-movables entity.movables))
      (when (not entity.scene-children)
        (set entity.scene-children []))
      (when (not entity.scene-terrains)
        (set entity.scene-terrains []))
      (when (not entity.scene-objects)
        (set entity.scene-objects []))
      (when (not entity.children)
        (set entity.children []))
      (set self.scene-children entity.scene-children)
      (set self.scene-terrains entity.scene-terrains)
      (entity.layout:set-root self.layout-root)
      (local position self.default-position)
      (local resolved-position (glm.vec3 position.x position.y position.z))
      (entity.layout:set-position resolved-position)
      (entity.layout:set-rotation self.default-rotation)
      (entity.layout:mark-measure-dirty)
      (set self.reference-point resolved-position)
      (LayoutPhysicsBodies.attach entity entity.__physics_bodies_spec)
      (set entity.movables (compute-entity-movables self entity))
      (set entity.resizables (compute-entity-resizables self entity))
      (register-entity-movables self entity)
      (register-entity-resizables self entity)
      (self:sync-physics-bodies))
    (log-terrain-diagnostic self :info "attach-entity:end")
    (notify-terrains-changed self))

  (fn build [self builder]
    (set self.builder builder)
    (if builder
      (do
        (apply-active-theme self.build-context)
        (self:attach-entity (builder self.build-context)))
      (self:attach-entity nil)))

(fn build-default [self opts]
  (assert-active-content-slot)
  (log-terrain-diagnostic self :info
                          "build-default"
                          (string.format "requested-terrains=%s"
                                         (count-label (and opts opts.terrains))))
  (self:build (make-default-builder opts)))

  (fn update [self]
    (self:sync-physics-bodies)
    (self:sync-scene-objects)
    (self.layout-root:update)
    (when (and self.active-activity-slot
               self.active-activity-slot.layout-root)
      (self.active-activity-slot.layout-root:update))
    (sync-terrain-runtime-state self))

  (fn drop [self]
  (log-terrain-diagnostic self :info "drop:begin")
  ;; Drop all retained activity slots first
  (local slot-ids [])
  (each [id _ (pairs self.activity-slots)]
    (table.insert slot-ids id))
  (each [_ id (ipairs slot-ids)]
    (drop-activity-slot self id))
  (when self.entity
    (self:unregister-entity self.entity)
    (self.entity:drop)
    (set self.entity nil)
    (set self.scene-children nil)
    (set self.scene-terrains nil))
  (set self.demo-browser nil)
  (set self.queued-cube-panels [])
  (set self.physics-body-count 0)
  (when (and self.focus-manager self.focus-scope)
    (self.focus-manager:detach self.focus-scope)
    (set self.focus-scope nil))
  (log-terrain-diagnostic self :info "drop:end"))

(fn reset-projection [self]
  (assert (and app app.create-default-projection)
          "Scene.reset-projection requires app.create-default-projection")
  (set self.projection (app.create-default-projection self.viewport))
  (set self.projection-version (+ (or self.projection-version 0) 1)))

(fn set-camera [self camera]
  (set self.camera camera))

(fn get-view-matrix [self]
  (assert self.camera "Scene.get-view-matrix requires self.camera")
  (self.camera:get-view-matrix))

(fn get-lighting-view-state [self]
  (assert self.camera "Scene.get-lighting-view-state requires self.camera")
  (assert self.camera.position "Scene.get-lighting-view-state requires self.camera.position")
  (LightingViewState.perspective self.camera.position))

(fn get-triangle-vector [self]
  (. (active-render-context) :triangle-vector))

(fn get-triangle-batches [self]
  (local render-ctx (active-render-context))
  (and render-ctx
       render-ctx.get-triangle-batches
       (render-ctx:get-triangle-batches)))

(fn get-line-vector [self]
  (. (active-render-context) :line-vector))

(fn get-point-vector [self]
  (. (active-render-context) :point-vector))

(fn get-line-strips [self]
  (. (active-render-context) :line-strips))

(fn get-image-batches [self]
  (. (active-render-context) :image-batches))

(fn get-quad-draw-list [self]
  (local render-ctx (active-render-context))
  (and render-ctx
       render-ctx.get-quad-draw-list
       (render-ctx:get-quad-draw-list)))

(fn get-text-ssbo-draw-list [self]
  (local render-ctx (active-render-context))
  (and render-ctx
       render-ctx.get-text-ssbo-draw-list
       (render-ctx:get-text-ssbo-draw-list)))

(fn get-mesh-batches [self]
  (local render-ctx (active-render-context))
  (and render-ctx
       render-ctx.get-mesh-batches
       (render-ctx:get-mesh-batches)))

(fn get-instanced-color-mesh-batches [self]
  (local render-ctx (active-render-context))
  (and render-ctx
       render-ctx.get-instanced-color-mesh-batches
       (render-ctx:get-instanced-color-mesh-batches)))

(fn get-reference-point [self]
  self.reference-point)

(fn screen-pos-ray [self pos opts]
  (local options (or opts {}))
  (local viewport (viewport-utils.to-table (or options.viewport self.viewport app.viewport)))
  (local view (or options.view (self:get-view-matrix)))
  (local projection (or options.projection self.projection))
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
      (error (.. "Scene.screen-pos-ray produced non-finite " label))))
  (assert view "Scene.screen-pos-ray requires a view matrix")
  (assert projection "Scene.screen-pos-ray requires a projection matrix")
  (local sample-pos
    (or (viewport-utils.input-pos->viewport-pos pos viewport app.engine)
        {:x (+ viewport.x (/ viewport.width 2))
         :y (+ viewport.y (/ viewport.height 2))}))
  (local px (or sample-pos.x viewport.x))
  (local py (or sample-pos.y viewport.y))
  (local inverted-y (- (+ viewport.height viewport.y) py))
  (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
  (local near (glm.unproject (glm.vec3 px inverted-y 0.0) view projection viewport-vec))
  (local far (glm.unproject (glm.vec3 px inverted-y 1.0) view projection viewport-vec))
  (local direction (glm.normalize (- far near)))
  (assert-finite-vec3 near "near")
  (assert-finite-vec3 far "far")
  (assert-finite-vec3 direction "direction")
  {:origin near :direction direction})

(fn on-viewport-changed [self viewport]
  (set self.viewport (viewport-utils.to-table viewport))
  nil)

(fn raycast-terrain [self ray]
  (var best nil)
  (each [_ metadata (ipairs (or self.scene-terrains []))]
    (local record (and metadata metadata.record))
    (local query-record (terrain-layout-record metadata))
    (local hit (and query-record (TerrainQuery.raycast-record query-record ray)))
    (when (and hit (or (not best) (< hit.distance best.distance)))
      (set best {:terrain-record record
                 :query-record query-record
                 :terrain-id (and record record.id)
                 :terrain-kind (and record record.kind)
                 :distance hit.distance
                 :world-point hit.world-point
                 :local-point hit.local-point
                 :sample hit.sample
                 :target hit.target})))
  best)

(fn terrain-surface-under-point [self world-point]
  (var best nil)
  (each [_ metadata (ipairs (or self.scene-terrains []))]
    (local record (and metadata metadata.record))
    (local query-record (terrain-layout-record metadata))
    (local info (and query-record
                     world-point
                     (TerrainQuery.surface-info-at-world-point query-record world-point)))
    (when info
      (local world-surface-y (and info.world-point info.world-point.y))
      (when (and world-surface-y
                 (or (not best)
                     (> world-surface-y (. best :world-surface-y))))
        (set best {:terrain-record record
                   :query-record query-record
                   :terrain-id (and record record.id)
                   :terrain-kind (and record record.kind)
                   :world-point info.world-point
                   :world-surface-y world-surface-y
                   :local-point info.local-point
                   :local-surface-y info.local-surface-y
                   :cell-x info.cell-x
                   :cell-z info.cell-z
                   :u info.u
                   :v info.v
                   :h00 info.h00
                   :h01 info.h01
                   :h10 info.h10
                   :h11 info.h11}))))
  best)

(fn screen-pos-terrain-hit [self pos opts]
  (self:raycast-terrain (self:screen-pos-ray pos opts)))

(fn screen-pos-terrain-domain-hit [self pos opts]
  (local ray (self:screen-pos-ray pos opts))
  (var best nil)
  (each [_ metadata (ipairs (or self.scene-terrains []))]
    (local record (and metadata metadata.record))
    (local query-record (terrain-layout-record metadata))
    (local hit (and query-record (TerrainQuery.domain-hit-record query-record ray)))
    (when (and hit (or (not best) (< hit.distance best.distance)))
      (set best {:terrain-record record
                 :query-record query-record
                 :terrain-id (and record record.id)
                 :terrain-kind (and record record.kind)
                 :distance hit.distance
                 :world-point hit.world-point
                 :local-point hit.local-point
                 :sample hit.sample
                 :target hit.target})))
  best)

(fn screen-rect-terrain-target [self terrain-id start-pos end-pos opts]
  (local terrain-entry (find-terrain-entry self.scene-terrains terrain-id))
  (if (not terrain-entry)
      nil
      (do
        (local metadata terrain-entry.metadata)
        (local record (and metadata metadata.record))
        (local query-record (and metadata (terrain-layout-record metadata)))
        (local target
          (and query-record
               (TerrainQuery.screen-rect-target query-record start-pos end-pos opts)))
        (and target
             {:terrain-record record
              :terrain-id (and record record.id)
              :terrain-kind (and record record.kind)
              :target target}))))

  (fn capture-state [self]
    (local panels [])
    (when (= self.scene-terrains nil)
      (log-terrain-diagnostic self :warn "capture-state:missing-scene-terrains"))
    (local terrains
      (if (= self.scene-terrains nil)
          nil
          (SceneWorldState.capture-terrains self.scene-terrains)))
    (assert (and app app.lights app.lights.get-state)
            "Scene.capture-state requires app.lights.get-state")
    (local lights (app.lights:get-state))
    (local skybox
      (if (and app app.renderers app.renderers.skybox app.renderers.skybox.get-state)
          (self:get-skybox-state)
          nil))
    (local background
      (if (and app app.renderers app.renderers.get-background-state)
          (self:get-background-state)
          nil))
    (each [_ metadata (ipairs (or self.scene-children []))]
      (local persistence (and metadata metadata.persistence))
      (when persistence
        (local kind (and persistence persistence.kind))
        (assert (= (type kind) :string)
                "Scene.capture-state panel persistence requires string :kind")
        (local module-name (and persistence persistence.restorer-module))
        (when (not (= module-name nil))
          (assert (= (type module-name) :string)
                  (.. "Scene.capture-state panel persistence for kind "
                      kind
                      " requires string :restorer-module")))
        (local registered (and (. self.panel-restorers kind)
                               (. (. self.panel-restorers kind) :restore)))
        (local built-in? (. built-in-scene-kinds kind))
        (assert (or built-in? registered (= (type module-name) :string))
                (.. "Scene.capture-state panel kind has no restore strategy: "
                    kind
                    " (register restorer or set :restorer-module)"))
        (local layout-state (capture-panel-layout-state metadata))
        (when layout-state
          (local record
            (if (and metadata.element metadata.element.capture-persistence)
                (clone-table (metadata.element:capture-persistence))
                (clone-table persistence)))
          (set record.position layout-state.position)
          (set record.rotation layout-state.rotation)
          (set record.size (or layout-state.size record.size))
          (table.insert panels record))))
    ;; Preserve queued cube panels from mismatched maps so they survive saves.
    (each [_ panel (ipairs self.queued-cube-panels)]
        (table.insert panels (clone-table panel)))
    (local captured {:panels panels
                     :terrains terrains
                     :lights lights})
    (when skybox
      (set captured.skybox skybox))
    (when background
      (set captured.background background))
    captured)

  (fn set-light-state [self state]
    (assert (and app app.lights app.lights.set-state)
            "Scene.set-light-state requires app.lights.set-state")
    (assert state "Scene.set-light-state requires light state")
    (app.lights:set-state state))

  (fn get-light-state [self]
    (assert (and app app.lights app.lights.get-state)
            "Scene.get-light-state requires app.lights.get-state")
    (app.lights:get-state))

  (fn set-skybox-state [self state]
    (assert (and app app.renderers app.renderers.skybox app.renderers.skybox.set-state)
            "Scene.set-skybox-state requires app.renderers.skybox.set-state")
    (app.renderers.skybox:set-state state))

  (fn get-skybox-state [self]
    (assert (and app app.renderers app.renderers.skybox app.renderers.skybox.get-state)
            "Scene.get-skybox-state requires app.renderers.skybox.get-state")
    (SkyboxState.normalize-resolved-state
      (app.renderers.skybox:get-state)
      "Scene.get-skybox-state"))

  (fn set-background-state [self state]
    (assert (and app app.renderers app.renderers.set-background-state)
            "Scene.set-background-state requires app.renderers.set-background-state")
    (app.renderers:set-background-state state))

  (fn get-background-state [self]
    (assert (and app app.renderers app.renderers.get-background-state)
            "Scene.get-background-state requires app.renderers.get-background-state")
    (BackgroundState.normalize-complete-state
      (app.renderers:get-background-state)
      "Scene.get-background-state"))

  (fn resolve-panel-restorer-strategy [self panel]
    (local kind panel.kind)
    (local registered-record (. self.panel-restorers kind))
    (local registered (and registered-record registered-record.restore))
    (if registered
        {:missing? false
         :restore registered}
        (do
          (local module-name panel.restorer-module)
          (if (not (= (type module-name) :string))
              {:missing? true
               :message (.. "Scene.restore-state panel kind "
                            kind
                            " requires string :restorer-module or registered restorer")}
              (do
                (local (ok module-or-error) (pcall require module-name))
                (assert ok
                        (.. "Scene.restore-state failed requiring panel restorer module "
                            module-name
                            ": "
                            (tostring module-or-error)))
                (local module module-or-error)
                (local restore (and module module.restore))
                (assert (= (type restore) :function)
                        (.. "Scene.restore-state module "
                            module-name
                            " must export function :restore"))
                {:missing? false
                 :restore (fn [payload]
                            (restore {:scene self
                                      :target self
                                      :panel payload}))})))))

  (fn restore-panel-with-fallback [self panel panel-idx]
    (local kind panel.kind)
    (local strategy (resolve-panel-restorer-strategy self panel))
    (if strategy.missing?
        (do
          (logging.warn (string.format
                          "[scene] skipping restored panel at index %d (kind=%s): %s"
                          panel-idx
                          (tostring kind)
                          (tostring strategy.message)))
          false)
        (do
          (strategy.restore panel)
          true)))

  (fn restore-panel-state [self panel panel-idx]
    (assert (= (type panel) :table) "Scene.restore-panel-state panel must be table")
    (local kind panel.kind)
    (local (ok parsed-position) (pcall array->vec3 panel.position))
    (local restored-position
      (if (and ok (safe-vec3? parsed-position))
          parsed-position
          nil))
    (local (ok-size parsed-size) (pcall array->vec3 panel.size))
    (local restored-size
      (if (and ok-size (safe-vec3? parsed-size))
          parsed-size
          (glm.vec3 4 4 4)))
    (when (and panel.position (not restored-position))
      (logging.warn (string.format
                      "[scene] dropping invalid restored panel position at index %d (kind=%s)"
                      panel-idx
                      (tostring kind))))
    (when (and panel.size (not (and ok-size (safe-vec3? parsed-size))))
      (logging.warn (string.format
                      "[scene] replacing invalid restored panel size at index %d (kind=%s)"
                      panel-idx
                      (tostring kind))))
     (if (= kind "graph-node-cube")
         (do
              (when (and panel.graph-map-id self.graph-map self.graph-map.id
                         (not= panel.graph-map-id self.graph-map.id))
                  ;; Put in queued scene panels so it survives save/load cycles.
                  (table.insert self.queued-cube-panels (clone-table panel))
                  (lua "return true"))
             ;; Remove queued entry if one exists (dedup when map matches).
             (for [i (length self.queued-cube-panels) 1 -1]
                 (when (and (= (. self.queued-cube-panels i :kind) "graph-node-cube")
                            (= (. self.queued-cube-panels i :node-key) panel.node-key)
                            (= (. self.queued-cube-panels i :graph-map-id) panel.graph-map-id))
                     (table.remove self.queued-cube-panels i)))
             (self:add-graph-node-cube {:node-key panel.node-key
                                        :label panel.label
                                        :size restored-size
                                        :position restored-position
                                        :rotation (array->quat panel.rotation)
                                        :graph-map-id panel.graph-map-id
                                        :restore? true}))
        (= kind "physics-cuboid")
        (self:add-physics-body {:size restored-size
                                :position restored-position
                                :rotation (array->quat panel.rotation)})
        (= kind "demo-browser")
        (self:add-demo-browser {:position restored-position
                                :rotation (array->quat panel.rotation)})
        (restore-panel-with-fallback self panel panel-idx)))

  (fn restore-state [self state]
    (local payload (or state {}))
    (assert payload.lights "Scene.restore-state requires :lights")
    (self:set-light-state payload.lights)
    (when payload.skybox
      (self:set-skybox-state payload.skybox))
    (when payload.background
      (self:set-background-state payload.background))
    (local panels (or payload.panels []))
    (assert (= (type panels) :table) "Scene.restore-state requires :panels table")
    (each [panel-idx panel (ipairs panels)]
      (assert (= (type panel) :table) "Scene.restore-state panel entries must be tables")
      (restore-panel-state self panel panel-idx))
    (self:sync-scene-objects)
    true)

(set self.unregister-entity unregister-entity)
(set self.attach-entity attach-entity)
(set self.build build)
(set self.build-default build-default)
(set self.update update)
(set self.drop drop)
(set self.sync-physics-bodies sync-physics-bodies)
(set self.sync-scene-objects sync-scene-objects)
(set self.ensure-activity-slot ensure-activity-slot)
(set self.activity-slot activity-slot)
(set self.activate-activity-slot activate-activity-slot)
(set self.deactivate-activity-slot deactivate-activity-slot)
(set self.drop-activity-slot drop-activity-slot)
(set self.capture-activity-slot-state capture-activity-slot-state)
(set self.restore-activity-slot-state restore-activity-slot-state)
(set self.add-light-ball add-light-ball)
(set self.replace-terrain-record replace-terrain-record)
(set self.add-terrain-record add-terrain-record)
(set self.remove-terrain remove-terrain)
(set self.set-terrain-selection-target set-terrain-selection-target)
(set self.clear-terrain-selection-target clear-terrain-selection-target)
(set self.get-terrain-selection-target get-terrain-selection-target)
(set self.reset-projection reset-projection)
(set self.set-camera set-camera)
(set self.get-view-matrix get-view-matrix)
(set self.get-lighting-view-state get-lighting-view-state)
(set self.get-triangle-vector get-triangle-vector)
(set self.get-triangle-batches get-triangle-batches)
(set self.get-line-vector get-line-vector)
(set self.get-point-vector get-point-vector)
(set self.get-line-strips get-line-strips)
(set self.get-image-batches get-image-batches)
(set self.get-quad-draw-list get-quad-draw-list)
(set self.get-text-ssbo-draw-list get-text-ssbo-draw-list)
(set self.get-mesh-batches get-mesh-batches)
(set self.get-instanced-color-mesh-batches get-instanced-color-mesh-batches)
(set self.get-reference-point get-reference-point)
(set self.screen-pos-ray screen-pos-ray)
(set self.raycast-terrain raycast-terrain)
(set self.terrain-surface-under-point terrain-surface-under-point)
(set self.screen-pos-terrain-hit screen-pos-terrain-hit)
(set self.screen-pos-terrain-domain-hit screen-pos-terrain-domain-hit)
(set self.screen-rect-terrain-target screen-rect-terrain-target)
(set self.on-viewport-changed on-viewport-changed)
(set self.capture-state capture-state)
(set self.restore-state restore-state)
(set self.restore-panel-state restore-panel-state)
(set self.set-light-state set-light-state)
(set self.get-light-state get-light-state)
(set self.set-skybox-state set-skybox-state)
(set self.get-skybox-state get-skybox-state)
(set self.set-background-state set-background-state)
(set self.get-background-state get-background-state)
(set self.capture-panel-element-state capture-panel-element-state)
(set self.register-panel-restorer register-panel-restorer)
(set self.unregister-panel-restorer unregister-panel-restorer)
(set self.register-scene-object register-scene-object)
(set self.unregister-scene-object unregister-scene-object)
(set self.add-widget-as-cuboid add-widget-as-cuboid)
(set self.add-object add-object)
(set self.add-panel-child add-panel-child)
(set self.remove-panel-child remove-panel-child)
(set self.find-panel-persistence find-panel-persistence)
(set self.add-demo-entry add-demo-entry)
(set self.add-demo-browser add-demo-browser)
(set self.add-physics-body add-physics-body)
(set self.add-graph-node-cube add-graph-node-cube)
(set self.set-graph (fn [_self graph] (set self.graph graph)))
(set self.set-graph-map (fn [_self graph-map]
                            (when (and self.graph-map graph-map
                                       (not= self.graph-map.id (and graph-map graph-map.id)))
                                (local to-remove [])
                                (each [_ metadata (ipairs (or self.scene-children []))]
                                    (when (and metadata metadata.persistence
                                               (= metadata.persistence.kind "graph-node-cube"))
                                        (table.insert to-remove metadata.element)))
                                (each [_ element (ipairs to-remove)]
                                    (self:remove-panel-child element)))
                            (set self.graph-map graph-map)
                            (when graph-map
                              (set self.graph graph-map.graph))
                            ;; Restore queued cube panels that match the new (now-active) map.
                            (when (and self.graph-map self.graph-map.id
                                       (> (length self.queued-cube-panels) 0))
                                (local remaining [])
                                (each [_ panel (ipairs self.queued-cube-panels)]
                                    (if (and (= panel.graph-map-id self.graph-map.id)
                                             (= panel.kind "graph-node-cube"))
                                        (let [(ok-pos pos) (pcall array->vec3 panel.position)
                                              (ok-sz sz) (pcall array->vec3 panel.size)
                                              (ok-rot rot) (pcall array->quat panel.rotation)
                                              restored-position (if (and ok-pos (safe-vec3? pos)) pos nil)
                                              restored-size (if (and ok-sz (safe-vec3? sz)) sz (glm.vec3 4 4 4))
                                              restored-rotation (if ok-rot rot nil)
                                              element (self:add-graph-node-cube
                                                        {:node-key panel.node-key
                                                         :label panel.label
                                                         :size restored-size
                                                         :position restored-position
                                                         :rotation (or restored-rotation (glm.quat 1 0 0 0))
                                                         :graph-map-id panel.graph-map-id
                                                         :restore? true})]
                                            (if element
                                                nil
                                                (table.insert remaining (clone-table panel))))
                                        (table.insert remaining (clone-table panel))))
                                (set self.queued-cube-panels remaining))))
(self:reset-projection)
self)

Scene
