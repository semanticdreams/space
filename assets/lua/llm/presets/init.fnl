;; PresetManager — owns live context, overrides, cached resolution, and change notifications.
;; Coordinates PresetRegistry and ToolAdapterRegistry. Pure resolution flows through the registry;
;; tool def generation flows through adapters.

(fn clone-table [value]
  (if (= (type value) "table")
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn deep-equal? [a b]
  (if (and (not (= (type a) "table")) (not (= (type b) "table")))
      (= a b)
      (or (= (type a) "table") (= (type b) "table"))
      (do
        (local same (= (type a) (type b)))
        (var ok same)
        (when ok
          (each [k v (pairs a)]
            (when ok
              (set ok (deep-equal? v (. b k)))))
          (when ok
            (each [k _v (pairs b)]
              (when ok
                (set ok (not (= (. a k) nil)))))))
        ok)
      false))

(fn append-sorted-override-signature [parts overrides]
  (local names [])
  (each [name _state (pairs (or overrides {}))]
    (table.insert names name))
  (table.sort names)
  (each [_ name (ipairs names)]
    (local state (. overrides name))
    (table.insert parts (.. "override:" name "=" (tostring (and state state.state))))))

(fn compute-signature [resolution overrides]
  (local parts [])
  (each [_ p (ipairs resolution.active-presets)]
    (table.insert parts (.. "preset:" p.name ":" (tostring p.reason))))
  (each [_ tid (ipairs resolution.tool-ids)]
    (table.insert parts (.. "tool:" tid)))
  (each [_ fragment (ipairs resolution.prompt-fragments)]
    (table.insert parts (.. "prompt:" fragment.preset ":" fragment.prompt)))
  (append-sorted-override-signature parts overrides)
  (table.concat parts "\n"))

(fn PresetManager [opts]
  (local registry opts.registry)
  (local tool-adapters opts.tool-adapters)
  (local app opts.app)
  (local context opts.context)
  (local overrides opts.overrides)
  (assert registry "PresetManager requires :registry")
  (assert tool-adapters "PresetManager requires :tool-adapters")
  (assert app "PresetManager requires :app")
  (assert context "PresetManager requires :context")
  (assert (= (type context.surface) "string") "context must have string surface")
  (when (not (= context.mode nil))
    (assert (= (type context.mode) "string") "context.mode must be string or nil"))
  (assert (not (= context.canvas-visible? nil)) "context.canvas-visible? must not be nil")

  (var current-context (clone-table context))
  (var current-overrides (clone-table (or overrides {})))
  (var cached-resolution nil)
  (var cached-signature nil)
  (var listeners [])

  (fn invalidate-cache []
    (set cached-resolution nil)
    (set cached-signature nil))

  (fn fire-change []
    (each [_ cb (ipairs listeners)]
      (cb)))

  (fn resolve-with-signature []
    (local resolved (registry:resolve current-context current-overrides))
    (values resolved (compute-signature resolved current-overrides)))

  (fn refresh-cache []
    (local (resolved signature) (resolve-with-signature))
    (set cached-resolution resolved)
    (set cached-signature signature)
    (values resolved signature))

  (fn fire-if-signature-changed [previous-signature]
    (local (_resolved signature) (refresh-cache))
    (when (not (= previous-signature signature))
      (fire-change)))

  (fn register [self preset]
    (local previous-signature (select 2 (refresh-cache)))
    (registry:register preset)
    (fire-if-signature-changed previous-signature)
    self)

  (fn unregister [self name]
    (local previous-signature (select 2 (refresh-cache)))
    (registry:unregister name)
    (fire-if-signature-changed previous-signature)
    self)

  (fn set-context [self ctx]
    (assert (= (type ctx) "table") "context must be a table")
    (assert (= (type ctx.surface) "string") "context.surface must be a string")
    (when (not (= ctx.mode nil))
      (assert (= (type ctx.mode) "string") "context.mode must be a string or nil"))
    (assert (not (= ctx.canvas-visible? nil)) "context.canvas-visible? must not be nil")
    (when (not (deep-equal? current-context ctx))
      (local previous-signature (select 2 (refresh-cache)))
      (set current-context (clone-table ctx))
      (fire-if-signature-changed previous-signature))
    self)

  (fn get-context [self]
    (clone-table current-context))

  (fn set-override [self name state]
    (assert (= (type name) "string") "override name must be a string")
    (assert (or (= state :auto) (= state :on) (= state :off))
            (.. "override state must be :auto, :on, or :off, got " (tostring state)))
    (when (not (registry:get name))
      (error (.. "unknown preset name: " name)))
    (local previous (. current-overrides name))
    (if (and previous (= previous.state state))
        self
        (do
          (local previous-signature (select 2 (refresh-cache)))
          (set (. current-overrides name) {:state state})
          (fire-if-signature-changed previous-signature)
          self)))

  (fn get-overrides [self]
    (clone-table current-overrides))

  (fn ensure-resolved [self]
    (when (not cached-resolution)
      (refresh-cache))
    cached-resolution)

  (fn get-active-presets [self]
    (clone-table (. (self:ensure-resolved) :active-presets)))

  (fn get-tool-ids [self]
    (clone-table (. (self:ensure-resolved) :tool-ids)))

  (fn get-tool-defs [self]
    (local resolved (self:ensure-resolved))
    (local defs [])
    (local seen-names {})
    (each [_ tid (ipairs resolved.tool-ids)]
      (local def (tool-adapters:resolve tid app))
      (when (. seen-names def.name)
        (error (.. "duplicate MCP tool name '" def.name "' resolved from tool-ids")))
      (tset seen-names def.name true)
      (table.insert defs def))
    defs)

  (fn get-prompt-fragments [self]
    (clone-table (. (self:ensure-resolved) :prompt-fragments)))

  (fn add-on-change [self cb]
    (table.insert listeners cb)
    cb)

  (fn remove-on-change [self cb]
    (for [i (# listeners) 1 -1]
      (when (= (. listeners i) cb)
        (table.remove listeners i))))

  (fn status [self]
    (local resolved (self:ensure-resolved))
    (var override-count 0)
    (each [_ _v (pairs current-overrides)]
      (set override-count (+ override-count 1)))
    {:context (clone-table current-context)
     :override-count override-count
     :active-preset-count (# resolved.active-presets)
     :tool-id-count (# resolved.tool-ids)
     :prompt-fragment-count (# resolved.prompt-fragments)
     :registry-status (registry:status)
     :cached (not (= cached-resolution nil))})

  {:registry registry
   :tool-adapters tool-adapters
   :app app
   :register register
   :unregister unregister
   :set-context set-context
   :get-context get-context
   :set-override set-override
   :get-overrides get-overrides
   :ensure-resolved ensure-resolved
   :get-active-presets get-active-presets
   :get-tool-ids get-tool-ids
   :get-tool-defs get-tool-defs
   :get-prompt-fragments get-prompt-fragments
   :add-on-change add-on-change
   :remove-on-change remove-on-change
   :status status})

{:PresetManager PresetManager}
