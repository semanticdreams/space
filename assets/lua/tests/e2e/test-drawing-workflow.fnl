(local Harness (require :tests.e2e.harness))
(local fs (require :fs))
(local glm (require :glm))
(local viewport-utils (require :viewport-utils))
(local Main (require :main))
(local HomeWorld (require :home-world))
(local Signal (require :signal))

(local CTRL-MOD 64)
(local KEY_DELETE 127)
(local KEY_Z_LOWER (string.byte "z"))

(var temp-counter 0)
(var click-timestamp 0)
(local temp-root "/tmp/space/tests/e2e/drawing-workflow")

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "drawing-workflow-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (if ok
      result
      (error result)))

(fn codepoints->text [codepoints]
  (local parts [])
  (each [_ codepoint (ipairs (or codepoints []))]
    (table.insert parts (utf8.char codepoint)))
  (table.concat parts))

(fn clickable-label [obj]
  (if (and obj obj.text obj.text.get-codepoints)
      (codepoints->text (obj.text:get-codepoints))
      nil))

(fn find-clickable-by-label [label]
  (var resolved nil)
  (each [_ obj (ipairs (or (and app.clickables app.clickables.left-click-objects) []))]
    (when (and (not resolved)
               (= (clickable-label obj) label))
      (set resolved obj)))
  resolved)

(fn find-text-input []
  (var resolved nil)
  (each [_ obj (ipairs (or (and app.clickables app.clickables.left-click-objects) []))]
    (when (and (not resolved)
               obj
               obj.get-text
               obj.set-text)
      (set resolved obj)))
  resolved)

(fn next-click-timestamp []
  (set click-timestamp (+ click-timestamp 1))
  click-timestamp)

