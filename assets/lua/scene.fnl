(local glm (require :glm))
(local {: LayoutRoot} (require :layout))
(local DemoDialogs (require :demo-dialogs))
(local DemoPhysicsCuboids (require :demo-physics-cuboids))
(local DemoLines (require :demo-lines))
(local DemoPoints (require :demo-points))
(local DemoAudio (require :demo-audio))
(local Container (require :container))
(local WidgetCuboid (require :widget-cuboid))
(local FlatTerrain (require :flat-terrain))
(local Ball (require :ball))
(local GltfMesh (require :gltf-mesh))
(local BuildContext (require :build-context))
(local viewport-utils (require :viewport-utils))

(local default-position (glm.vec3 -5 0 0))
(local default-rotation (glm.quat (math.rad 30) (glm.vec3 0 1 0)))
(local default-depth-scale 0)
(local default-camera-distance 100.0)

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
  {:position (+ origin (* forward (glm.vec3 default-camera-distance)))
   :rotation facing-rotation})

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
                             :handle element})))
  entries)

(fn resolve-min-size [layout]
  (or (and layout layout.measure)
      (and layout layout.size)
      (glm.vec3 0 0 0)))

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
                             :min-size min-size})))
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
  (each [_ entry (ipairs (collect-positioned-movables self.scene-children))]
    (table.insert entries entry))
  entries)

(fn compute-entity-resizables [self entity]
  (local base (or entity.__scene_base_resizables []))
  (local entries (copy-movables base))
  (each [_ entry (ipairs (collect-positioned-resizables self.scene-children))]
    (table.insert entries entry))
  entries)

(fn make-default-builder []
  (local terrain (FlatTerrain {}))
  (local scene-children [])

  (fn build [ctx]
    (local container-children [])
    (table.insert container-children
                  (fn [child-ctx]
                    (local element (terrain child-ctx))
                    {:element element
                     :position (glm.vec3 -500 -100 -500)}))
    (local builder
      (Container {:children
                  container-children}))
    (local entity (builder ctx))
    (set entity.scene-children scene-children)
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
               :demo-browser nil
               :scene-children nil
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
           :on-drag-start entry.on-drag-start
           :on-drag-end entry.on-drag-end})))

  (fn register-movable-entries [self entity entries]
    (when (and entity app.movables)
      (local keys [])
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
          (table.insert keys key)))
      (set entity.__scene_movable_keys keys)))

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
           :min-size entry.min-size
           :on-resize-start entry.on-resize-start
           :on-resize-end entry.on-resize-end})))

  (fn register-resizable-entries [self entity entries]
    (when (and entity app.resizables)
      (local keys [])
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
          (table.insert keys key)))
      (set entity.__scene_resizable_keys keys)))

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
      (set entity.__scene_movable_keys nil)))

  (fn unregister-entity-resizables [self entity]
    (when (and entity app.resizables)
      (local keys entity.__scene_resizable_keys)
      (if (and keys (> (length keys) 0))
          (each [_ key (ipairs keys)]
            (app.resizables:unregister key))
          (app.resizables:unregister entity))
      (set entity.__scene_resizable_keys nil)))

  (fn refresh-panel-movables [self]
    (when self.entity
      (unregister-entity-movables self self.entity)
      (set self.entity.movables (compute-entity-movables self self.entity))
      (register-entity-movables self self.entity)))

  (fn refresh-panel-resizables [self]
    (when self.entity
      (unregister-entity-resizables self self.entity)
      (set self.entity.resizables (compute-entity-resizables self self.entity))
      (register-entity-resizables self self.entity)))

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
      (self:refresh-panel-movables)
      (self:refresh-panel-resizables))
    removed)

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
      (when (and opts opts.position)
        (set placement.position opts.position))
      (when (and opts opts.rotation)
        (set placement.rotation opts.rotation))
      (local parent-layout entity.layout)
      (local parent-position (or (and parent-layout parent-layout.position) (glm.vec3 0 0 0)))
      (local parent-rotation (or (and parent-layout parent-layout.rotation) (glm.quat 1 0 0 0)))
      (local parent-inverse (parent-rotation:inverse))
      (local offset (parent-inverse:rotate (- placement.position parent-position)))
      (local local-rotation (* parent-inverse placement.rotation))
      (set element (builder self.build-context builder-options))
      (local metadata {:flex (or opts.flex 0)
                       :element element
                       :position offset
                       :rotation local-rotation})
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
        (local half-measure (* 0.5 measure))
        (local centered-position
          (- placement.position (placement.rotation:rotate half-measure)))
        (set element.layout.position centered-position)
        (set metadata.position
             (parent-inverse:rotate (- centered-position parent-position)))
        (element.layout:layouter))
      (set entity.movables (compute-entity-movables self entity))
      (refresh-panel-movables self)
      (refresh-panel-resizables self)
      element))

  (fn add-demo-entry [self entry]
    (when (and entry entry.builder)
      (add-panel-child self {:builder entry.builder
                            :flex (or entry.flex 0)})))

  (fn add-demo-browser [self]
    (if self.demo-browser
        self.demo-browser
        (let [browser
              (DemoDialogs.new-browser-dialog
                {:on-open (fn [entry]
                            (self:add-demo-entry entry))})
              element (add-panel-child self {:builder browser})]
          (when element
            (set self.demo-browser element))
          element)))

  (fn unregister-entity [self entity]
    (unregister-entity-movables self entity)
    (unregister-entity-resizables self entity))

  (fn sync-physics-cuboids [self]
    (DemoPhysicsCuboids.sync self.entity))

  (fn sync-physics-balls [self]
    (Ball.sync-all self.entity))

  (fn attach-entity [self entity]
    (when self.entity
      (self:unregister-entity self.entity)
      (self.entity:drop))
    (set self.entity entity)
    (set self.scene-children nil)
    (set self.demo-browser nil)
    (when entity
      (set entity.__scene_base_movables (copy-movables entity.movables))
      (when (not entity.scene-children)
        (set entity.scene-children []))
      (when (not entity.children)
        (set entity.children []))
      (set self.scene-children entity.scene-children)
      (entity.layout:set-root self.layout-root)
      (local position self.default-position)
      (local resolved-position (glm.vec3 position.x position.y position.z))
      (entity.layout:set-position resolved-position)
      (entity.layout:set-rotation self.default-rotation)
      (entity.layout:mark-measure-dirty)
      (set self.reference-point resolved-position)
      (DemoPhysicsCuboids.attach entity entity.__physics_cuboids_spec)
      (Ball.attach-all entity)
      (set entity.movables (compute-entity-movables self entity))
      (set entity.resizables (compute-entity-resizables self entity))
      (register-entity-movables self entity)
      (register-entity-resizables self entity)
      (self:sync-physics-cuboids)))

  (fn build [self builder]
    (set self.builder builder)
    (if builder
      (do
        (apply-active-theme self.build-context)
        (self:attach-entity (builder self.build-context)))
      (self:attach-entity nil)))

