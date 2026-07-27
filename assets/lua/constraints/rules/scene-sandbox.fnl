;; Scene/Sandbox constraint rules for experimental Fennel constraints.
;; Four rules covering legacy state, activity slot ownership,
;; sandbox activation contract, and render context routing.

(local Diagnostics (require :constraints.diagnostics))

(local M {})

;; ---------------------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------------------

(fn file-path-basename [path]
  "Return the basename of a file path, stripping the .fnl extension if present."
  (var result path)
  (each [part (path:gmatch "[^/]+")]
    (set result part))
  ;; Strip .fnl extension
  (result:gsub "%.fnl$" ""))

(fn path-contains? [path fragment]
  "Check if path contains the given fragment (literal match)."
  (let [(start _end) (string.find path fragment 1 true)]
    (not (not start))))

(fn extract-string-arg-from-form [form]
  "Extract the first string argument from a Fennel form string.
  Returns the extracted string or nil."
  (local quoted (or (form:match "\"([^\"]+)\"")
                    (form:match ":[a-z][a-z-]*")))
  (when quoted
    (if (= (quoted:sub 1 1) ":")
        (quoted:sub 2)
        quoted)))

(fn call-exists-with-method? [calls callee]
  "Check if any call in the list has the given callee name."
  (var found false)
  (each [_ c (ipairs calls)]
    (when (= c.callee callee)
      (set found true)))
  found)

(fn require-exists? [requires module-name]
  "Check if any require entry has the given module name."
  (var found false)
  (each [_ r (ipairs requires)]
    (when (= r.module module-name)
      (set found true)))
  found)

(fn find-call-with-method [calls callee]
  "Find the first call with the given callee, returning the call record or nil."
  (var found nil)
  (each [_ c (ipairs calls)]
    (when (and (= c.callee callee) (not found))
      (set found c)))
  found)

(fn find-call-with-method-arg [calls callee expected-arg]
  "Find the first call with the given callee, and check if its form
  contains the expected argument. Returns {:match? bool :call call}."
  (var result {:match? false})
  (each [_ c (ipairs calls)]
    (when (= c.callee callee)
      (let [arg (extract-string-arg-from-form c.form)]
        (when (= arg expected-arg)
          (set result {:match? true :call c})))))
  result)

;; ---------------------------------------------------------------------------
;; Rule 1: scene.no-legacy-world-state-scene
;; ---------------------------------------------------------------------------

(fn is-allowlisted-migration-file? [path]
  "Return true if the file path is an allowlisted migration file
  that is permitted to access world.state.scene.*."
  (or (path-contains? path "/home-world.fnl")
      (path-contains? path "/tests/")
      (path-contains? path "/e2e/")))

(fn legacy-world-state-rule-run [ctx]
  "Rule: flag world.state.scene.* access outside allowlisted migration files."
  (let [fact-db ctx.facts
        diagnostics []]
    (each [_ ff (ipairs (or fact-db.files []))]
      (when (not (is-allowlisted-migration-file? ff.path))
        (each [_ access (ipairs (or ff.accesses []))]
          (when (and (>= (length (or access.path [])) 3)
                     (= (. access.path 1) "world")
                     (= (. access.path 2) "state")
                     (= (. access.path 3) "scene"))
            (table.insert diagnostics
              (Diagnostics.violation
                {:constraint-id "scene.no-legacy-world-state-scene"
                 :family "scene-sandbox"
                 :message (.. "legacy world.state.scene access: " access.text)
                 :file ff.path
                 :line (or access.line 0)
                 :column (or access.column 0)
                 :evidence {:access access.text :form (or access.form "")}
                 :hint (.. "replace world.state.scene.* access with "
                           "runtime.scene slot API (ensure-activity-slot / activate-activity-slot) "
                           "or add this file to the migration allowlist if it is a known migration file")}))))))
    (if (> (length diagnostics) 0) diagnostics nil)))

;; ---------------------------------------------------------------------------
;; Rule 2: scene.activity-slot-ownership
;; ---------------------------------------------------------------------------

(local activity-module-ids
  {"graph-activity-unit" "graph"
   "drawing-activity-unit" "drawing"
   "board-activity-unit" "board"})