(fn project-to-screen [position target]
  (assert (and glm glm.project) "drawing workflow e2e requires glm.project")
  (local viewport (viewport-utils.to-table app.viewport))
  (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
  (local view (target:get-view-matrix))
  (local projection target.projection)
  (local projected (glm.project position view projection viewport-vec))
  (assert projected "glm.project returned nil")
  {:x projected.x
   :y (- (+ viewport.height viewport.y) projected.y)})

(fn layout-screen-point [target layout]
  (local size (or layout.size layout.measure (glm.vec3 0 0 0)))
  (local rotation (or layout.rotation (glm.quat 1 0 0 0)))
  (local offset (glm.vec3 (/ size.x 2)
                          (/ size.y 2)
                          0))
  (local world-pos (+ layout.position
                      (rotation:rotate offset)))
  (project-to-screen world-pos target))

(fn canvas-screen-point [point]
  (project-to-screen point app.canvas))

(fn apply-runtime-to-app [world runtime hud]
  (local entry {:id world.id
                :world world})
  (set app.hud hud)
  (set app.focus hud.__e2e_focus_manager)
  (assert (and Main Main.install-app-shell!)
          "drawing workflow e2e requires Main.install-app-shell!")
  (Main.install-app-shell!)
  (assert app.bind-active-world-runtime
          "drawing workflow e2e requires app.bind-active-world-runtime")
  (app.bind-active-world-runtime entry runtime)
  (assert app.set-active-interaction-surface
          "drawing workflow e2e requires app.set-active-interaction-surface")
  (app.set-active-interaction-surface :canvas)
  (when app.hud
    (app.hud:update)))

(fn active-state []
  (local state (and app.states (app.states:active-state)))
  (assert state "drawing workflow e2e requires active state")
  state)

(fn refresh-world [env]
  (env.world:update 0 {})
  (when app.scene
    (app.scene:update))
  (when app.canvas
    (app.canvas:update))
  (when app.hud
    (app.hud:update)))

(fn click-at [env point]
  (local state (active-state))
  (local timestamp (next-click-timestamp))
  (state.on-mouse-button-down {:button 1
                               :x point.x
                               :y point.y
                               :timestamp timestamp})
  (state.on-mouse-button-up {:button 1
                             :x point.x
                             :y point.y
                             :timestamp timestamp})
  (refresh-world env))

(fn click-button [env label]
  (refresh-world env)
  (local button (assert (find-clickable-by-label label)
                        (.. "drawing workflow e2e missing button: " label)))
  (click-at env (layout-screen-point app.hud button.layout))
  button)

(fn focus-rename-input [env]
  (refresh-world env)
  (local input (assert (find-text-input)
                       "drawing workflow e2e missing rename input"))
  (click-at env (layout-screen-point app.hud input.layout))
  (local focused-input (assert (find-text-input)
                               "drawing workflow e2e lost rename input after focus"))
  (assert focused-input.focused? "drawing workflow e2e expected focused rename input")
  focused-input)

(fn send-key-down [env key mod]
  (local state (active-state))
  (state.on-key-down {:key key
                      :mod (or mod 0)})
  (refresh-world env))

(fn blur-input [env]
  (when (and app.focus app.focus.clear-focus)
    (app.focus:clear-focus))
  (refresh-world env))

(fn drag-on-canvas [env start finish]
  (local state (active-state))
  (local start-point (canvas-screen-point start))
  (local finish-point (canvas-screen-point finish))
  (state.on-mouse-button-down {:button 1
                               :x start-point.x
                               :y start-point.y
                               :timestamp (next-click-timestamp)})
  (state.on-mouse-motion {:x finish-point.x
                          :y finish-point.y})
  (state.on-mouse-button-up {:button 1
                             :x finish-point.x
                             :y finish-point.y
                             :timestamp (next-click-timestamp)})
  (refresh-world env))

(fn active-layer []
  (and app.drawing-controller
       (app.drawing-controller:active-layer)))

(fn object-count []
  (local layer (active-layer))
  (length (or (and layer layer.objects) [])))

(fn triangle-vector-length []
  (local vector
    (and app.canvas
         app.canvas.build-context
         (. app.canvas.build-context :triangle-vector)))
  (and vector (vector:length)))

(fn with-home-world [ctx run-fn]
  (with-temp-dir
    (fn [dir]
      (local hud (Harness.make-hud-target {:width ctx.width
                                           :height ctx.height}))
      (local focus-manager hud.__e2e_focus_manager)
      (var active-world-entry nil)
      (local runtime-context {:hud hud
                              :focus-manager focus-manager
                              :focus-root (focus-manager:get-root-scope)
                              :icons app.icons
                              :states app.states
                              :movables app.movables})
      (local world-manager-stub {:changed (Signal)
                                 :active-world (fn [_self] active-world-entry)
                                 :list-tabs (fn [_self] [])})
      (local world (HomeWorld {:id "e2e-world"
                               :name "home"
                               :type "home"
                               :dir dir
                               :graph-world-manager world-manager-stub
                               :asset-path-resolver (fn [path]
                                                      (app.engine:get-asset-path path))}))
      (local previous {:hud app.hud
                       :focus app.focus
                       :scene app.scene
                       :canvas app.canvas
                       :projection app.projection
                       :camera app.camera
                       :first-person-controls app.first-person-controls
                       :canvas-controls app.canvas-controls
                       :graph app.graph
                       :graph-view app.graph-view
                       :drawing-controller app.drawing-controller
                       :drawing-render app.drawing-render
                       :pointer-target-enabled? app.pointer-target-enabled?
                       :mark-active-world-hud-dirty app.mark-active-world-hud-dirty
                       :reset-projection app.reset-projection
                       :set-active-interaction-surface app.set-active-interaction-surface
                       :set-active-canvas-feature app.set-active-canvas-feature
                       :bind-active-world-runtime app.bind-active-world-runtime
                       :world-manager app.world-manager
                       :active-world-entry app.active-world-entry
                       :active-world-runtime app.active-world-runtime
                       :preferred-interaction-surface app.preferred-interaction-surface
                       :active-interaction-surface app.active-interaction-surface
                       :active-canvas-feature app.active-canvas-feature
                       :canvas-shell-changed app.canvas-shell-changed
                       :canvas-visible? app.canvas-visible?
                       :scene-interactive? app.scene-interactive?
                       :canvas-interactive? app.canvas-interactive?
                       :active-pointer-controls app.active-pointer-controls
                       :object-selector app.object-selector
                       :layout-root app.layout-root})
      (var ok false)
      (var result nil)
      (var err nil)
      (var stage "boot")
      (local (run-ok run-result)
        (pcall
          (fn []
            (set app.hud hud)
            (set app.focus focus-manager)
            (set app.world-manager world-manager-stub)
            (world:activate runtime-context)
            (local runtime (assert (world:get-runtime)
                                   "drawing workflow e2e expected active runtime"))
            (set active-world-entry {:id world.id
                                     :world world})
            (apply-runtime-to-app world runtime hud)
            (set click-timestamp 0)
            (set stage "run")
            (set result (run-fn {:world world
                                 :hud hud
                                 :runtime runtime
                                 :runtime-context runtime-context
                                 :set-stage (fn [value]
                                              (set stage value))}))
            (set ok true))))
      (when (not run-ok)
        (set err (.. "[stage " stage "] " run-result)))
      (when world
        (world:drop runtime-context "e2e-drawing-workflow"))
      (Harness.cleanup-target hud)
      (each [key value (pairs previous)]
        (set (. app key) value))
      (if ok
          result
          (error err)))))

(fn run [ctx]
  (with-home-world
    ctx
    (fn [env]
      (env.set-stage "assert start graph")
      (assert (= app.active-canvas-feature "graph")
              "drawing workflow e2e should start in graph mode")
      (env.set-stage "click draw")
      (click-button env "Draw")
      (env.set-stage "assert drawing mode")
      (assert (= app.active-canvas-feature "drawing")
              "drawing workflow e2e should enter drawing mode")
      (env.set-stage "click rect")
      (click-button env "Rect")
      (env.set-stage "assert rect tool")
      (assert (= app.drawing-controller.state.ui.active_tool "rectangle")
              "drawing workflow e2e should switch to rectangle tool")
      (env.set-stage "drag rectangle")
      (drag-on-canvas env
                      (glm.vec3 -12 -8 0)
                      (glm.vec3 12 8 0))
      (env.set-stage "assert rectangle count")
      (assert (= (object-count) 1)
              "drawing workflow e2e should create one rectangle")
      (env.set-stage "assert triangle vector")
      (assert (> (or (triangle-vector-length) 0) 0)
              "drawing workflow e2e should populate the canvas triangle vector")
      (env.set-stage "click graph")
      (click-button env "Graph")
      (env.set-stage "assert graph mode")
      (assert (= app.active-canvas-feature "graph")
              "drawing workflow e2e should switch back to graph mode")
      (env.set-stage "click draw again")
      (click-button env "Draw")
      (env.set-stage "assert drawing mode again")
      (assert (= app.active-canvas-feature "drawing")
              "drawing workflow e2e should switch back to drawing mode")
      (env.set-stage "click select")
      (click-button env "Select")
      (env.set-stage "assert select tool")
      (assert (= app.drawing-controller.state.ui.active_tool "select")
              "drawing workflow e2e should switch to select tool")
      (env.set-stage "select rectangle")
      (click-at env (canvas-screen-point (glm.vec3 0 0 0)))
      (env.set-stage "assert selection")
      (assert (= (app.drawing-controller:selection-count) 1)
              "drawing workflow e2e should select the drawn rectangle")
      (env.set-stage "focus rename input")
      (focus-rename-input env)
      (env.set-stage "delete while input focused")
      (send-key-down env KEY_DELETE)
      (env.set-stage "ctrl-z while input focused")
      (send-key-down env KEY_Z_LOWER CTRL-MOD)
      (env.set-stage "assert object persistence")
      (assert (= (object-count) 1)
              "drawing workflow e2e should keep the rectangle while typing in rename input")
      (env.set-stage "assert selection persistence")
      (assert (= (app.drawing-controller:selection-count) 1)
              "drawing workflow e2e should keep selection while typing in rename input")
      (env.set-stage "blur input")
      (blur-input env)
      (env.set-stage "final update")
      (refresh-world env))))

(fn main []
  (Harness.with-app {:width 1280 :height 720}
                    (fn [ctx]
                      (run ctx)))
  (print "E2E drawing workflow complete"))

{:run run
 :main main}
