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
  "Extract a string or keyword argument from a Fennel form string.
  Prefers the last quoted string or last keyword (the argument, not method name).
  Returns the extracted string or nil."
  ;; Try quoted string first (e.g. \"sandbox\")
  (var result (form:match "\"([^\"]+)\""))
  ;; If no quoted string, find the LAST keyword (argument comes after method name)
  (when (not result)
    (each [kw (form:gmatch ":[a-z][a-z-]*")]
      ;; Strip the leading : to get just the name
      (set result (kw:sub 2))))
  result)

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

(fn form-contains-any? [form patterns]
  "Check if form string contains any of the given literal substrings."
  (var found false)
  (each [_ p (ipairs patterns)]
    (when (string.find form p 1 true)
      (set found true)))
  found)

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

(fn check-activity-slot-call [diagnostics ff basename expected-id method-name]
  "Check that the module has the required Scene slot call with the correct id.
  Flags: missing call, call with wrong id (any id other than expected-id)."
  (let [full-method (.. "scene:" method-name)
        existing-call (find-call-with-method ff.calls full-method)]
    (if (not existing-call)
        ;; Missing the required call entirely
        (table.insert diagnostics
          (Diagnostics.violation
            {:constraint-id "scene.activity-slot-ownership"
             :family "scene-sandbox"
             :message (.. basename " is missing required call: " full-method)
             :file ff.path
             :line 0 :column 0
             :evidence {:missing-call full-method
                        :expected-id expected-id}
             :hint (.. "add (" full-method " \"" expected-id "\") to " basename)}))
        ;; Call exists — check if the slot id argument matches the expected id
        (let [arg (extract-string-arg-from-form existing-call.form)]
          (when (not (= arg expected-id))
            (table.insert diagnostics
              (Diagnostics.violation
                {:constraint-id "scene.activity-slot-ownership"
                 :family "scene-sandbox"
                 :message (.. basename " calls " method-name " with \""
                              (or arg "?") "\" instead of \"" expected-id "\"")
                 :file ff.path
                 :line (or existing-call.line 0)
                 :column (or existing-call.column 0)
                 :evidence {:call full-method
                            :form (or existing-call.form "")
                            :actual-arg (or arg "unknown")
                            :expected-arg expected-id}
                 :hint (.. "replace the id argument with \""
                           expected-id "\" in the " method-name " call")})))))))

(fn activity-slot-ownership-rule-run [ctx]
  "Rule: Graph, Drawing, and Board modules must call ensure/activate-activity-slot
  with their own ids; missing calls or any wrong slot id are violations."
  (let [fact-db ctx.facts
        diagnostics []]
    (each [_ ff (ipairs (or fact-db.files []))]
      (let [basename (file-path-basename ff.path)
            expected-id (. activity-module-ids basename)]
        (when expected-id
          (check-activity-slot-call diagnostics ff basename expected-id "ensure-activity-slot")
          (check-activity-slot-call diagnostics ff basename expected-id "activate-activity-slot"))))
    (if (> (length diagnostics) 0) diagnostics nil)))

;; ---------------------------------------------------------------------------
;; Rule 3: scene.sandbox-activation-contract
;; ---------------------------------------------------------------------------

(local sandbox-contract-required-calls
  [;; The core Scene slot management calls — must use "sandbox" id
   {:callee "scene:ensure-activity-slot" :label "ensure-activity-slot sandbox"
    :validate-arg "sandbox"}
   {:callee "scene:activate-activity-slot" :label "activate-activity-slot sandbox"
    :validate-arg "sandbox"}
   ;; Surface configuration: hide Canvas, prefer Scene
   {:callee "ctx:set-surface-state!" :label "set-surface-state! (hide Canvas)"
    :form-patterns [":visible? false" ":interactive? false"]}
   {:callee "ctx:set-preferred-interaction-surface!"
    :label "set-preferred-interaction-surface! (prefer Scene)"
    :validate-arg "scene"}
   ;; Action and routing installation — presence only
   {:callee "ctx:set-root-actions!" :label "set-root-actions!"}
   {:callee "ctx:set-target-enabled!" :label "set-target-enabled!"}
   ;; Update hook installation — presence only
   {:callee "ctx:set-update!" :label "set-update!"}])

