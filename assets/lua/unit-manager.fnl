(fn UnitManager []
  (var units-by-id {})
  (var unit-order [])

  (fn register [self unit]
    (assert unit "UnitManager.register requires a unit")
    (local id unit.id)
    (assert id "Unit requires :id")
    (assert (= (type id) :string) "Unit :id must be a string")
    (assert (not (. units-by-id id))
            (.. "Unit " id " already registered"))
    (tset units-by-id id unit)
    (table.insert unit-order unit)
    unit)

  (fn unregister [self id]
    (assert (= (type id) :string) "UnitManager.unregister requires a string id")
    (local unit (. units-by-id id))
    (when unit
      (if (unit:loaded?)
          (do
            (unit:unload {})
            (tset units-by-id id nil)
            (for [i (length unit-order) 1 -1]
              (when (= (. unit-order i) unit)
                (table.remove unit-order i))))
          (do
            (tset units-by-id id nil)
            (for [i (length unit-order) 1 -1]
              (when (= (. unit-order i) unit)
                (table.remove unit-order i))))))
    unit)

  (fn get [self id]
    (. units-by-id id))

  (fn list [self]
    unit-order)

  (fn count [self]
    (length unit-order))

  (fn reload-unit [self id ctx]
    (local unit (self:get id))
    (assert unit (.. "Unit " id " not found"))
    (unit:reload (or ctx {})))

  (fn clear [self]
    (for [i (length unit-order) 1 -1]
      (local unit (. unit-order i))
      (self:unregister unit.id))
    true)

  {:register register
   :unregister unregister
   :get get
   :list list
   :count count
   :reload-unit reload-unit
   :clear clear})
