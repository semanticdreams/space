(local glm (require :glm))
(local logging (require :logging))
(local {: LayoutRoot} (require :layout))
(local BuildContext (require :build-context))
(local FloatLayer (require :float-layer))
(local viewport-utils (require :viewport-utils))
(local MathUtils (require :math-utils))
(local LightingViewState (require :lighting-view-state))

(local vec3->array (. MathUtils :vec3->array))
(local quat->array (. MathUtils :quat->array))
(local array->vec3 (. MathUtils :array->vec3))
(local default-world-scale 1.0)
(local default-scale-factor 1.0)
(local panel-depth-layer-step 8)

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

(fn safe-vec3? [value]
  (and value
       (finite-number? value.x)
       (finite-number? value.y)
       (finite-number? value.z)))

(fn resolve-active-theme []
  (and app.engine app.themes app.themes.get-active-theme
       (app.themes.get-active-theme)))

(fn apply-active-theme [ctx]
  (when (and ctx ctx.set-theme)
    (ctx:set-theme (resolve-active-theme))))

(fn capture-panel-layout-state [metadata]
  (local element (and metadata metadata.element))
  (local layout (and element element.layout))
  (if (not layout)
      nil
      (do
        (local size (or layout.size layout.measure))
        {:position (vec3->array layout.position)
         :rotation (quat->array layout.rotation)
         :size (and size (vec3->array size))})))

(fn resolve-min-size [layout]
  (and layout layout.min-size))

