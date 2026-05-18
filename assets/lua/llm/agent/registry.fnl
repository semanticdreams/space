;; Agent registry — maps stable agent IDs to lazy-constructed agent instances.

(fn AgentRegistry [opts]
  (local deps (or opts.deps {}))
  (var factories {})
  (var instances {})

  (fn register [self id factory]
    (assert (= (type id) "string") "agent id must be a string")
    (assert (= (type factory) "function") (.. "agent factory for '" id "' must be a function"))
    (tset factories id factory)
    ;; Invalidate cached instance when re-registering
    (tset instances id nil)
    self)

  (fn get [self id]
    (assert (= (type id) "string") "agent id must be a string")
    (if (. instances id)
        (. instances id)
        (do
          (local factory (. factories id))
          (if factory
              (do
                (local instance (factory deps))
                (assert (= (type instance) "table") (.. "factory for '" id "' must return a table"))
                (tset instances id instance)
                instance)
              nil))))

  (fn list [self]
    (local result [])
    (each [id _factory (pairs factories)]
      (local instance (. instances id))
      (table.insert result {:id id
                            :name (or (and instance instance.name) id)}))
    result)

  (fn unregister [self id]
    (tset factories id nil)
    (tset instances id nil)
    self)

  {:register register
   :get get
   :list list
   :unregister unregister})

{:AgentRegistry AgentRegistry}
