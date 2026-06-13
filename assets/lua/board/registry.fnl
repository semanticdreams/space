(global app (or app {}))

(local Signal (require :signal))

(fn ensure-registry []
  (when (not app.board-registry)
    (set app.board-registry {:item-types {}
                             :changed (Signal)}))
  app.board-registry)

(fn register-item-type [spec owner]
  (local registry (ensure-registry))
  (local item-type (assert (and spec spec.id) "BoardRegistry.register-item-type requires :id"))
  (assert (= (type item-type) :string) "Board item type id must be a string")
  (assert (= (type spec.builder) :function)
          (.. "Board item type " item-type " requires :builder function"))
  (assert (not (. registry.item-types item-type))
          (.. "Duplicate board item type: " item-type))
  (local entry {:id item-type
                :label (or spec.label item-type)
                :icon spec.icon
                :builder spec.builder
                :create spec.create
                :owner owner})
  (set (. registry.item-types item-type) entry)
  (registry.changed:emit {:reason :registered :id item-type})
  entry)

(fn unregister-item-type [item-type owner]
  (local registry (ensure-registry))
  (local entry (. registry.item-types item-type))
  (when entry
    (when (or (= owner nil)
              (= entry.owner nil)
              (= entry.owner owner))
      (set (. registry.item-types item-type) nil)
      (registry.changed:emit {:reason :unregistered :id item-type})))
  true)

(fn unregister-owner [owner]
  (local registry (ensure-registry))
  (local ids [])
  (each [id entry (pairs registry.item-types)]
    (when (= entry.owner owner)
      (table.insert ids id)))
  (each [_ id (ipairs ids)]
    (unregister-item-type id owner))
  true)

(fn item-type [id]
  (local registry (ensure-registry))
  (. registry.item-types id))

(fn item-types []
  (local out [])
  (local registry (ensure-registry))
  (each [_ entry (pairs registry.item-types)]
    (table.insert out entry))
  (table.sort out (fn [a b] (< a.id b.id)))
  out)

{:ensure-registry ensure-registry
 :register-item-type register-item-type
 :unregister-item-type unregister-item-type
 :unregister-owner unregister-owner
 :item-type item-type
 :item-types item-types}
