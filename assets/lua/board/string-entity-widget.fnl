(local Input (require :input))

(fn StringEntityBoardWidget [opts]
  (local options (or opts {}))
  (local item (assert options.item "StringEntityBoardWidget requires :item"))
  (local store (assert options.store "StringEntityBoardWidget requires :store"))
  (local entity-id (assert options.entity-id "StringEntityBoardWidget requires :entity-id"))
  (fn build [ctx]
    (local entity (assert (store:get-entity entity-id)
                          (.. "String entity board item missing entity: " (tostring entity-id))))
    (local input
      ((Input {:text (or entity.value "")
               :placeholder "String value..."
               :multiline? true
               :min-lines 3
               :max-lines 12
               :on-change (fn [_input value]
                            (store:update-entity entity-id {:value value}))})
       ctx))
    {:item item
     :input input
     :layout input.layout
     :drop (fn [_self]
             (input:drop))}))

StringEntityBoardWidget
