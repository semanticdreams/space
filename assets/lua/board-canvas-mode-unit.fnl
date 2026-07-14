(global app (or app {}))

(local fs (require :fs))
(local runtime (require :runtime))
(local glm (require :glm))
(local CanvasModes (require :canvas-modes))
(local {:Board Board} (require :board/core))
(local BoardView (require :board/view))
(local BuiltinStringEntity (require :board/builtin-string-entity))

(local owner {})

(fn board-mode-owned-paths []
  (local lua-root (fs.join-path runtime.assets-path "lua"))
  (local board-root (fs.join-path lua-root "board"))
  [(fs.join-path lua-root "board-canvas-mode-unit.fnl")
   board-root])

(fn ensure-board-state [world-runtime]
  (set world-runtime.board-state (or world-runtime.board-state {}))
  world-runtime.board-state)

(fn screen-world-position [event]
  (local canvas (assert app.canvas "Board screen-world-position requires app.canvas"))
  (assert event "Board screen-world-position requires pointer event")
  (local pointer (or event.screen
                     (and event.x event.y event)))
  (local ray
    (or event.ray
        (do
          (assert pointer
                  "Board screen-world-position requires event.ray, event.screen, or a pointer {x y}")
          (canvas:screen-pos-ray pointer))))
  (assert (and ray ray.origin ray.direction)
          "Board screen-world-position requires a ray with origin and direction")
  (local dz ray.direction.z)
  (assert (and dz (not (= dz 0)))
          "Board screen-world-position ray must intersect z=0 plane")
  (local t (/ (- 0 ray.origin.z) dz))
  (local point (+ ray.origin (* ray.direction t)))
  (glm.vec3 point.x point.y 0))

(fn create-board-view! []
  (local world-runtime (assert app.active-world-runtime
                               "Board canvas mode requires app.active-world-runtime"))
  (local canvas (assert world-runtime.canvas
                        "Board canvas mode requires runtime.canvas"))
  (when world-runtime.board-view
    (world-runtime.board-view:drop)
    (set world-runtime.board-view nil))
  (BuiltinStringEntity.register owner)
  (local board (Board {}))
  (local selector (and world-runtime world-runtime.object-selector))
  (local view (BoardView {:board board
                           :canvas canvas
                           :ctx canvas.build-context
                           :selector selector}))
  (set world-runtime.board board)
  (set world-runtime.board-view view)
  (set app.board board)
  (set app.board-view view)
  (local (ok err)
    (pcall (fn []
             (board:restore-state (ensure-board-state world-runtime)))))
  (when (not ok)
    (view:drop)
    (set world-runtime.board nil)
    (set world-runtime.board-view nil)
    (set app.board nil)
    (set app.board-view nil)
    (error err))
  view)

(fn capture-board-state! []
  (local world-runtime app.active-world-runtime)
  (local view (and world-runtime world-runtime.board-view))
  (when (and world-runtime view)
    (set world-runtime.board-state (view:capture-state)))
  (and world-runtime world-runtime.board-state))

(fn drop-board-view! []
  (capture-board-state!)
  (local world-runtime app.active-world-runtime)
  (local view (or (and world-runtime world-runtime.board-view)
                  app.board-view))
  (when view
    (view:drop))
  (when world-runtime
    (set world-runtime.board nil)
    (set world-runtime.board-view nil))
  (set app.board nil)
  (set app.board-view nil)
  true)

(fn board-mode-update [payload]
  (local view (and payload payload.runtime payload.runtime.board-view))
  (when view
    (view:update (and payload payload.delta)))
  nil)

(fn board-root-actions [context]
  (local root-event (and context context.event))
  [{:name "Create String Entity"
    :icon "note_add"
    :fn (fn [_button event]
           (local view (assert app.board-view "Create String Entity requires app.board-view"))
           (view:add-string-entity {:position (screen-world-position (or root-event event))}))}])

(fn connectable? [item]
  (and item item.subject-key
       (not (= (tostring item.subject-key) ""))))

