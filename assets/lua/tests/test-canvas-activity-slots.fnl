(local glm (require :glm))
(local Main (require :main))
(local Canvas (require :canvas))
(local Camera (require :camera))
(local ObjectSelector (require :object-selector))
(local Signal (require :signal))
(local {: Layout} (require :layout))
(local {: FocusManager} (require :focus))

(local tests [])

(fn make-canvas []
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local canvas (Canvas {:camera camera}))
  {:camera camera
   :canvas canvas})

(fn make-focused-canvas []
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager))
  (local canvas (Canvas {:camera camera
                         :focus-manager focus-manager}))
  {:camera camera
   :canvas canvas
   :focus-manager focus-manager})

(fn drop-fixture [fixture]
  (fixture.canvas:drop)
  (when fixture.focus-manager
    (fixture.focus-manager:drop))
  (fixture.camera:drop))

(fn with-restored-app-fields [keys f]
  (local snapshot {})
  (each [_ key (ipairs keys)]
    (set (. snapshot key) (. app key)))
  (local (ok result) (pcall f))
  (each [_ key (ipairs keys)]
    (set (. app key) (. snapshot key)))
  (if ok
      result
      (error result)))

(fn ensure-activity-slot-creates-isolated-context []
  (local fixture (make-canvas))
  (local canvas fixture.canvas)
  (local graph-slot (canvas:ensure-activity-slot "graph"))
  (assert (= graph-slot (canvas:ensure-activity-slot "graph"))
          "Canvas should retain one slot per activity id")
  (graph-slot:set-canvas-target-kind! :graph-view)
  (assert (= graph-slot.pointer-target.canvas-target-kind :graph-view)
          "Activity slots should expose canvas target kind on their pointer target")
  (assert (not (= graph-slot.ctx canvas.build-context))
          "Activity slot should not share the canvas default build context")
  (assert (not (= graph-slot.layout-root canvas.layout-root))
          "Activity slot should not share the canvas default layout root")
  (assert (= graph-slot.ctx.triangle-vector graph-slot.ctx.triangle-vector))
  (assert (= (canvas:get-triangle-vector) canvas.build-context.triangle-vector)
          "Inactive activity slots should not replace the render context")
  (assert (not graph-slot.visible?))
  (assert (not graph-slot.interactive?))
  (drop-fixture fixture))

(fn active-activity-slot-controls-render-context []
  (local fixture (make-canvas))
  (local canvas fixture.canvas)
  (local graph-slot (canvas:ensure-activity-slot "graph"))
  (local drawing-slot (canvas:ensure-activity-slot "drawing"))
  (canvas:activate-activity-slot "graph")
  (local render-contexts (canvas:get-render-contexts))
  (assert (= (. render-contexts 1) graph-slot.ctx)
          "Active activity context should render before surface context")
  (assert (= (. render-contexts 2) canvas.build-context)
          "Canvas surface context should still render while an activity is active")
  (assert graph-slot.visible?)
  (assert graph-slot.interactive?)
  (assert (= (canvas:get-triangle-vector) graph-slot.ctx.triangle-vector)
          "Active slot triangle data should be exposed for rendering")
  (assert (= (canvas:get-line-vector) graph-slot.ctx.line-vector)
          "Active slot line data should be exposed for rendering")
  (assert (= (canvas:get-point-vector) graph-slot.ctx.point-vector)
          "Active slot point data should be exposed for rendering")
  (assert (= (canvas:get-line-strips) graph-slot.ctx.line-strips)
          "Active slot line strips should be exposed for rendering")
  (assert (= (canvas:get-image-batches) graph-slot.ctx.image-batches)
          "Active slot image batches should be exposed for rendering")
  (assert (= (canvas:get-mesh-batches) (graph-slot.ctx:get-mesh-batches))
          "Active slot mesh batches should be exposed for rendering")
  (assert (= (canvas:get-instanced-color-mesh-batches)
             (graph-slot.ctx:get-instanced-color-mesh-batches))
          "Active slot instanced color mesh batches should be exposed for rendering")
  (canvas:activate-activity-slot "drawing")
  (assert (not graph-slot.visible?)
          "Activating a new slot should hide the previous slot")
  (assert drawing-slot.visible?)
  (assert (= (canvas:get-triangle-vector) drawing-slot.ctx.triangle-vector)
          "Switching slots should switch render data immediately")
  (canvas:deactivate-activity-slot "drawing")
  (assert (= (canvas:get-triangle-vector) canvas.build-context.triangle-vector)
          "Deactivating the active slot should stop exposing activity draw data")
  (drop-fixture fixture))