(fn build-default [self]
  (self:build (make-default-builder)))

(fn update [self]
  (self:sync-physics-cuboids)
  (self:sync-physics-balls)
  (self.layout-root:update))

(fn drop [self]
  (when self.entity
    (self:unregister-entity self.entity)
    (self.entity:drop)
    (set self.entity nil)
    (set self.scene-children nil))
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

(fn get-text-vectors [self]
  self.build-context.text-vectors)

(fn get-text-batches [self]
  (and self.build-context
       self.build-context.get-text-batches
       (self.build-context:get-text-batches)))

(fn get-image-batches [self]
  self.build-context.image-batches)

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

(set self.unregister-entity unregister-entity)
(set self.attach-entity attach-entity)
(set self.build build)
(set self.build-default build-default)
(set self.update update)
(set self.drop drop)
(set self.sync-physics-cuboids sync-physics-cuboids)
(set self.sync-physics-balls sync-physics-balls)
(set self.reset-projection reset-projection)
(set self.get-view-matrix get-view-matrix)
(set self.get-triangle-vector get-triangle-vector)
(set self.get-triangle-batches get-triangle-batches)
(set self.get-line-vector get-line-vector)
(set self.get-point-vector get-point-vector)
(set self.get-line-strips get-line-strips)
(set self.get-text-vectors get-text-vectors)
(set self.get-text-batches get-text-batches)
(set self.get-image-batches get-image-batches)
(set self.get-mesh-batches get-mesh-batches)
(set self.get-reference-point get-reference-point)
(set self.screen-pos-ray screen-pos-ray)
(set self.on-viewport-changed on-viewport-changed)
(set self.add-widget-as-cuboid add-widget-as-cuboid)
(set self.add-panel-child add-panel-child)
(set self.remove-panel-child remove-panel-child)
(set self.add-demo-entry add-demo-entry)
(set self.add-demo-browser add-demo-browser)
(set self.refresh-panel-movables refresh-panel-movables)
(set self.refresh-panel-resizables refresh-panel-resizables)

(self:reset-projection)
self)

Scene