(fn check-call-uses-foreign-slot [diagnostics ff basename expected-id method-name]
  "Check if a scene method call in the file uses 'sandbox' instead of the expected id."
  (let [full-method (.. "scene:" method-name)
        check-result (find-call-with-method-arg ff.calls full-method "sandbox")]
    (when check-result.match?
      (table.insert diagnostics
        (Diagnostics.violation
          {:constraint-id "scene.activity-slot-ownership"
           :family "scene-sandbox"
           :message (.. basename " calls " method-name " with \"sandbox\" instead of \"" expected-id "\"")
           :file ff.path
           :line (or check-result.call.line 0)
           :column (or check-result.call.column 0)
           :evidence {:call full-method
                      :form (or check-result.call.form "")
                      :actual-arg "sandbox"
                      :expected-arg expected-id}
           :hint (.. "replace \"sandbox\" with \"" expected-id "\" in the " method-name " call")})))))

(fn activity-slot-ownership-rule-run [ctx]
  "Rule: Graph, Drawing, and Board modules must call ensure/activate-activity-slot
  with their own ids, not 'sandbox'."
  (let [fact-db ctx.facts
        diagnostics []]
    (each [_ ff (ipairs (or fact-db.files []))]
      (let [basename (file-path-basename ff.path)
            expected-id (. activity-module-ids basename)]
        (when expected-id
          (check-call-uses-foreign-slot diagnostics ff basename expected-id "ensure-activity-slot")
          (check-call-uses-foreign-slot diagnostics ff basename expected-id "activate-activity-slot"))))
    (if (> (length diagnostics) 0) diagnostics nil)))

;; ---------------------------------------------------------------------------
;; Rule 3: scene.sandbox-activation-contract
;; ---------------------------------------------------------------------------

(local sandbox-contract-required-calls
  [;; The core Scene slot management calls
   {:callee "scene:ensure-activity-slot" :label "ensure-activity-slot sandbox"}
   {:callee "scene:activate-activity-slot" :label "activate-activity-slot sandbox"}
   ;; Surface configuration: hide Canvas, prefer Scene
   {:callee "ctx:set-surface-state!" :label "set-surface-state! (hide Canvas)"}
   {:callee "ctx:set-preferred-interaction-surface!"
    :label "set-preferred-interaction-surface! (prefer Scene)"}
   ;; Action and routing installation
   {:callee "ctx:set-root-actions!" :label "set-root-actions!"}
   {:callee "ctx:set-target-enabled!" :label "set-target-enabled!"}
   ;; Update hook installation
   {:callee "ctx:set-update!" :label "set-update!"}])

(fn check-sandbox-requires-runtime [diagnostics ff]
  "Check that sandbox-activity-unit.fnl requires the runtime module."
  (when (not (require-exists? ff.requires "runtime"))
    (table.insert diagnostics
      (Diagnostics.violation
        {:constraint-id "scene.sandbox-activation-contract"
         :family "scene-sandbox"
         :message "sandbox-activity-unit.fnl must require 'runtime'"
         :file ff.path
         :line 0 :column 0
         :evidence {:required-require "runtime"}
          :hint "add (local runtime (require :runtime)) to sandbox-activity-unit.fnl"}))))

(fn check-single-contract-call [diagnostics ff req]
  "Check a single required call in sandbox-activity-unit.fnl."
  (when (not (call-exists-with-method? ff.calls req.callee))
    (table.insert diagnostics
      (Diagnostics.violation
        {:constraint-id "scene.sandbox-activation-contract"
         :family "scene-sandbox"
         :message (.. "sandbox-activity-unit.fnl missing required call: " req.label)
         :file ff.path
         :line 0 :column 0
         :evidence {:missing-call req.callee}
         :hint (.. "add (" req.callee " ...) to the sandbox activation function")}))))

(fn sandbox-activation-contract-rule-run [ctx]
  "Rule: sandbox-activity-unit.fnl must follow the activation contract."
  (let [fact-db ctx.facts
        diagnostics []]
    (each [_ ff (ipairs (or fact-db.files []))]
      (when (path-contains? ff.path "sandbox-activity-unit.fnl")
        (check-sandbox-requires-runtime diagnostics ff)
        (each [_ req (ipairs sandbox-contract-required-calls)]
          (check-single-contract-call diagnostics ff req))))
    (if (> (length diagnostics) 0) diagnostics nil)))