(fn drop-activity-slot-removes-retained-content []
  (local fixture (make-canvas))
  (local canvas fixture.canvas)
  (local slot (canvas:activate-activity-slot "graph"))
  (var dropped? false)
  (set slot.root {:drop (fn [_self]
                          (set dropped? true))})
  (canvas:drop-activity-slot "graph")
  (assert dropped?
          "Dropping an activity slot should drop its retained root")
  (assert (= (canvas:activity-slot "graph") nil))
  (assert (= canvas.active-activity-slot nil))
  (assert (= (canvas:get-triangle-vector) canvas.build-context.triangle-vector))
  (drop-fixture fixture))

(fn inactive-activity-slot-rejects-pointer-targets []
  (with-restored-app-fields
    [:canvas
     :canvas-controls
     :first-person-controls
     :active-interaction-surface
     :active-pointer-controls
     :preferred-interaction-surface
     :scene-interactive?
     :canvas-interactive?
     :canvas-surface-interactive?
     :canvas-visible?
     :activity-target-enabled?
     :pointer-target-enabled?]
    (fn []
      (Main.install-app-shell!)
      (local fixture (make-canvas))
      (local canvas fixture.canvas)
      (set app.canvas canvas)
      (set app.canvas-interactive? true)
      (set app.activity-target-enabled? nil)
      (local graph-slot (canvas:ensure-activity-slot "graph"))
      (local drawing-slot (canvas:ensure-activity-slot "drawing"))
      (assert (not (app.pointer-target-enabled? graph-slot.pointer-target))
              "Inactive activity slot pointer target should be rejected")
      (canvas:activate-activity-slot "graph")
      (assert (app.pointer-target-enabled? graph-slot.pointer-target)
              "Active activity slot pointer target should be enabled")
      (canvas:activate-activity-slot "drawing")
      (assert (not (app.pointer-target-enabled? graph-slot.pointer-target))
              "Previously active activity slot pointer target should be rejected after switch")
      (assert (app.pointer-target-enabled? drawing-slot.pointer-target))
      (canvas:deactivate-activity-slot "drawing")
      (assert (not (app.pointer-target-enabled? drawing-slot.pointer-target)))
      (drop-fixture fixture))))

(fn object-selector-filters-inactive-activity-selectables []
  (with-restored-app-fields
    [:canvas
     :canvas-controls
     :first-person-controls
     :active-interaction-surface
     :active-pointer-controls
     :preferred-interaction-surface
     :scene-interactive?
     :canvas-interactive?
     :canvas-surface-interactive?
     :canvas-visible?
     :activity-target-enabled?
     :pointer-target-enabled?]
    (fn []
      (Main.install-app-shell!)
      (local fixture (make-canvas))
      (local canvas fixture.canvas)
      (set app.canvas canvas)
      (set app.canvas-interactive? true)
      (set app.activity-target-enabled? nil)
      (local graph-slot (canvas:ensure-activity-slot "graph"))
      (local drawing-slot (canvas:ensure-activity-slot "drawing"))
      (local box {:changed (Signal)
                  :exited (Signal)
                  :active? (fn [_self] false)
                  :on-mouse-button (fn [_self _payload] nil)
                  :on-mouse-motion (fn [_self _payload] nil)
                  :on-key-down (fn [_self _payload] nil)
                  :cancel (fn [_self] nil)
                  :drop (fn [_self] nil)})
      (local selector
        (ObjectSelector {:box_selector box
                         :project (fn [position _opts] position)}))
      (local graph-selectable {:position (glm.vec3 10 10 0)
                               :pointer-target graph-slot.pointer-target})
      (local drawing-selectable {:position (glm.vec3 10 10 0)
                                 :pointer-target drawing-slot.pointer-target})
      (selector:add-selectables [graph-selectable drawing-selectable])
      (canvas:activate-activity-slot "graph")
      (box.changed:emit {:p1 {:x 0 :y 0}
                         :p2 {:x 20 :y 20}})
      (assert (= (length selector.selected) 1)
              "Selector should ignore inactive drawing slot selectable")
      (assert (= (. selector.selected 1) graph-selectable)
              "Selector should keep the active graph selectable")
      (canvas:activate-activity-slot "drawing")
      (box.changed:emit {:p1 {:x 0 :y 0}
                         :p2 {:x 20 :y 20}})
      (assert (= (length selector.selected) 1)
              "Selector should ignore inactive graph slot selectable after switch")
      (assert (= (. selector.selected 1) drawing-selectable)
              "Selector should keep the active drawing selectable")
      (selector:drop)
      (drop-fixture fixture))))