(fn delete-selection []
  (local view app.board-view)
  (and view (> (view:remove-selected-items) 0)))

(fn board-selection-actions [context]
  (local view (or (and context context.board context.board.view)
                  app.board-view))
  (local selected (or (and view view.selected-items) []))
  (local actions [])
  (when (> (length selected) 0)
    (table.insert actions
                  {:name "Delete Selected"
                   :icon "delete"
                   :variant {:action :danger}
                   :fn (fn [_button _event]
                         (view:remove-selected-items))}))
  (when (and (= (length selected) 2)
             (connectable? (. selected 1))
             (connectable? (. selected 2)))
    (let [source (. selected 1)
          target (. selected 2)]
      (table.insert actions
                    {:name "Connect Items"
                     :icon "link"
                     :fn (fn [_button _event]
                           (view:connect-items source target))})))
  actions)

(fn enrich-board-context! [context]
  (local view (or app.board-view
                  (and context context.board context.board.view)))
  (set context.board {:board app.board
                      :view app.board-view
                      :selected-items (if view view.selected-items [])})
  context)

(fn board-target-enabled? [target]
  (local target-kind (and target target.canvas-target-kind))
  (or (= target-kind nil)
      (= target-kind :board)))

(fn activate-mode! [ctx]
  (ctx:defer-cleanup! drop-board-view!)
  (local view (create-board-view!))
  (ctx:set-root-actions! board-root-actions)
  (ctx:set-selection-actions! board-selection-actions)
  (ctx:set-delete-selection! delete-selection)
  (ctx:set-command-hints-provider! (fn [_payload] []))
  (ctx:set-context-enricher! enrich-board-context!)
  (ctx:set-target-enabled! board-target-enabled?)
  (ctx:set-update! board-mode-update)
  {:mode-id "board"
   :board-view view})

(fn deactivate-mode! [_ctx _session]
  (drop-board-view!))

(fn snapshot-board-canvas-mode! []
  {:active? (= (CanvasModes.active-mode-id) "board")
   :board-state (capture-board-state!)})

(fn restore-state-arg [first _session maybe-state]
  (if (and first (. first :mode))
      maybe-state
      first))

(fn restore-board-canvas-mode! [first session maybe-state]
  (local state (restore-state-arg first session maybe-state))
  (when (and app.active-world-runtime state state.board-state)
    (set app.active-world-runtime.board-state state.board-state))
  (when (and state state.active?)
    (if (and state.board-state
             (= (CanvasModes.active-mode-id) "board")
             app.active-world-runtime
             app.active-world-runtime.board)
        (app.active-world-runtime.board:restore-state state.board-state)
        (CanvasModes.activate-mode "board")))
  true)

(fn mode-registered? [mode-id]
  (local (ok _resolved) (pcall CanvasModes.resolve mode-id))
  ok)

(fn load-board-canvas-mode! []
  (BuiltinStringEntity.register owner)
  (when (not (mode-registered? "board"))
    (CanvasModes.register-mode
      {:id "board"
       :label "Board"
       :icon "dashboard_customize"
       :button-name "board-canvas-mode"
       :show-in-sidebar? true
       :activate activate-mode!
       :deactivate deactivate-mode!
       :snapshot snapshot-board-canvas-mode!
       :restore restore-board-canvas-mode!}))
  true)

(fn unload-board-canvas-mode! []
  (local registered? (mode-registered? "board"))
  (local active? (and registered?
                      (= (CanvasModes.active-mode-id) "board")))
  (when active?
    (CanvasModes.deactivate-active-mode))
  (when registered?
    (CanvasModes.unregister-mode "board"))
  (BuiltinStringEntity.unregister owner)
  true)

{:board-mode-owned-paths board-mode-owned-paths
 :load-board-canvas-mode! load-board-canvas-mode!
 :unload-board-canvas-mode! unload-board-canvas-mode!
 :snapshot-board-canvas-mode! snapshot-board-canvas-mode!
 :restore-board-canvas-mode! restore-board-canvas-mode!}
