(local glm (require :glm))
(local {: LayoutRoot} (require :layout))
(local DemoDialogs (require :demo-dialogs))
(local DemoPhysicsBodies (require :demo-physics-bodies))
(local LayoutPhysicsBodies (require :layout-physics-bodies))
(local DemoLines (require :demo-lines))
(local DemoPoints (require :demo-points))
(local DemoAudio (require :demo-audio))
(local Container (require :container))
(local WidgetCuboid (require :widget-cuboid))
(local GraphNodeCube (require :graph-node-cube))
(local Sized (require :sized))
(local SceneWorldState (require :scene-world-state))
(local Ball (require :ball))
(local GltfMesh (require :gltf-mesh))
(local BuildContext (require :build-context))
(local viewport-utils (require :viewport-utils))
(local MathUtils (require :math-utils))
(local CoordinateGuard (require :coordinate-guard))
(local logging (require :logging))
(local TerrainQuery (require :terrain-query))
(local HeightfieldTerrainData (require :heightfield-terrain-data))

(local default-position (glm.vec3 -5 0 0))
(local default-rotation (glm.quat (math.rad 30) (glm.vec3 0 1 0)))
(local default-depth-scale 0)
(local default-camera-distance 100.0)

(local vec3->array (. MathUtils :vec3->array))
(local quat->array (. MathUtils :quat->array))
(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))
(local safe-vec3? CoordinateGuard.safe-vec3?)

(local built-in-scene-kinds {:graph-node-cube true
                             :physics-ball true
                             :physics-cuboid true
                             :demo-browser true})

(fn normalize-or [value fallback]
  (if (and value (> (glm.length value) 1e-6))
      (glm.normalize value)
      fallback))