(fn activity-slot-panel-children-use-slot-context []
  (local fixture (make-canvas))
  (local canvas fixture.canvas)
  (local slot (canvas:activate-activity-slot "graph"))
  (var built-ctx nil)
  (var dropped? false)
  (local element
    (slot:add-panel-child
      {:builder (fn [ctx]
                  (set built-ctx ctx)
                  {:layout (Layout {:name "slot-panel"})
                   :drop (fn [_self]
                           (set dropped? true))})
       :persistence {:kind "slot-panel"}}))
  (assert (= built-ctx slot.ctx)
          "Activity slot panels should build with the slot context")
  (assert (= built-ctx.pointer-target slot.pointer-target)
          "Activity slot panels should route input through the slot pointer target")
  (assert (= built-ctx.panel-target slot)
          "Activity slot panels should expose the slot as their panel target")
  (assert (= (length slot.float.children) 1)
          "Activity slot panel should mount in the slot float layer")
  (assert (= (length canvas.float.children) 0)
          "Activity slot panel should not mount in the canvas default float layer")
  (local persistence (slot:find-panel-persistence element))
  (assert (= persistence.kind "slot-panel"))
  (canvas:activate-activity-slot "drawing")
  (local contexts (canvas:get-render-contexts))
  (assert (not (= (. contexts 1) slot.ctx))
          "Inactive activity slot panel context should not be rendered")
  (assert (not slot.visible?)
          "Switching activities should hide the prior slot")
  (slot:remove-panel-child element)
  (assert dropped?
          "Removing an activity slot panel should drop it")
  (drop-fixture fixture))

(fn activity-slot-focus-scope-follows-activation []
  (local fixture (make-focused-canvas))
  (local canvas fixture.canvas)
  (local slot (canvas:ensure-activity-slot "graph"))
  (assert slot.focus-scope
          "Canvas activity slot should own a focus scope when canvas focus is available")
  (assert (= slot.focus-scope.parent nil)
          "Inactive activity slot focus scope should be detached")
  (canvas:activate-activity-slot "graph")
  (assert (= slot.focus-scope.parent canvas.focus-scope)
          "Active activity slot focus scope should attach under the canvas focus scope")
  (canvas:deactivate-activity-slot "graph")
  (assert (= slot.focus-scope.parent nil)
          "Deactivated activity slot focus scope should detach from traversal")
  (drop-fixture fixture))

(fn retained-activity-slot-themes-update []
  (with-restored-app-fields
    [:themes]
    (fn []
      (local light-theme {:name :light})
      (local dark-theme {:name :dark})
      (var active-theme light-theme)
      (set app.themes {:get-active-theme (fn [] active-theme)})
      (local fixture (make-canvas))
      (local canvas fixture.canvas)
      (local slot (canvas:ensure-activity-slot "graph"))
      (assert (= canvas.build-context.theme light-theme))
      (assert (= slot.ctx.theme light-theme))
      (set active-theme dark-theme)
      (canvas:apply-active-theme-to-contexts)
      (assert (= canvas.build-context.theme dark-theme)
              "Canvas default context should receive updated theme")
      (assert (= slot.ctx.theme dark-theme)
              "Retained activity slot context should receive updated theme")
      (drop-fixture fixture))))

(table.insert tests {:name "Canvas activity slots create isolated contexts"
                     :fn ensure-activity-slot-creates-isolated-context})
(table.insert tests {:name "Canvas active activity slot controls render context"
                     :fn active-activity-slot-controls-render-context})
(table.insert tests {:name "Canvas activity slot drop removes retained content"
                     :fn drop-activity-slot-removes-retained-content})
(table.insert tests {:name "Canvas inactive activity slots reject pointer targets"
                      :fn inactive-activity-slot-rejects-pointer-targets})
(table.insert tests {:name "Object selector filters inactive activity selectables"
                     :fn object-selector-filters-inactive-activity-selectables})
(table.insert tests {:name "Canvas activity slot panel children use slot context"
                     :fn activity-slot-panel-children-use-slot-context})
(table.insert tests {:name "Canvas activity slot focus scope follows activation"
                      :fn activity-slot-focus-scope-follows-activation})
(table.insert tests {:name "Canvas retained activity slot themes update"
                     :fn retained-activity-slot-themes-update})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "canvas-activity-slots"
                       :tests tests})))

{:name "canvas-activity-slots"
 :tests tests
 :main main}
