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
    (local spawn-layout-position
      (or options.position
          (layout-origin-from-center placement.center placement.rotation size)))
    (local builder
      (Ball {:radius radius
             :size size
             :position (glm.vec3 0 0 0)
             :color options.color
             :mass options.mass
             :friction options.friction
             :restitution options.restitution
             :initial-velocity options.initial-velocity}))
    (local element
      (add-panel-child self {:builder builder
                             :skip-cuboid true
                             :skip-physics true
                             :position spawn-layout-position
                             :rotation options.rotation
                             :persistence {:kind "physics-ball"
                                           :size (vec3->array size)}}))
    (when (and self.entity element)
      (when (not self.entity.balls)
        (set self.entity.balls []))
      (table.insert self.entity.balls element)
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
  (local sample-pos (or pos
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

  (fn resolve-panel-restorer [self panel]
    (local kind panel.kind)
    (local registered-record (. self.panel-restorers kind))
    (local registered (and registered-record registered-record.restore))
    (if registered
        registered
        (do
          (local module-name panel.restorer-module)
          (assert (= (type module-name) :string)
                  (.. "Scene.restore-state panel kind "
                      kind
                      " requires string :restorer-module or registered restorer"))
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
          (fn [payload]
            (restore {:scene self
                      :target self
                      :panel payload})))))

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
                          :position restored-position
                          :rotation (array->quat panel.rotation)})
          (= kind "demo-browser")
          (self:add-demo-browser {:position restored-position
                                  :rotation (array->quat panel.rotation)})
          (do
            (local restorer (resolve-panel-restorer self panel))
            (restorer panel))))
    true)

(set self.unregister-entity unregister-entity)
(set self.attach-entity attach-entity)
(set self.build build)
(set self.build-default build-default)
(set self.update update)
(set self.drop drop)
(set self.sync-physics-bodies sync-physics-bodies)
(set self.sync-physics-balls sync-physics-balls)
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
