(local glm (require :glm))
(local {: Layout : LayoutRoot} (require :layout))
(local BuildContext (require :build-context))
(local HudLayout (require :hud-layout))
(local viewport-utils (require :viewport-utils))
(local Rectangle (require :rectangle))
(local Padding (require :padding))
(local Stack (require :stack))

(local identity-view (glm.mat4 1))
(local default-world-scale 0.05)
(local default-size-scale 2.0) ; enlarge orthographic bounds so HUD renders smaller on screen
(local panel-border-size 0.2)

(fn resolve-active-theme []
  (and app.engine app.themes app.themes.get-active-theme
       (app.themes.get-active-theme)))

(fn apply-active-theme [ctx]
  (when (and ctx ctx.set-theme)
    (ctx:set-theme (resolve-active-theme))))

(fn resolve-panel-border-color [ctx]
  (local theme (and ctx ctx.theme))
  (or (and theme theme.panel-border)
      (and theme theme.hud theme.hud.panel-border)
      (glm.vec4 0.72 0.75 0.79 0.85)))

(fn Hud [opts]
  (local options (or opts {}))
  (local layout-root (LayoutRoot))
  (local focus-manager options.focus-manager)
  (local focus-root (and focus-manager (focus-manager:get-root-scope)))
  (local focus-scope
    (or options.focus-scope
        (and focus-manager
             (focus-manager:create-scope {:name (or options.focus-scope-name "hud")}))))
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
               :tiles nil
               :float nil
               :overlay-root nil
               :scene options.scene
               :margin-px (or options.margin-px 0)
               :scale-factor (or options.scale-factor default-size-scale)
               :world-units-per-pixel default-world-scale
               :half-width 1
               :half-height 1
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
        (when (not entry.pointer-target)
          (set options.pointer-target self))
        (local key (or entry.key widget entry))
        (when key
          (set options.key key)
          (app.movables:register widget options)
          (table.insert keys key)))
      (set entity.__hud_movable_keys keys)))

  (fn register-entity-movables [self entity]
    (when (and entity app.movables)
      (local entries (icollect [_ entry (ipairs (or entity.movables []))]
                               (normalize-movable-entry self entry)))
      (var filtered [])
      (each [_ entry (ipairs entries)]
        (when entry
          (table.insert filtered entry)))
      (if (> (length filtered) 0)
          (register-movable-entries self entity filtered)
          (set entity.__hud_movable_keys nil))))

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
        (when (not entry.pointer-target)
          (set options.pointer-target self))
        (local key (or entry.key widget entry))
        (when key
          (set options.key key)
          (app.resizables:register widget options)
          (table.insert keys key)))
      (set entity.__hud_resizable_keys keys)))

  (fn register-entity-resizables [self entity]
    (when (and entity app.resizables)
      (local entries (icollect [_ entry (ipairs (or entity.resizables []))]
                               (normalize-resizable-entry self entry)))
      (var filtered [])
      (each [_ entry (ipairs entries)]
        (when entry
          (table.insert filtered entry)))
      (if (> (length filtered) 0)
          (register-resizable-entries self entity filtered)
          (set entity.__hud_resizable_keys nil))))

  (fn resolve-panel-wrapper [element]
    (if (not element)
        nil
        (if element.__hud_inner
            element
            (or element.__hud_wrapper element))))

  (fn wrap-panel-element [self element]
    (local wrapper (resolve-panel-wrapper element))
    (if (and wrapper wrapper.__hud_inner)
        wrapper
        (let [ctx self.build-context
              border-color (resolve-panel-border-color ctx)
              border ((Rectangle {:color border-color}) ctx)
              padding ((Padding {:edge-insets [panel-border-size panel-border-size]
                                 :child (fn [_ctx] element)}) ctx)
              wrapper ((Stack {:children [(fn [_ctx] border)
                                          (fn [_ctx] padding)]}) ctx)]
          (set wrapper.__hud_inner element)
          (set element.__hud_wrapper wrapper)
          wrapper)))

  (fn promote-tile-element [self element entry source]
    (local wrapper (resolve-panel-wrapper element))
    (when (and wrapper self.tiles self.float)
      ;; Always detach from tiles to ensure no duplicates/fighting
      ;; This handles the case where an element might be in both (ghost in tiles)
      (local tile-metadata (self.tiles:detach-child wrapper))
      
      (var float-meta nil)
      (each [_ meta (ipairs self.float.children)]
        (when (= meta.element wrapper)
          (set float-meta meta)))
      
      (if float-meta
          float-meta
          (when tile-metadata
            (local layout wrapper.layout)
            (local position (and layout layout.position))
            (local rotation (and layout layout.rotation))
            (local size (and layout layout.size))
            (set float-meta (self.float:attach-child wrapper {:position position
                                                              :rotation rotation
                                                              :size size}))
            (when entry
              (set entry.target (self.float:ensure-movable-target float-meta)))
            
            ;; Cross-Registry Refresh to keep passive registries up to date
            (when (= source :movable)
              (self:refresh-panel-resizables))
            (when (= source :resizable)
              (self:refresh-panel-movables))
              
            float-meta))))

  (fn resolve-min-size [layout]
    (or (and layout layout.measure)
        (and layout layout.size)
        (glm.vec3 0 0 0)))

  (fn collect-panel-movables [self]
    (var entries [])
    (when self.tiles
      (each [_ metadata (ipairs self.tiles.children)]
        (local element (and metadata metadata.element))
        (local wrapper (resolve-panel-wrapper element))
        (local layout (and wrapper wrapper.layout))
        (when layout
          (table.insert entries {:target layout
                                 :handle wrapper
                                 :key wrapper
                                 :on-drag-start (fn [entry]
                                                 (promote-tile-element self wrapper entry :movable))}))))
    (when self.float
      (each [_ metadata (ipairs self.float.children)]
        (local element (and metadata metadata.element))
        (local wrapper (resolve-panel-wrapper element))
        (local target (self.float:ensure-movable-target metadata))
        (local handle (and wrapper wrapper.layout))
        (when (and handle target)
          (table.insert entries {:target target
                                 :handle handle
                                 :key wrapper}))))
    entries)

  (fn collect-panel-resizables [self]
    (var entries [])
    (when self.tiles
      (each [_ metadata (ipairs self.tiles.children)]
        (local element (and metadata metadata.element))
        (local wrapper (resolve-panel-wrapper element))
        (local layout (and wrapper wrapper.layout))
        (when layout
          (local min-size (resolve-min-size layout))
          (table.insert entries {:target layout
                                 :handle layout
                                 :key wrapper
                                 :min-size min-size
                                 :pointer-target self
                                 :on-resize-start (fn [entry]
                                                    (local float-meta (promote-tile-element self wrapper nil :resizable))
                                                    (when (and float-meta self.float)
                                                      (set entry.target (self.float:ensure-resize-target float-meta)))
                                                    entry)}))))
    (when self.float
      (each [_ metadata (ipairs self.float.children)]
        (local element (and metadata metadata.element))
        (local wrapper (resolve-panel-wrapper element))
        (local layout (and wrapper wrapper.layout))
        (local target (self.float:ensure-resize-target metadata))
        (when (and layout target)
          (local min-size (resolve-min-size layout))
          (table.insert entries {:target target
                                 :handle layout
                                 :key wrapper
                                 :min-size min-size
                                 :pointer-target self}))))
    entries)

  (fn unregister-entity-movables [self entity]
    (when (and entity app.movables)
      (local keys entity.__hud_movable_keys)
      (if (and keys (> (length keys) 0))
          (each [_ key (ipairs keys)]
            (app.movables:unregister key))
          (app.movables:unregister entity))
      (set entity.__hud_movable_keys nil)))

  (fn unregister-entity-resizables [self entity]
    (when (and entity app.resizables)
      (local keys entity.__hud_resizable_keys)
      (if (and keys (> (length keys) 0))
          (each [_ key (ipairs keys)]
            (app.resizables:unregister key))
          (app.resizables:unregister entity))
      (set entity.__hud_resizable_keys nil)))

  (fn refresh-panel-movables [self]
    (when self.entity
      (unregister-entity-movables self self.entity)
      (set self.entity.movables (collect-panel-movables self))
      (register-entity-movables self self.entity)))

  (fn refresh-panel-resizables [self]
    (when self.entity
      (unregister-entity-resizables self self.entity)
      (set self.entity.resizables (collect-panel-resizables self))
      (register-entity-resizables self self.entity)))

  (fn unregister-entity [self entity]
    (unregister-entity-movables self entity)
    (unregister-entity-resizables self entity))

  (fn update-root-transform [self opts]
    (when self.entity
      (local options (or opts {}))
      (local skip-mark? (or options.skip-mark-dirty? false))
      (local mark-dirty? (not skip-mark?))
      (local margin (* self.world-units-per-pixel self.margin-px))
      (local layout self.entity.layout)
      (local measured (and layout layout.measure))
      (local height (if measured (. measured 2) 0))
      (local x (+ (- self.half-width) margin))
      (local top (- self.half-height margin))
      (local y (- top height))
      (layout:set-position (glm.vec3 x y 0))
      (layout:set-rotation (glm.quat 1 0 0 0))
      (when mark-dirty?
        (layout:mark-measure-dirty))))

  (fn attach-entity [self entity]
    (when self.entity
      (self:unregister-entity self.entity)
      (self.entity:drop))
    (set self.entity entity)
    (set self.tiles nil)
    (set self.float nil)
    (set self.overlay-root nil)
    (when entity
      (set self.tiles entity.tiles-root)
      (set self.float entity.float-root)
      (set self.overlay-root entity.overlay-root)
      (entity.layout:set-root self.layout-root)
      (self:update-root-transform)
      (set entity.movables (collect-panel-movables self))
      (set entity.resizables (collect-panel-resizables self))
      (register-entity-movables self entity)
      (register-entity-resizables self entity)))

  (fn build [self builder]
    (set self.builder builder)
    (if builder
        (do
          (apply-active-theme self.build-context)
          (self:attach-entity (builder self.build-context)))
        (self:attach-entity nil)))

  (fn build-default [self opts]
    (self:build (HudLayout.make-hud-builder opts)))

  (fn remove-panel-child [self element]
    (local wrapper (resolve-panel-wrapper element))
    (var removed nil)
    (when (and self.tiles wrapper)
      (set removed (self.tiles:remove-child wrapper)))
    (when (and (not removed) self.float wrapper)
      (set removed (self.float:remove-child wrapper)))
    (when removed
      (self:refresh-panel-movables)
      (self:refresh-panel-resizables))
    (not (= removed nil)))

  (fn add-panel-child [self opts]
    (local options (or opts {}))
    (local destination (or options.location options.layer :tiles))
    (local builder (and options options.builder))
    (when builder
      (when (and (or (= destination :float) (= destination "float"))
                 (not self.float))
        (error "Hud.add-panel-child requires a float root"))
      (when (and (or (= destination :tiles) (= destination "tiles"))
                 (not self.tiles))
        (error "Hud.add-panel-child requires a tiles root"))
      (local builder-options {})
      (each [key value (pairs (or options.builder-options {}))]
        (set (. builder-options key) value))
      (var element nil)
      (var close-called? false)
      (local user-on-close builder-options.on-close)
      (fn handle-close [dialog button event]
        (when (not close-called?)
          (set close-called? true)
          (when user-on-close
            (user-on-close dialog button event))
          (when element
            (self:remove-panel-child element))))
      (set builder-options.on-close handle-close)
      (set element (builder self.build-context builder-options))
      (local wrapper (wrap-panel-element self element))
      (if (or (= destination :float) (= destination "float"))
          (self.float:attach-child wrapper {:position options.position
                                            :rotation options.rotation
                                            :size options.size
                                            :depth-offset-index options.depth-offset-index})
          (self.tiles:attach-child wrapper {:align-x options.align-x
                                            :align-y options.align-y}))
      (self:refresh-panel-movables)
      (self:refresh-panel-resizables)
      element))

  (fn remove-overlay-child [self element]
    (local root self.overlay-root)
    (var removed false)
    (when (and root element)
      (each [idx metadata (ipairs root.children)]
        (when (and (not removed) (= metadata.element element))
          (set removed true)
          (root.layout:remove-child idx)
          (table.remove root.children idx)
          (root.layout:mark-measure-dirty)
          (root.layout:mark-layout-dirty))))
    (when removed
      (when (and element element.drop)
        (element:drop)))
    removed)

  (fn add-overlay-child [self opts]
    (local root self.overlay-root)
    (local builder (and opts opts.builder))
    (when (and root builder)
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
          (when element
            (self:remove-overlay-child element))))
      (set builder-options.on-close handle-close)
      (set element (builder self.build-context builder-options))
      (local position (or opts.position (glm.vec3 0 0 0)))
      (local rotation (or opts.rotation (glm.quat 1 0 0 0)))
      (local parent-layout root.layout)
      (local parent-position (or (and parent-layout parent-layout.position) (glm.vec3 0 0 0)))
      (local parent-rotation (or (and parent-layout parent-layout.rotation) (glm.quat 1 0 0 0)))
      (local parent-inverse (parent-rotation:inverse))
      (local offset (parent-inverse:rotate (- position parent-position)))
      (local local-rotation (* parent-inverse rotation))
      (local metadata {:element element
                       :position offset
                       :rotation local-rotation
                       :depth-offset-index opts.depth-offset-index})
      (table.insert root.children metadata)
      (root.layout:add-child element.layout)
      (root.layout:mark-measure-dirty)
      (root.layout:mark-layout-dirty)
      element))

  (fn drop [self]
    (when self.entity
      (self:unregister-entity self.entity)
      (self.entity:drop)
    (set self.entity nil))
    (set self.tiles nil)
    (set self.float nil)
    (set self.overlay-root nil)
    (when (and self.focus-manager self.focus-scope)
      (self.focus-manager:detach self.focus-scope)
      (set self.focus-scope nil)))

  (fn get-view-matrix [_self]
    identity-view)

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

  (fn screen-pos-ray [self pos opts]
    (local options (or opts {}))
    (local viewport (viewport-utils.to-table (or options.viewport app.viewport)))
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
        (error (.. "Hud.screen-pos-ray produced non-finite " label))))
    (assert projection "Hud.screen-pos-ray requires a projection matrix")
    (local sample-pos (or pos
                          {:x (+ viewport.x (/ viewport.width 2))
                           :y (+ viewport.y (/ viewport.height 2))}))
    (local px (or sample-pos.x viewport.x))
    (local py (or sample-pos.y viewport.y))
    (local inverted-y (- (+ viewport.height viewport.y) py))
    (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
    (local near (glm.unproject (glm.vec3 px inverted-y 0.0) identity-view projection viewport-vec))
    (local far (glm.unproject (glm.vec3 px inverted-y 1.0) identity-view projection viewport-vec))
    (local direction (glm.normalize (- far near)))
    (assert-finite-vec3 near "near")
    (assert-finite-vec3 far "far")
    (assert-finite-vec3 direction "direction")
    {:origin near :direction direction})

  (fn update-projection [self viewport]
    (local vp (or viewport {:x 0 :y 0 :width 1 :height 1}))
    (local adjusted-scale (* default-world-scale self.scale-factor))
    (set self.world-units-per-pixel adjusted-scale)
    (local safe-width (math.max vp.width 1))
    (local safe-height (math.max vp.height 1))
    (set self.half-width (math.max 0.001 (* 0.5 safe-width adjusted-scale)))
    (set self.half-height (math.max 0.001 (* 0.5 safe-height adjusted-scale)))
    (if glm.ortho
        (set self.projection (glm.ortho (- self.half-width) self.half-width (- self.half-height) self.half-height -100.0 100.0))
        (set self.projection identity-view))
    (self:update-root-transform))

  (fn reset-projection [self]
    (self:update-projection app.viewport))

  (fn on-viewport-changed [self viewport]
    (self:update-projection viewport))

  (fn update [self]
    (self.layout-root:update)
    (self:update-root-transform {:skip-mark-dirty? true}))

  (set self.unregister-entity unregister-entity)
  (set self.attach-entity attach-entity)
  (set self.build build)
  (set self.build-default build-default)
  (set self.drop drop)
  (set self.update-root-transform update-root-transform)
  (set self.get-view-matrix get-view-matrix)
  (set self.get-triangle-vector get-triangle-vector)
  (set self.get-triangle-batches get-triangle-batches)
  (set self.get-line-vector get-line-vector)
  (set self.get-point-vector get-point-vector)
  (set self.get-line-strips get-line-strips)
  (set self.get-text-vectors get-text-vectors)
  (set self.get-text-batches get-text-batches)
  (set self.get-image-batches get-image-batches)
  (set self.reset-projection reset-projection)
  (set self.on-viewport-changed on-viewport-changed)
  (set self.update update)
  (set self.update-projection update-projection)
  (set self.screen-pos-ray screen-pos-ray)
  (set self.add-panel-child add-panel-child)
  (set self.remove-panel-child remove-panel-child)
  (set self.add-overlay-child add-overlay-child)
  (set self.remove-overlay-child remove-overlay-child)
  (set self.refresh-panel-movables refresh-panel-movables)
  (set self.refresh-panel-resizables refresh-panel-resizables)

  (self:reset-projection)
  self)

(local exports {:Hud Hud})

(setmetatable exports
              {:__call (fn [_ ...]
                         (Hud ...))})

exports