(fn Canvas [opts]
  (local options (or opts {}))
  (local camera (assert options.camera "Canvas requires :camera"))
  (local layout-root (LayoutRoot))
  (local focus-manager options.focus-manager)
  (local focus-root (and focus-manager (focus-manager:get-root-scope)))
  (local focus-scope
    (or options.focus-scope
        (and focus-manager
             (focus-manager:create-scope {:name (or options.focus-scope-name "canvas")
                                          :directional-traversal-boundary? true}))))
  (local ctx
    (BuildContext {:theme (resolve-active-theme)
                   :quad-unlit? true
                   :clickables app.clickables
                   :hoverables app.hoverables
                   :touch-gesture-targets app.touch-gesture-targets
                   :system-cursors app.system-cursors
                   :icons options.icons
                   :states options.states
                   :layout-root layout-root
                   :movables options.movables
                   :focus-manager focus-manager
                   :focus-parent focus-root
                   :focus-scope focus-scope}))

  (local float ((FloatLayer {:name "canvas-float"
                             :depth-layer-step panel-depth-layer-step})
                ctx))
  (local self {:layout-root layout-root
               :build-context ctx
               :activity-slots {}
               :active-activity-slot-id nil
               :active-activity-slot nil
               :camera camera
               :projection nil
               :projection-version 0
               :viewport nil
               :float float
               :panel-restorers {}
               :scale-factor (or options.scale-factor default-scale-factor)
               :world-units-per-pixel default-world-scale
               :half-width 1
               :half-height 1
               :focus-manager focus-manager
               :focus-scope focus-scope
               :interaction-surface :canvas
               :default-panel-location "float"})

  (fn make-slot-focus-scope [activity-id]
    (and focus-manager
         (focus-manager:create-scope {:name (.. "canvas:" activity-id)
                                      :directional-traversal-boundary? true})))

  (fn make-slot-pointer-target [slot]
    {:interaction-surface :canvas
     :activity-slot slot
     :canvas-target-kind nil
     :screen-pos-ray (fn [_target pos opts]
                       (self:screen-pos-ray pos opts))})

  (fn make-slot-build-context [slot slot-layout-root]
    (local slot-focus-scope slot.focus-scope)
    (local slot-ctx
      (BuildContext {:theme (resolve-active-theme)
                     :quad-unlit? true
                     :clickables app.clickables
                     :hoverables app.hoverables
                     :touch-gesture-targets app.touch-gesture-targets
                     :system-cursors app.system-cursors
                     :icons options.icons
                     :states options.states
                     :layout-root slot-layout-root
                     :movables options.movables
                     :focus-manager focus-manager
                     :focus-parent focus-scope
                     :focus-scope slot-focus-scope}))
    (set slot-ctx.pointer-target slot.pointer-target)
    (set slot-ctx.panel-target self)
    (apply-active-theme slot-ctx)
    slot-ctx)

  (fn apply-active-theme-to-contexts [_canvas]
    (apply-active-theme self.build-context)
    (each [_ slot (pairs self.activity-slots)]
      (apply-active-theme slot.ctx))
    true)

  (set ctx.pointer-target self)
  (set ctx.panel-target self)
  (apply-active-theme ctx)
  (float.layout:set-root layout-root)

  (fn find-panel-metadata [element]
    (var found nil)
    (each [_ metadata (ipairs (or self.float.children []))]
      (when (and (not found)
                 (= (and metadata metadata.element) element))
        (set found metadata)))
    found)

  (fn unregister-panel-interactions [element]
    (when (and element app.movables)
      (app.movables:unregister element))
    (when (and element app.resizables)
      (app.resizables:unregister element)))

  (fn register-panel-interactions [metadata]
    (local element (and metadata metadata.element))
    (local layout (and element element.layout))
    (when (and element layout app.movables)
      (local target (self.float:ensure-movable-target metadata))
      (app.movables:register element {:target target
                                      :handle layout
                                      :key element
                                      :pointer-target self}))
    (when (and element layout app.resizables)
      (local min-size (resolve-min-size layout))
      (local target (self.float:ensure-resize-target metadata))
      (app.resizables:register element {:target target
                                        :handle layout
                                        :key element
                                        :min-size min-size
                                        :pointer-target self})))

  (fn add-panel-child [canvas opts]
    (local panel-opts (or opts {}))
    (local destination (or panel-opts.location panel-opts.layer :float))
    (when (or (= destination :tiles) (= destination "tiles"))
      (error "Canvas.add-panel-child only supports float panels"))
    (local builder (assert panel-opts.builder "Canvas.add-panel-child requires :builder"))
    (local builder-options {})
    (each [key value (pairs (or panel-opts.builder-options {}))]
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
          (canvas:remove-panel-child element))))
    (set builder-options.on-close handle-close)
    (set element (builder self.build-context builder-options))
    (local default-position (or (and camera camera.position) (glm.vec3 0 0 0)))
    (local metadata
      (self.float:attach-child element {:position (or panel-opts.position default-position)
                                        :rotation panel-opts.rotation
                                        :size panel-opts.size
                                        :depth-offset-index panel-opts.depth-offset-index}))
    (when metadata
      (set metadata.persistence (and panel-opts.persistence
                                     (clone-table panel-opts.persistence)))
      (register-panel-interactions metadata))
    element)

  (fn remove-panel-child [_canvas element]
    (local metadata (find-panel-metadata element))
    (when metadata
      (unregister-panel-interactions element)
      (self.float:remove-child element)
      true))

  (fn find-panel-persistence [_canvas element]
    (local metadata (find-panel-metadata element))
    (and metadata metadata.persistence))

  (fn register-panel-restorer [_canvas kind restorer owner]
    (assert (= (type kind) :string) "Canvas.register-panel-restorer requires string kind")
    (assert (= (type restorer) :function) "Canvas.register-panel-restorer requires function restorer")
    (set (. self.panel-restorers kind) {:restore restorer
                                        :owner owner})
    true)

  (fn unregister-panel-restorer [_canvas kind owner]
    (assert (= (type kind) :string) "Canvas.unregister-panel-restorer requires string kind")
    (local current (. self.panel-restorers kind))
    (when current
      (when (or (= owner nil)
                (= current.owner nil)
                (= current.owner owner))
        (set (. self.panel-restorers kind) nil)))
    true)

  (fn capture-panel-element-state [_canvas element]
    (local metadata (find-panel-metadata element))
    (if (not metadata)
        nil
        (do
          (local layout-state (capture-panel-layout-state metadata))
          (when layout-state
            {:layer "float"
             :position layout-state.position
             :rotation layout-state.rotation
             :size layout-state.size}))))

  (fn capture-state [_canvas]
    (local panels [])
    (each [_ metadata (ipairs (or self.float.children []))]
      (local persistence (and metadata metadata.persistence))
      (when persistence
        (local record (clone-table persistence))
        (local kind record.kind)
        (assert (= (type kind) :string)
                "Canvas.capture-state panel persistence requires string :kind")
        (local module-name record.restorer-module)
        (when (not (= module-name nil))
          (assert (= (type module-name) :string)
                  (.. "Canvas.capture-state panel persistence for kind "
                      kind
                      " requires string :restorer-module")))
        (local registered (and (. self.panel-restorers kind)
                               (. (. self.panel-restorers kind) :restore)))
        (assert (or registered (= (type module-name) :string))
                (.. "Canvas.capture-state panel kind has no restore strategy: "
                    kind))
        (local layout-state (capture-panel-layout-state metadata))
        (assert layout-state
                (.. "Canvas.capture-state missing layout for panel kind: " kind))
        (set record.layer "float")
        (set record.position layout-state.position)
        (set record.rotation layout-state.rotation)
        (set record.size layout-state.size)
        (table.insert panels record)))
    {:camera {:position (vec3->array camera.position)}
     :scale_factor self.scale-factor
     :panels panels})

  (fn resolve-panel-restorer [panel]
    (local kind panel.kind)
    (local registered-record (. self.panel-restorers kind))
    (local registered (and registered-record registered-record.restore))
    (if registered
        registered
        (do
          (local module-name panel.restorer-module)
          (assert (= (type module-name) :string)
                  (.. "Canvas.restore-state panel kind "
                      kind
                      " requires string :restorer-module or registered restorer"))
          (local (ok module-or-error) (pcall require module-name))
          (assert ok
                  (.. "Canvas.restore-state failed requiring panel restorer module "
                      module-name
                      ": "
                      (tostring module-or-error)))
          (local module module-or-error)
          (local restore (and module module.restore))
          (assert (= (type restore) :function)
                  (.. "Canvas.restore-state module "
                      module-name
                      " must export function :restore"))
          (fn [payload]
            (restore {:canvas self
                      :target self
                      :panel payload})))))

  (fn restore-shell-state [self state]
    (local payload (or state {}))
    (local camera-state (or payload.camera {}))
    (local (ok position) (pcall array->vec3 camera-state.position))
    (if (and ok (safe-vec3? position))
        (camera:set-position position)
        (when camera-state.position
          (logging.warn "[canvas] invalid persisted camera position; keeping current value")))
    (local scale-factor (or payload.scale_factor payload.scale-factor))
    (if (finite-number? scale-factor)
        (self:set-scale-factor scale-factor)
        (when (not (= scale-factor nil))
          (logging.warn "[canvas] invalid persisted scale factor; keeping current value")))
    true)

  (fn restore-state [_canvas state]
    (self:restore-shell-state state)
    (local payload (or state {}))
    (local panels (or payload.panels []))
    (assert (= (type panels) :table) "Canvas.restore-state requires :panels table")
    (each [_ panel (ipairs panels)]
      (assert (= (type panel) :table) "Canvas.restore-state panel entries must be tables")
      (local kind panel.kind)
      (assert (= (type kind) :string) "Canvas.restore-state panel kind must be a string")
      ((resolve-panel-restorer panel) panel))
    true)

  (fn get-view-matrix [_canvas]
    (camera:get-view-matrix))

  (fn get-lighting-view-state [_canvas]
    (LightingViewState.orthographic (glm.vec3 0.0 0.0 1.0)))

  (fn active-render-context []
    (if (and self.active-activity-slot
             self.active-activity-slot.visible?)
        self.active-activity-slot.ctx
        self.build-context))

  (fn get-render-contexts [_canvas]
    (local contexts [])
    (when (and self.active-activity-slot
               self.active-activity-slot.visible?)
      (table.insert contexts self.active-activity-slot.ctx))
    (table.insert contexts self.build-context)
    contexts)

  (fn get-triangle-vector [_canvas]
    (. (active-render-context) :triangle-vector))

  (fn get-triangle-batches [_canvas]
    (local render-ctx (active-render-context))
    (and render-ctx
         render-ctx.get-triangle-batches
         (render-ctx:get-triangle-batches)))

  (fn get-line-vector [_canvas]
    (. (active-render-context) :line-vector))

  (fn get-point-vector [_canvas]
    (. (active-render-context) :point-vector))

  (fn get-line-strips [_canvas]
    (. (active-render-context) :line-strips))

  (fn get-image-batches [_canvas]
    (. (active-render-context) :image-batches))

  (fn get-mesh-batches [_canvas]
    (local render-ctx (active-render-context))
    (and render-ctx
         render-ctx.get-mesh-batches
         (render-ctx:get-mesh-batches)))

  (fn get-instanced-color-mesh-batches [_canvas]
    (local render-ctx (active-render-context))
    (and render-ctx
         render-ctx.get-instanced-color-mesh-batches
         (render-ctx:get-instanced-color-mesh-batches)))

  (fn get-quad-draw-list [_canvas]
    (local render-ctx (active-render-context))
    (and render-ctx
         render-ctx.get-quad-draw-list
         (render-ctx:get-quad-draw-list)))

  (fn get-text-ssbo-draw-list [_canvas]
    (local render-ctx (active-render-context))
    (and render-ctx
         render-ctx.get-text-ssbo-draw-list
         (render-ctx:get-text-ssbo-draw-list)))

  (fn ensure-activity-slot [_canvas activity-id]
    (assert (= (type activity-id) :string)
            "Canvas.ensure-activity-slot requires string activity id")
    (assert (> (# activity-id) 0)
            "Canvas.ensure-activity-slot requires non-empty activity id")
    (local existing (. self.activity-slots activity-id))
    (if existing
        existing
        (do
          (local slot-layout-root (LayoutRoot))
          (local slot
            {:activity-id activity-id
             :surface :canvas
             :ctx nil
             :layout-root slot-layout-root
             :focus-scope (make-slot-focus-scope activity-id)
             :pointer-target nil
             :root nil
             :visible? false
             :interactive? false})
          (set slot.pointer-target (make-slot-pointer-target slot))
          (set slot.ctx (make-slot-build-context slot slot-layout-root))
          (set slot.set-canvas-target-kind!
               (fn [slot-self target-kind]
                 (set slot-self.pointer-target.canvas-target-kind target-kind)
                 slot-self))
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
                 true))
          (slot:deactivate)
          (set (. self.activity-slots activity-id) slot)
          slot)))

  (fn activity-slot [_canvas activity-id]
    (assert (= (type activity-id) :string)
            "Canvas.activity-slot requires string activity id")
    (. self.activity-slots activity-id))

  (fn activate-activity-slot [canvas activity-id]
    (local slot (canvas:ensure-activity-slot activity-id))
    (when (and self.active-activity-slot
               (not (= self.active-activity-slot slot)))
      (self.active-activity-slot:deactivate))
    (slot:activate)
    (set self.active-activity-slot-id activity-id)
    (set self.active-activity-slot slot)
    slot)

  (fn deactivate-activity-slot [_canvas activity-id]
    (local slot (activity-slot self activity-id))
    (when slot
      (slot:deactivate)
      (when (= self.active-activity-slot slot)
        (set self.active-activity-slot nil)
        (set self.active-activity-slot-id nil)))
    slot)

  (fn drop-activity-slot [_canvas activity-id]
    (local slot (activity-slot self activity-id))
    (when slot
      (slot:drop)
      (when (= self.active-activity-slot slot)
        (set self.active-activity-slot nil)
        (set self.active-activity-slot-id nil))
      (set (. self.activity-slots activity-id) nil))
    true)

  (fn screen-pos-ray [_canvas pos opts]
    (local ray-opts (or opts {}))
    (local viewport (viewport-utils.to-table (or ray-opts.viewport self.viewport app.viewport)))
    (local view (or ray-opts.view (self:get-view-matrix)))
    (local projection (or ray-opts.projection self.projection))
    (fn assert-finite-vec3 [vec label]
      (when (not (safe-vec3? vec))
        (error (.. "Canvas.screen-pos-ray produced non-finite " label))))
    (assert view "Canvas.screen-pos-ray requires a view matrix")
    (assert projection "Canvas.screen-pos-ray requires a projection matrix")
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

  (fn update-projection [_canvas viewport]
    (local vp (viewport-utils.to-table (or viewport self.viewport {:x 0 :y 0 :width 1 :height 1})))
    (set self.viewport vp)
    (local adjusted-scale (* default-world-scale self.scale-factor))
    (set self.world-units-per-pixel adjusted-scale)
    (local safe-width (math.max vp.width 1))
    (local safe-height (math.max vp.height 1))
    (set self.half-width (math.max 0.001 (* 0.5 safe-width adjusted-scale)))
    (set self.half-height (math.max 0.001 (* 0.5 safe-height adjusted-scale)))
    (if glm.ortho
        (set self.projection
             (glm.ortho (- self.half-width)
                        self.half-width
                        (- self.half-height)
                        self.half-height
                        -1000.0
                        1000.0))
        (set self.projection (glm.mat4 1)))
    (set self.projection-version (+ (or self.projection-version 0) 1)))

  (fn set-scale-factor [_canvas scale-factor]
    (assert (finite-number? scale-factor) "Canvas.set-scale-factor requires finite number")
    (set self.scale-factor scale-factor)
    (self:update-projection app.viewport))

  (fn reset-projection [_canvas]
    (self:update-projection app.viewport))

  (fn on-viewport-changed [_canvas viewport]
    (self:update-projection viewport))

  (fn update [_canvas]
    (self.layout-root:update)
    (when (and self.active-activity-slot
               self.active-activity-slot.layout-root)
      (self.active-activity-slot.layout-root:update)))

  (fn drop [_canvas]
    (local activity-slot-ids [])
    (each [activity-id _slot (pairs self.activity-slots)]
      (table.insert activity-slot-ids activity-id))
    (each [_ activity-id (ipairs activity-slot-ids)]
      (drop-activity-slot self activity-id))
    (each [_ metadata (ipairs (or self.float.children []))]
      (local element (and metadata metadata.element))
      (when element
        (unregister-panel-interactions element)))
    (when self.float
      (self.float:drop)
      (set self.float nil))
    (when (and self.focus-manager self.focus-scope)
      (self.focus-manager:detach self.focus-scope)
      (set self.focus-scope nil)))

  (set self.get-view-matrix get-view-matrix)
  (set self.get-lighting-view-state get-lighting-view-state)
  (set self.get-triangle-vector get-triangle-vector)
  (set self.get-triangle-batches get-triangle-batches)
  (set self.get-line-vector get-line-vector)
  (set self.get-point-vector get-point-vector)
  (set self.get-line-strips get-line-strips)
  (set self.get-image-batches get-image-batches)
  (set self.get-mesh-batches get-mesh-batches)
  (set self.get-instanced-color-mesh-batches get-instanced-color-mesh-batches)
  (set self.get-quad-draw-list get-quad-draw-list)
  (set self.get-text-ssbo-draw-list get-text-ssbo-draw-list)
  (set self.get-render-contexts get-render-contexts)
  (set self.apply-active-theme-to-contexts apply-active-theme-to-contexts)
  (set self.ensure-activity-slot ensure-activity-slot)
  (set self.activity-slot activity-slot)
  (set self.activate-activity-slot activate-activity-slot)
  (set self.deactivate-activity-slot deactivate-activity-slot)
  (set self.drop-activity-slot drop-activity-slot)
  (set self.add-panel-child add-panel-child)
  (set self.remove-panel-child remove-panel-child)
  (set self.find-panel-persistence find-panel-persistence)
  (set self.register-panel-restorer register-panel-restorer)
  (set self.unregister-panel-restorer unregister-panel-restorer)
  (set self.capture-panel-element-state capture-panel-element-state)
  (set self.capture-state capture-state)
  (set self.restore-state restore-state)
  (set self.restore-shell-state restore-shell-state)
  (set self.screen-pos-ray screen-pos-ray)
  (set self.update-projection update-projection)
  (set self.set-scale-factor set-scale-factor)
  (set self.reset-projection reset-projection)
  (set self.on-viewport-changed on-viewport-changed)
  (set self.update update)
  (set self.drop drop)

  (self:reset-projection)
  self)

Canvas
