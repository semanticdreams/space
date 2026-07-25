;; PresetRegistry — immutable preset definitions and pure resolution.
;; No runtime closures, no MCP knowledge. Change notifications via callbacks.

(local VALID-RISKS {:normal true :filesystem-read true :filesystem-write true :destructive true :shell true})
(local VALID-DEFAULT-STATES {:auto true :off true})
(local VALID-OVERRIDE-STATES {:auto true :on true :off true})

(fn clone-table [value]
  (if (= (type value) "table")
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn validate-context [ctx]
  (assert (= (type ctx) "table") "context must be a table")
  (assert (= (type ctx.surface) "string") "context.surface must be a string")
  (assert (= ctx.mode nil) "context.mode is not supported; use context.activity")
  (when (not (= ctx.activity nil))
    (assert (= (type ctx.activity) "string") "context.activity must be a string or nil"))
  (assert (not (= ctx.canvas-visible? nil)) "context.canvas-visible? must not be nil")
  true)

(fn validate-overrides [overrides by-name]
  (assert (= (type overrides) "table") "overrides must be a table")
  (each [name state (pairs overrides)]
    (assert (. by-name name) (.. "unknown override preset name: " name))
    (assert (= (type state) "table") (.. "override for '" name "' must be a table"))
    (assert (. VALID-OVERRIDE-STATES state.state)
            (.. "override '" name "' has invalid state '" (tostring state.state) "'")))
  true)

(fn validate-preset [preset]
  (assert (= (type preset) "table") "preset must be a table")
  (assert (= (type preset.name) "string") "preset must have a string name")
  (assert (> (# preset.name) 0) "preset name must not be empty")
  (assert (. VALID-DEFAULT-STATES preset.default-state)
          (.. "preset '" preset.name "' has invalid default-state '" (tostring preset.default-state) "'"))
  (assert (. VALID-RISKS preset.risk)
          (.. "preset '" preset.name "' has invalid risk '" (tostring preset.risk) "'"))
  (assert (= (type preset.contexts) "table") (.. "preset '" preset.name "' contexts must be a table"))
  (assert (> (# preset.contexts) 0) (.. "preset '" preset.name "' must have at least one context"))
  (each [_ ctx (ipairs preset.contexts)]
    (assert (= (type ctx) "table") (.. "preset '" preset.name "' context entry must be a table"))
    (assert (= ctx.mode nil) (.. "preset '" preset.name "' context.mode is not supported; use context.activity"))
    (when (not (= ctx.activity nil))
      (assert (or (= ctx.activity :any) (= ctx.activity :none) (= (type ctx.activity) "string"))
              (.. "preset '" preset.name "' context.activity must be a string, :any, :none, or nil"))))
  (assert (= (type preset.tool-ids) "table") (.. "preset '" preset.name "' tool-ids must be a table"))
  (assert (> (# preset.tool-ids) 0) (.. "preset '" preset.name "' tool-ids must not be empty"))
  (each [_ tid (ipairs preset.tool-ids)]
    (assert (= (type tid) "string") (.. "preset '" preset.name "' tool-id must be a string")))
  (when preset.system-prompt
    (assert (= (type preset.system-prompt) "string")
            (.. "preset '" preset.name "' system-prompt must be a string")))
  true)

(fn context-field-matches? [pattern-val actual-val]
  (if (= pattern-val :any)
      true
      (= pattern-val :none)
      (= actual-val nil)
      (= pattern-val actual-val)))

(fn context-matches? [pattern ctx]
  (each [key pat-val (pairs pattern)]
    (when (not (context-field-matches? pat-val (. ctx key)))
      (lua "return false")))
  true)

(fn PresetRegistry [opts]
  (var presets [])
  (var by-name {})
  (var listeners [])
  (var change-count 0)

  (fn fire-change []
    (set change-count (+ change-count 1))
    (each [_ cb (ipairs listeners)]
      (cb)))

  (fn register [self preset]
    (validate-preset preset)
    (when (. by-name preset.name)
      (error (.. "duplicate preset name: " preset.name)))
    (local stored (clone-table preset))
    (table.insert presets stored)
    (tset by-name stored.name stored)
    (fire-change)
    self)

  (fn unregister [self name]
    (when (not (. by-name name))
      (error (.. "unknown preset name: " name)))
    (tset by-name name nil)
    (local filtered [])
    (each [_ p (ipairs presets)]
      (when (not (= p.name name))
        (table.insert filtered p)))
    (set presets filtered)
    (fire-change)
    self)

  (fn get [self name]
    (clone-table (. by-name name)))

  (fn list [self]
    (clone-table presets))

  (fn list-by-group [self group]
    (local result [])
    (each [_ p (ipairs presets)]
      (when (= p.group group)
        (table.insert result (clone-table p))))
    result)

  (fn preset-activation [preset override]
    (if (and override (= override.state :on))
        (values true :override)
        (and override (= override.state :off))
        (values false nil)
        (= preset.default-state :off)
        (values false nil)
        (values false :pending)))

  (fn resolve [self context overrides]
    (validate-context context)
    (when overrides (validate-overrides overrides by-name))
    (local active-presets [])
    (local resolved-tool-ids [])
    (local seen-tool-ids {})
    (local prompt-fragments [])

    (each [_ preset (ipairs presets)]
      (local override (and overrides (. overrides preset.name)))
      (local (forced? forced-reason) (preset-activation preset override))

      (var active? false)
      (var reason nil)

      (if forced?
          (do
            (set active? true)
            (set reason forced-reason))
          (= forced-reason :pending)
          (each [_ pattern (ipairs preset.contexts)]
            (when (and (not active?) (context-matches? pattern context))
              (set active? true)
              (set reason :context))))

      (when active?
        (table.insert active-presets {:name preset.name
                                      :reason reason
                                      :risk preset.risk
                                      :group (or preset.group nil)})
        (each [_ tid (ipairs preset.tool-ids)]
          (when (. seen-tool-ids tid)
            (error (.. "duplicate tool-id '" tid "' resolved from presets")))
          (tset seen-tool-ids tid true)
          (table.insert resolved-tool-ids tid))
        (when preset.system-prompt
          (table.insert prompt-fragments {:preset preset.name :prompt preset.system-prompt}))))

    {:active-presets active-presets
     :tool-ids resolved-tool-ids
     :prompt-fragments prompt-fragments})

  (fn status [self]
    {:preset-count (# presets)
     :change-count change-count
     :listener-count (# listeners)})

  (fn add-on-change [self cb]
    (table.insert listeners cb)
    cb)

  (fn remove-on-change [self cb]
    (for [i (# listeners) 1 -1]
      (when (= (. listeners i) cb)
        (table.remove listeners i))))

  {:register register
   :unregister unregister
   :get get
   :list list
   :list-by-group list-by-group
   :resolve resolve
   :status status
   :add-on-change add-on-change
   :remove-on-change remove-on-change})

{:PresetRegistry PresetRegistry}