(fn terrain-query-record [metadata]
  (local record (and metadata metadata.record))
  (local layout (and metadata metadata.element metadata.element.layout))
  (if (or (not record)
          (not layout)
          (not (= record.kind "heightfield-terrain")))
      record
      (do
        (local bounds (HeightfieldTerrainData.sample-bounds record))
        (local spacing (or (and record.options record.options.sample-spacing) [20 20]))
        (local spacing-x (or (. spacing 1) spacing.x 20))
        (local spacing-z (or (. spacing 2) spacing.y spacing.z 20))
        (local canonical-origin-offset
          (glm.vec3 (* bounds.min-sample-x spacing-x)
                    0
                    (* bounds.min-sample-z spacing-z)))
        (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
        (local canonical-position
          (- layout.position (rotation:rotate canonical-origin-offset)))
        (local options {})
        (each [key value (pairs (or record.options {}))]
          (set (. options key) value))
        (set options.position [canonical-position.x canonical-position.y canonical-position.z])
        (set options.rotation [rotation.w rotation.x rotation.y rotation.z])
        {:id record.id
         :kind record.kind
         :options options
         :chunks record.chunks})))

(fn resolve-camera-placement [self]
  (local camera app.camera)
  (local origin (or (and camera camera.position) self.default-position))
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

(fn add-widget-as-cuboid [_self widget-builder opts]
  (assert widget-builder "Scene.add-widget-as-cuboid requires a widget builder")
  (local options (or opts {}))
  (local depth-scale (or options.depth-scale default-depth-scale))

  (fn cuboid-builder [ctx runtime-opts]
    (local wc-opts {:child widget-builder
                    :min-depth 10
                    :depth-scale depth-scale})
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

(fn collect-ball-movables [entity]
  (var entries [])
  (each [_ ball (ipairs (or (and entity entity.balls) []))]
    (local layout (and ball ball.layout))
    (when layout
      (table.insert entries {:target layout
                             :handle ball
                             :key ball
                             :owner ball
                             :on-drag-start (fn [_entry]
                                              (ball:begin-drag))
                             :on-drag-end (fn [_entry]
                                            (ball:end-drag))})))
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
  (each [_ entry (ipairs (collect-ball-movables entity))]
    (table.insert entries entry))
  (local physics-movables (LayoutPhysicsBodies.collect-movables entity))
  (local physics-targets {})
  (each [_ entry (ipairs physics-movables)]
    (when entry
      (table.insert entries entry)))
  (each [_ entry (ipairs physics-movables)]
    (when (and entry entry.target)
      (set (. physics-targets entry.target) true)))
  (each [_ entry (ipairs (collect-positioned-movables self.scene-children))]
    (when (not (. physics-targets entry.target))
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
                      {:element element
                       :position terrain-position
                       :rotation terrain-rotation})))
    (local builder
      (Container {:children
                  container-children}))
    (local entity (builder ctx))
    (set entity.scene-children scene-children)
    (set entity.scene-terrains terrain-children)
    ;(local balls
    ;  (icollect [_ metadata (ipairs entity.children)]
    ;    (and metadata metadata.element metadata.element.is-physics-ball
    ;         metadata.element)))
    ;(set entity.balls (or balls []))
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
               :projection nil
               :entity nil
               :builder nil
               :graph options.graph
               :panel-restorers {}
               :demo-browser nil
               :scene-children nil
               :scene-terrains nil
               :physics-body-count 0
               :default-position (or options.position default-position)
               :default-rotation (or options.rotation default-rotation)
               :reference-point default-position
               :focus-manager focus-manager
               :focus-scope focus-scope})

  (set ctx.pointer-target self)
  (apply-active-theme ctx)

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
          (table.insert filtered entry)))
      (when (= (length filtered) 0)
        (table.insert filtered {:target entity.layout}))
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
          (table.insert filtered entry)))
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

  (fn remove-ball-for-owner [entity owner]
    (when (and entity entity.balls owner)
      (for [idx (length entity.balls) 1 -1]
        (local ball (. entity.balls idx))
        (when (= ball owner)
          (table.remove entity.balls idx)))))

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
      (remove-ball-for-owner entity removed-element)
      (unregister-movables-for-owner self entity removed-element)
      (unregister-resizables-for-owner self entity removed-element)
      (remove-entries-for-owner entity.movables removed-element)
      (remove-entries-for-owner entity.resizables removed-element))
    removed)

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
      (local placement (resolve-camera-placement self))
      (when (and opts opts.rotation)
        (set placement.rotation opts.rotation))
      ;; Scene APIs now treat opts.position as layout-origin coordinates.
      (local requested-layout-position (and opts opts.position))
      (local parent-layout entity.layout)
      (local parent-position (or (and parent-layout parent-layout.position) (glm.vec3 0 0 0)))
      (local parent-rotation (or (and parent-layout parent-layout.rotation) (glm.quat 1 0 0 0)))
      (local parent-inverse (parent-rotation:inverse))
      (local local-rotation (* parent-inverse placement.rotation))
      (set element (builder self.build-context builder-options))
      (local metadata {:flex (or opts.flex 0)
                       :element element
                       :position (glm.vec3 0 0 0)
                       :rotation local-rotation
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
        (set element.layout.rotation placement.rotation)
        (local measure (or element.layout.measure (glm.vec3 0 0 0)))
        (set element.layout.size measure)
        (local layout-position
          (if requested-layout-position
              requested-layout-position
              (layout-origin-from-center placement.center placement.rotation measure)))
        (set element.layout.position layout-position)
        (set metadata.position
             (parent-inverse:rotate (- layout-position parent-position)))
        (element.layout:layouter))
      (when (and self.entity
                 element
                 element.layout
                 (not (and opts opts.skip-physics)))
        (local body-entry
          (LayoutPhysicsBodies.add-runtime-layout-body self.entity {:element element
                                                                    :metadata metadata}))
        (var body-movable nil)
        (each [_ movable (ipairs (LayoutPhysicsBodies.collect-movables self.entity))]
          (when (and (not body-movable)
                     (= movable.key body-entry))
            (set body-movable movable)))
        (when body-movable
          (when (not entity.movables)
            (set entity.movables []))
          (table.insert entity.movables body-movable)
          (register-movable-entries self entity
                                    [(normalize-movable-entry self body-movable)])))
      (when (and element element.layout)
        (when (not entity.movables)
          (set entity.movables []))
        (when (not entity.resizables)
          (set entity.resizables []))
        (var has-physics-movable? false)
        (each [_ entry (ipairs entity.movables)]
          (when (and entry (= entry.owner element))
            (set has-physics-movable? true)))
        (when (not has-physics-movable?)
          (local panel-movable
            {:target element.layout
             :handle element
             :owner element})
          (table.insert entity.movables panel-movable)
          (register-movable-entries self entity
                                    [(normalize-movable-entry self panel-movable)]))
        (local panel-resizable
          {:target element.layout
           :handle element.layout
           :key element
           :min-size (resolve-min-size element.layout)
           :owner element})
        (table.insert entity.resizables panel-resizable)
        (register-resizable-entries self entity
                                    [(normalize-resizable-entry self panel-resizable)]))
      element))

  (fn add-demo-entry [self entry]
    (when (and entry entry.builder)
      (assert entry.persistence
              (.. "Scene.add-demo-entry requires :persistence for demo entry key "
                  (tostring entry.key)))
      (add-panel-child self {:builder entry.builder
                             :flex (or entry.flex 0)
                             :persistence entry.persistence})))

  (fn add-physics-body [self opts]
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

  (fn add-ball [self opts]
    (local options (or opts {}))
    (local size (or options.size (glm.vec3 18 18 18)))
    (local radius (or options.radius (* 0.5 size.x)))
    (local placement (resolve-camera-placement self))
    (local spawn-rotation (or options.rotation placement.rotation))
    (local spawn-layout-position
      (or options.position
          (layout-origin-from-center placement.center spawn-rotation size)))
    (local builder
      (Ball {:radius radius
             :size size
             :position (glm.vec3 0 0 0)
             :color options.color
             :mass options.mass
             :friction options.friction
             :restitution options.restitution
             :initial-velocity options.initial-velocity
             :hexagon-color options.hexagon-color
             :pentagon-color options.pentagon-color}))
    (local element
      (add-panel-child self {:builder builder
                             :skip-cuboid true
                             :skip-physics true
                             :position spawn-layout-position
                             :rotation spawn-rotation
                             :persistence {:kind "physics-ball"
                                           :size (vec3->array size)
                                           :radius radius
                                           :color (vec4->array options.color)
                                           :mass options.mass
                                           :friction options.friction
                                           :restitution options.restitution
                                           :initial-velocity (and options.initial-velocity
                                                                  (vec3->array options.initial-velocity))
                                           :hexagon-color (vec4->array options.hexagon-color)
                                           :pentagon-color (vec4->array options.pentagon-color)}}))
    (when (and self.entity element)
      (when (not self.entity.balls)
        (set self.entity.balls []))
      (table.insert self.entity.balls element)
      (unregister-movables-for-owner self self.entity element)
      (remove-entries-for-owner self.entity.movables element)
      (when (not self.entity.movables)
        (set self.entity.movables []))
      (local ball-movable (. (collect-ball-movables self.entity) (length self.entity.balls)))
      (when ball-movable
        (table.insert self.entity.movables ball-movable)
        (register-movable-entries self self.entity
                                  [(normalize-movable-entry self ball-movable)]))
      (when self.entity.layout
        (element:ensure-body self.entity.layout))
      (self:sync-physics-balls))
    element)

  (fn add-graph-node-cube [self opts]
    (local options (or opts {}))
    (local key (tostring (or options.node-key (and options.node options.node.key) "")))
    (assert (> (string.len key) 0)
            "Scene.add-graph-node-cube requires :node or :node-key")
    (local graph (or self.graph app.graph))
    (local node (or options.node
                    (and graph graph.lookup (graph:lookup key))
                    (and graph graph.load-by-key (graph:load-by-key key))))
    (assert node (.. "Scene.add-graph-node-cube could not resolve node for key: " key))
    (local label (or options.label (and node node.label) key))
    (local size (or options.size (glm.vec3 4 4 4)))
    (local placement (resolve-camera-placement self))
    (local stack-index self.physics-body-count)
    (local stacked-center
      (+ placement.center
         (glm.vec3 0 (+ 6 (* stack-index 4)) 0)))
    (set self.physics-body-count (+ stack-index 1))
    (fn on-graph-action [_cube _button _event payload]
      (local graph (or self.graph app.graph))
      (when graph
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
                           (and payload payload.cube-position))})))))
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
                                           :node-key key
                                           :label label
                                           :size (vec3->array size)}}))
    (when element
      (self:sync-physics-bodies))
    element)

  (fn add-demo-browser [self opts]
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

  (fn sync-physics-balls [self]
    (Ball.sync-all self.entity))

  (fn replace-terrain-record [self terrain-id record]
    (local runtime-entry (require-terrain-runtime-entry self terrain-id))
    (local entity runtime-entry.entity)
    (local terrain-entry runtime-entry.terrain-entry)
    (local current-element runtime-entry.current-element)
    (local child-index runtime-entry.child-index)
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
    (local new-child-metadata {:element new-element
                               :position terrain-spec.position
                               :rotation terrain-spec.rotation
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

  (fn set-terrain-preview-target [self terrain-id target]
    (local runtime-entry (require-terrain-runtime-entry self terrain-id))
    (local element runtime-entry.current-element)
    (require-terrain-selection-method element terrain-id :set-preview-target)
    (assert (element:set-preview-target target)
            (.. "Scene failed to set terrain preview for " terrain-id))
    true)

  (fn clear-terrain-preview-target [self terrain-id]
    (local runtime-entry (require-terrain-runtime-entry self terrain-id))
    (local element runtime-entry.current-element)
    (require-terrain-selection-method element terrain-id :clear-preview-target)
    (assert (element:clear-preview-target)
            (.. "Scene failed to clear terrain preview for " terrain-id))
    true)

  (fn add-terrain-record [self record]
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
    (local new-child-metadata {:element new-element
                               :position terrain-spec.position
                               :rotation terrain-spec.rotation
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
    true)

  (fn remove-terrain [self terrain-id]
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
    true)

  (fn attach-entity [self entity]
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
      (Ball.attach-all entity)
      (set entity.movables (compute-entity-movables self entity))
      (set entity.resizables (compute-entity-resizables self entity))
      (register-entity-movables self entity)
      (register-entity-resizables self entity)
      (self:sync-physics-bodies)))

  (fn build [self builder]
    (set self.builder builder)
    (if builder
      (do
        (apply-active-theme self.build-context)
        (self:attach-entity (builder self.build-context)))
      (self:attach-entity nil)))

(fn build-default [self opts]
  (self:build (make-default-builder opts)))

(fn update [self]
  (self:sync-physics-bodies)
  (self:sync-physics-balls)
  (self.layout-root:update))

  (fn drop [self]
  (when self.entity
    (self:unregister-entity self.entity)
    (self.entity:drop)
    (set self.entity nil)
    (set self.scene-children nil)
    (set self.scene-terrains nil))
  (set self.demo-browser nil)
  (when (and self.focus-manager self.focus-scope)
    (self.focus-manager:detach self.focus-scope)
    (set self.focus-scope nil)))

(fn reset-projection [self]
  (set self.projection (app.create-default-projection)))

(fn get-view-matrix [_self]
  (if app.camera
    (app.camera:get-view-matrix)
    (glm.mat4 1)))

(fn get-triangle-vector [self]
  self.build-context.triangle-vector)

(fn get-triangle-batches [self]
  (and self.build-context
       self.build-context.get-triangle-batches
       (self.build-context:get-triangle-batches)))

(fn get-line-vector [self]
  self.build-context.line-vector)

(fn get-point-vector [self]
  self.build-context.point-vector)

(fn get-line-strips [self]
  self.build-context.line-strips)

(fn get-image-batches [self]
  self.build-context.image-batches)

(fn get-quad-draw-list [self]
  (and self.build-context
       self.build-context.get-quad-draw-list
       (self.build-context:get-quad-draw-list)))

(fn get-text-ssbo-draw-list [self]
  (and self.build-context
       self.build-context.get-text-ssbo-draw-list
       (self.build-context:get-text-ssbo-draw-list)))

(fn get-mesh-batches [self]
  (and self.build-context
       self.build-context.get-mesh-batches
       (self.build-context:get-mesh-batches)))

(fn get-reference-point [self]
  self.reference-point)

(fn screen-pos-ray [self pos opts]
  (local options (or opts {}))
  (local viewport (viewport-utils.to-table (or options.viewport app.viewport)))
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

(fn on-viewport-changed [_self _viewport]
  nil)

(fn raycast-terrain [self ray]
  (var best nil)
  (each [_ metadata (ipairs (or self.scene-terrains []))]
    (local record (and metadata metadata.record))
    (local query-record (terrain-query-record metadata))
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

(fn screen-pos-terrain-hit [self pos opts]
  (self:raycast-terrain (self:screen-pos-ray pos opts)))

(fn screen-pos-terrain-domain-hit [self pos opts]
  (local ray (self:screen-pos-ray pos opts))
  (var best nil)
  (each [_ metadata (ipairs (or self.scene-terrains []))]
    (local record (and metadata metadata.record))
    (local query-record (terrain-query-record metadata))
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

(fn screen-drag-terrain-target [self start-pos end-pos opts]
  (local start-hit (self:screen-pos-terrain-domain-hit start-pos opts))
  (local end-hit (self:screen-pos-terrain-domain-hit end-pos opts))
  (if (and start-hit
           end-hit
           (= start-hit.terrain-id end-hit.terrain-id)
           (= start-hit.terrain-kind end-hit.terrain-kind))
      (do
        (local record start-hit.terrain-record)
        (local query-record (or start-hit.query-record record))
        (local target
          (and query-record
               (TerrainQuery.target-between-hits query-record start-hit end-hit)))
        (and target
             {:terrain-record record
              :terrain-id start-hit.terrain-id
              :terrain-kind start-hit.terrain-kind
              :start-hit start-hit
              :end-hit end-hit
              :target target}))
      nil))

(fn screen-rect-terrain-target [self terrain-id start-pos end-pos opts]
  (local terrain-entry (find-terrain-entry self.scene-terrains terrain-id))
  (if (not terrain-entry)
      nil
      (do
        (local metadata terrain-entry.metadata)
        (local record (and metadata metadata.record))
        (local query-record (and metadata (terrain-query-record metadata)))
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
    (local terrains
      (SceneWorldState.capture-terrains self.scene-terrains))
    (each [_ metadata (ipairs (or self.scene-children []))]
      (local persistence (and metadata metadata.persistence))
      (assert persistence
              "Scene.capture-state found panel without persistence")
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
        (local record (clone-table persistence))
        (set record.position layout-state.position)
        (set record.rotation layout-state.rotation)
        (set record.size (or layout-state.size record.size))
        (table.insert panels record)))
    {:panels panels
     :terrains terrains})

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

  (fn restore-state [self state]
    (local payload (or state {}))
    (local panels (or payload.panels []))
    (assert (= (type panels) :table) "Scene.restore-state requires :panels table")
    (each [panel-idx panel (ipairs panels)]
      (assert (= (type panel) :table) "Scene.restore-state panel entries must be tables")
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
          (self:add-graph-node-cube {:node-key panel.node-key
                                     :label panel.label
                                     :size restored-size
                                     :position restored-position
                                     :rotation (array->quat panel.rotation)})
          (= kind "physics-cuboid")
          (self:add-physics-body {:size restored-size
                                  :position restored-position
                                  :rotation (array->quat panel.rotation)})
          (= kind "physics-ball")
          (self:add-ball {:size restored-size
                          :radius panel.radius
                          :position restored-position
                          :rotation (array->quat panel.rotation)
                          :color (and panel.color (glm.vec4 (. panel.color 1)
                                                            (. panel.color 2)
                                                            (. panel.color 3)
                                                            (. panel.color 4)))
                          :mass panel.mass
                          :friction panel.friction
                          :restitution panel.restitution
                          :initial-velocity (and panel.initial-velocity
                                                 (array->vec3 panel.initial-velocity))
                          :hexagon-color (and panel.hexagon-color
                                              (glm.vec4 (. panel.hexagon-color 1)
                                                        (. panel.hexagon-color 2)
                                                        (. panel.hexagon-color 3)
                                                        (. panel.hexagon-color 4)))
                          :pentagon-color (and panel.pentagon-color
                                               (glm.vec4 (. panel.pentagon-color 1)
                                                         (. panel.pentagon-color 2)
                                                         (. panel.pentagon-color 3)
                                                         (. panel.pentagon-color 4)))})
          (= kind "demo-browser")
          (self:add-demo-browser {:position restored-position
                                  :rotation (array->quat panel.rotation)})
          (do
            (restore-panel-with-fallback self panel panel-idx))))
    true)

(set self.unregister-entity unregister-entity)
(set self.attach-entity attach-entity)
(set self.build build)
(set self.build-default build-default)
(set self.update update)
(set self.drop drop)
(set self.sync-physics-bodies sync-physics-bodies)
(set self.sync-physics-balls sync-physics-balls)
(set self.replace-terrain-record replace-terrain-record)
(set self.add-terrain-record add-terrain-record)
(set self.remove-terrain remove-terrain)
(set self.set-terrain-selection-target set-terrain-selection-target)
(set self.clear-terrain-selection-target clear-terrain-selection-target)
(set self.get-terrain-selection-target get-terrain-selection-target)
(set self.set-terrain-preview-target set-terrain-preview-target)
(set self.clear-terrain-preview-target clear-terrain-preview-target)
(set self.reset-projection reset-projection)
(set self.get-view-matrix get-view-matrix)
(set self.get-triangle-vector get-triangle-vector)
(set self.get-triangle-batches get-triangle-batches)
(set self.get-line-vector get-line-vector)
(set self.get-point-vector get-point-vector)
(set self.get-line-strips get-line-strips)
(set self.get-image-batches get-image-batches)
(set self.get-quad-draw-list get-quad-draw-list)
(set self.get-text-ssbo-draw-list get-text-ssbo-draw-list)
(set self.get-mesh-batches get-mesh-batches)
(set self.get-reference-point get-reference-point)
(set self.screen-pos-ray screen-pos-ray)
(set self.raycast-terrain raycast-terrain)
(set self.screen-pos-terrain-hit screen-pos-terrain-hit)
(set self.screen-pos-terrain-domain-hit screen-pos-terrain-domain-hit)
(set self.screen-drag-terrain-target screen-drag-terrain-target)
(set self.screen-rect-terrain-target screen-rect-terrain-target)
(set self.on-viewport-changed on-viewport-changed)
(set self.capture-state capture-state)
(set self.restore-state restore-state)
(set self.capture-panel-element-state capture-panel-element-state)
(set self.register-panel-restorer register-panel-restorer)
(set self.unregister-panel-restorer unregister-panel-restorer)
(set self.add-widget-as-cuboid add-widget-as-cuboid)
(set self.add-panel-child add-panel-child)
(set self.remove-panel-child remove-panel-child)
(set self.add-demo-entry add-demo-entry)
(set self.add-demo-browser add-demo-browser)
(set self.add-ball add-ball)
(set self.add-physics-body add-physics-body)
(set self.add-graph-node-cube add-graph-node-cube)
(set self.set-graph (fn [_self graph] (set self.graph graph)))
(self:reset-projection)
self)

Scene