;; ---------------------------------------------------------------------------
;; Rule 4: scene.active-render-context-routing
;; ---------------------------------------------------------------------------

(fn active-render-context-routing-rule-run [ctx]
  "Scenario: verify that the active Scene slot context supplies render vectors."
  (local Scenarios (require :constraints.scenarios))
  (local diagnostics [])
  (Scenarios.with-test-app
    (fn []
      ;; Import needed modules inside the scenario (has real app environment)
      (local glm (require :glm))
      (local Activities (require :activities))
      (local Scene (require :scene))
      (local Camera (require :camera))
      (local AppProjection (require :app-projection))
      (local SandboxActivityUnit (require :sandbox-activity-unit))

      ;; Setup: ensure activity is registered and active
      (SandboxActivityUnit.load-sandbox-activity!)

      ;; Ensure projection factory is available (required by Scene.reset-projection)
      (when (not app.create-default-projection)
        (set app.create-default-projection AppProjection.create-default-projection))

      ;; Create a scene with camera
      (local camera (Camera {:position (glm.vec3 0 0 100)}))
      (local scene (Scene {:camera camera}))

      ;; Set up the runtime as if sandbox is active
      (set app.active-world-runtime {:scene scene})
      (tset app :canvas {:visible? false :interactive? false})

      ;; Activate the sandbox activity
      (Activities.activate-activity "sandbox")

      ;; Verify: the scene should have an active slot for sandbox
      (let [slot (scene:activity-slot "sandbox")]
        (when (not slot)
          (table.insert diagnostics
            (Diagnostics.violation
              {:constraint-id "scene.active-render-context-routing"
               :family "scene-sandbox"
               :message "no Scene activity slot for sandbox after activation"
               :file "sandbox-activity-unit.fnl"
               :line 0 :column 0
               :evidence {:assertion "scene:activity-slot(\"sandbox\")"}
               :hint "ensure sandbox activation creates a Scene activity slot via ensure-activity-slot"})))
        ;; Verify: the slot should have a build context (render vectors)
        (when (and slot (not slot.ctx))
          (table.insert diagnostics
            (Diagnostics.violation
              {:constraint-id "scene.active-render-context-routing"
               :family "scene-sandbox"
               :message "active Scene slot missing render context (ctx)"
               :file "sandbox-activity-unit.fnl"
               :line 0 :column 0
               :evidence {:assertion "slot.ctx render context"}
               :hint "ensure the Scene slot provides a build context for render vectors"})))
        ;; Verify: the slot should have a layout root for render routing
        (when (and slot (not slot.layout-root))
          (table.insert diagnostics
            (Diagnostics.violation
              {:constraint-id "scene.active-render-context-routing"
               :family "scene-sandbox"
               :message "active Scene slot missing layout root for render routing"
               :file "sandbox-activity-unit.fnl"
               :line 0 :column 0
               :evidence {:assertion "slot.layout-root render routing"}
               :hint "ensure the Scene slot provides a layout root for render routing"})))

      ;; Cleanup
      (scene:drop)
      (camera:drop)
      (tset app :active-world-runtime nil))))
  (if (> (length diagnostics) 0) diagnostics nil))

;; ---------------------------------------------------------------------------
;; Rule registry
;; ---------------------------------------------------------------------------

(fn M.rules []
  "Return the list of scene-sandbox rules."
  [{:id "scene.no-legacy-world-state-scene"
    :family "scene-sandbox"
    :targets [:repo]
    :kind :static
    :run legacy-world-state-rule-run}
   {:id "scene.activity-slot-ownership"
    :family "scene-sandbox"
    :targets [:repo]
    :kind :static
    :run activity-slot-ownership-rule-run}
   {:id "scene.sandbox-activation-contract"
    :family "scene-sandbox"
    :targets [:repo]
    :kind :static
    :run sandbox-activation-contract-rule-run}
   {:id "scene.active-render-context-routing"
    :family "scene-sandbox"
    :targets [:repo]
    :kind :scenario
    :run active-render-context-routing-rule-run}])

M
