(local Registry (require :board/registry))
(local StringEntityStore (require :entities/string))
(local StringEntityBoardWidget (require :board/string-entity-widget))

(local ITEM_TYPE "string-entity")

(fn subject-key [entity]
  (.. "string-entity:" (tostring entity.id)))

(fn entity-id-from-subject [key]
  (when (= (type key) :string)
    (local prefix "string-entity:")
    (when (= (string.sub key 1 (# prefix)) prefix)
      (string.sub key (+ (# prefix) 1)))))

(fn build-string-entity [item _view]
  (local store (StringEntityStore.get-default))
  (local entity-id (assert (entity-id-from-subject item.subject-key)
                           "String entity board item requires string-entity subject key"))
  (StringEntityBoardWidget {:item item
                            :store store
                            :entity-id entity-id}))

(fn create-string-entity [board opts]
  (local options (or opts {}))
  (assert (= options.store nil)
          "BuiltinStringEntity.create-string-entity does not accept :store; entities are always placed in the default store")
  (local store (StringEntityStore.get-default))
  (local created? (= options.entity nil))
  (local entity (or options.entity
                     (store:create-entity {:value (or options.value "")})))
  (when options.entity
    (assert (store:get-entity entity.id)
            (.. "String entity board create requires entity " (tostring entity.id)
                " to exist in default store")))
  (local key (subject-key entity))
  (local previous-items {})
  (each [_ existing (ipairs (or board.items-in-order []))]
    (set (. previous-items existing) true))
  (var item nil)
  (local (ok result)
    (pcall
      (fn []
        (set item
             (board:add-item {:type ITEM_TYPE
                              :subject-key key
                              :position options.position
                              :rotation options.rotation
                              :size options.size
                              :state options.state})))))
  (when (not ok)
    (when board.remove-item
      (when item
        (board:remove-item item.id))
      (each [_ existing (ipairs (or board.items-in-order []))]
        (when (and (= existing.subject-key key)
                   (not (. previous-items existing)))
          (board:remove-item existing.id))))
    (when created?
      (store:delete-entity entity.id))
    (error result))
  item)

(fn register [owner]
  (local existing (Registry.item-type ITEM_TYPE))
  (when existing
    (assert (= existing.owner owner)
            "String-entity board item type already registered by different owner"))
  (when (not existing)
    (Registry.register-item-type {:id ITEM_TYPE
                                   :label "String"
                                   :icon "notes"
                                   :builder build-string-entity
                                   :create create-string-entity}
                                  owner)
    true))

(fn unregister [owner]
  (Registry.unregister-item-type ITEM_TYPE owner))

{:item-type ITEM_TYPE
 :subject-key subject-key
 :entity-id-from-subject entity-id-from-subject
 :create-string-entity create-string-entity
 :register register
 :unregister unregister}