(fn check-sandbox-requires-runtime [diagnostics ff]
  "Check that sandbox-activity-unit.fnl requires the runtime.scene module."
  (when (not (require-exists? ff.requires "runtime.scene"))
    (table.insert diagnostics
      (Diagnostics.violation
        {:constraint-id "scene.sandbox-activation-contract"
         :family "scene-sandbox"
         :message "sandbox-activity-unit.fnl must require 'runtime.scene'"
         :file ff.path
         :line 0 :column 0
         :evidence {:required-require "runtime.scene"}
         :hint "add (local runtime (require :runtime.scene)) to sandbox-activity-unit.fnl"}))))

(fn check-single-contract-call [diagnostics ff req]
  "Check a single required call in sandbox-activity-unit.fnl.
  When validate-arg is set, checks that the first string/keyword argument matches.
  When form-patterns is set, checks that the call form contains all expected patterns."
  (let [existing-call (find-call-with-method ff.calls req.callee)]
    (if (not existing-call)
        ;; Missing the required call entirely
        (table.insert diagnostics
          (Diagnostics.violation
            {:constraint-id "scene.sandbox-activation-contract"
             :family "scene-sandbox"
             :message (.. "sandbox-activity-unit.fnl missing required call: " req.label)
             :file ff.path
             :line 0 :column 0
             :evidence {:missing-call req.callee}
             :hint (.. "add (" req.callee " ...) to the sandbox activation function")}))
        ;; Call exists — check argument validation if specified
        (let [form (or existing-call.form "")]
          (when req.validate-arg
            (let [arg (extract-string-arg-from-form form)]
              (when (not (= arg req.validate-arg))
                (table.insert diagnostics
                  (Diagnostics.violation
                    {:constraint-id "scene.sandbox-activation-contract"
                     :family "scene-sandbox"
                     :message (.. "sandbox-activity-unit.fnl " req.callee " should use \""
                                  req.validate-arg "\" but got \"" (or arg "?") "\"")
                     :file ff.path
                     :line (or existing-call.line 0)
                     :column (or existing-call.column 0)
                     :evidence {:call req.callee
                                :form form
                                :expected-arg req.validate-arg
                                :actual-arg (or arg "unknown")}
                     :hint (.. "change the argument in (" req.callee " ...) to \""
                               req.validate-arg "\"")})))))
          (when req.form-patterns
            (let [missing-patterns []]
              (each [_ p (ipairs req.form-patterns)]
                (when (not (string.find form p 1 true))
                  (table.insert missing-patterns p)))
              (when (> (length missing-patterns) 0)
                (table.insert diagnostics
                  (Diagnostics.violation
                    {:constraint-id "scene.sandbox-activation-contract"
                     :family "scene-sandbox"
                     :message (.. "sandbox-activity-unit.fnl " req.callee " missing required patterns: "
                                  (table.concat missing-patterns ", "))
                     :file ff.path
                     :line (or existing-call.line 0)
                     :column (or existing-call.column 0)
                     :evidence {:call req.callee
                                :form form
                                :missing-patterns missing-patterns}
                     :hint (.. "ensure (" req.callee " ...) includes the required configuration")})))))))))

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
    :run legacy-world-state-rule-run
    :fn legacy-world-state-rule-run}
   {:id "scene.activity-slot-ownership"
    :family "scene-sandbox"
    :targets [:repo]
    :kind :static
    :run activity-slot-ownership-rule-run
    :fn activity-slot-ownership-rule-run}
   {:id "scene.sandbox-activation-contract"
    :family "scene-sandbox"
    :targets [:repo]
    :kind :static
    :run sandbox-activation-contract-rule-run
    :fn sandbox-activation-contract-rule-run}
   {:id "scene.active-render-context-routing"
    :family "scene-sandbox"
    :targets [:repo]
    :kind :scenario
    :run active-render-context-routing-rule-run
    :fn active-render-context-routing-rule-run}])

M
