(local fs (require :fs))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "string-entities"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "entities-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn with-temp-store [f]
  (with-temp-dir
    (fn [root]
      (local StringEntityStore (require :entities/string))
      (local store (StringEntityStore.StringEntityStore {:base-dir root}))
      (f store root))))

(fn string-entity-store-creates-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:value "test value"}))
      (assert entity "entity should be created")
      (assert entity.id "entity should have id")
      (assert (= entity.value "test value") "entity should have correct value")
      (assert entity.created-at "entity should have created-at")
      (assert entity.updated-at "entity should have updated-at"))))

(fn string-entity-store-retrieves-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:value "test value"}))
      (local retrieved (store:get-entity entity.id))
      (assert retrieved "entity should be retrieved")
      (assert (= retrieved.id entity.id) "retrieved entity should have same id")
      (assert (= retrieved.value "test value") "retrieved entity should have correct value"))))

(fn string-entity-store-updates-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:value "initial"}))
      (local updated (store:update-entity entity.id {:value "updated"}))
      (assert updated "entity should be updated")
      (assert (= updated.value "updated") "value should be updated")
      (local retrieved (store:get-entity entity.id))
      (assert (= retrieved.value "updated") "persisted value should be updated"))))

(fn string-entity-store-deletes-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:value "to delete"}))
      (local deleted (store:delete-entity entity.id))
      (assert deleted "entity should be deleted")
      (local retrieved (store:get-entity entity.id))
      (assert (= retrieved nil) "entity should no longer be retrievable"))))

(fn string-entity-store-lists-entities []
  (with-temp-store
    (fn [store _root]
      (store:create-entity {:value "first"})
      (store:create-entity {:value "second"})
      (store:create-entity {:value "third"})
      (local entities (store:list-entities))
      (assert (= (length entities) 3) "should list three entities"))))

(fn string-entity-store-emits-created-signal []
  (with-temp-store
    (fn [store _root]
      (var created-count 0)
      (store.string-entity-created:connect (fn [_] (set created-count (+ created-count 1))))
      (store:create-entity {:value "test"})
      (assert (= created-count 1) "created signal should be emitted"))))

(fn string-entity-store-emits-updated-signal []
  (with-temp-store
    (fn [store _root]
      (var updated-count 0)
      (store.string-entity-updated:connect (fn [_] (set updated-count (+ updated-count 1))))
      (local entity (store:create-entity {:value "test"}))
      (store:update-entity entity.id {:value "updated"})
      (assert (= updated-count 1) "updated signal should be emitted"))))

(fn string-entity-store-emits-deleted-signal []
  (with-temp-store
    (fn [store _root]
      (var deleted-count 0)
      (store.string-entity-deleted:connect (fn [_] (set deleted-count (+ deleted-count 1))))
      (local entity (store:create-entity {:value "test"}))
      (store:delete-entity entity.id)
      (assert (= deleted-count 1) "deleted signal should be emitted"))))

(fn string-entity-store-preserves-multiline-values []
  (with-temp-store
    (fn [store root]
      (local entity (store:create-entity {:value "line 1\nline 2\nline 3"}))
      (local StringEntityStore (require :entities/string))
      (local new-store (StringEntityStore.StringEntityStore {:base-dir root}))
      (local retrieved (new-store:get-entity entity.id))
      (assert (= retrieved.value "line 1\nline 2\nline 3") "multiline value should be preserved"))))

(fn entities-node-loads []
  (local EntitiesNode (require :graph/nodes/entities))
  (assert EntitiesNode "EntitiesNode should load")
  (assert (= (type EntitiesNode) "function") "EntitiesNode should be a function"))

(fn entities-node-creates-with-correct-properties []
  (local EntitiesNode (require :graph/nodes/entities))
  (local node (EntitiesNode {}))
  (assert (= node.key "entities") "key should be 'entities'")
  (assert (= node.label "entities") "label should be 'entities'")
  (assert node.color "should have color")
  (assert node.types-changed "should have types-changed signal")
  (assert node.collect-types "should have collect-types method")
  (assert node.emit-types "should have emit-types method")
  (assert node.add-type-node "should have add-type-node method"))

(fn string-entity-list-node-loads []
  (local StringEntityListNode (require :graph/nodes/string-entity-list))
  (assert StringEntityListNode "StringEntityListNode should load")
  (assert (= (type StringEntityListNode) "function") "StringEntityListNode should be a function"))

(fn string-entity-list-node-creates-with-correct-properties []
  (local StringEntityListNode (require :graph/nodes/string-entity-list))
  (local node (StringEntityListNode {}))
  (assert (= node.key "string-entity-list") "key should be 'string-entity-list'")
  (assert (= node.label "string entities") "label should be 'string entities'")
  (assert node.color "should have color")
  (assert node.items-changed "should have items-changed signal")
  (assert node.collect-items "should have collect-items method")
  (assert node.emit-items "should have emit-items method")
  (assert node.add-entity-node "should have add-entity-node method")
  (assert node.create-entity "should have create-entity method"))

(fn string-entity-node-loads []
  (local {:StringEntityNode StringEntityNode} (require :graph/nodes/string-entity))
  (assert StringEntityNode "StringEntityNode should load")
  (assert (= (type StringEntityNode) "function") "StringEntityNode should be a function"))

(fn string-entity-node-creates-with-correct-properties []
  (with-temp-store
    (fn [store _root]
      (local {:StringEntityNode StringEntityNode} (require :graph/nodes/string-entity))
      (local entity (store:create-entity {:value "test node"}))
      (local node (StringEntityNode {:entity-id entity.id :store store}))
      (assert (= node.key (.. "string-entity:" entity.id)) "key should be prefixed entity id")
      (assert node.color "should have color")
      (assert node.entity-deleted "should have entity-deleted signal")
      (assert node.get-entity "should have get-entity method")
      (assert node.update-value "should have update-value method")
      (assert node.delete-entity "should have delete-entity method")
      (node:drop))))

(fn entities-node-view-loads []
  (local EntitiesNodeView (require :graph/view/views/entities))
  (assert EntitiesNodeView "EntitiesNodeView should load")
  (assert (= (type EntitiesNodeView) "function") "EntitiesNodeView should be a function"))

(fn string-entity-list-node-view-loads []
  (local StringEntityListNodeView (require :graph/view/views/string-entity-list))
  (assert StringEntityListNodeView "StringEntityListNodeView should load")
  (assert (= (type StringEntityListNodeView) "function") "StringEntityListNodeView should be a function"))

(fn string-entity-node-view-loads []
  (local StringEntityNodeView (require :graph/view/views/string-entity))
  (assert StringEntityNodeView "StringEntityNodeView should load")
  (assert (= (type StringEntityNodeView) "function") "StringEntityNodeView should be a function"))

(table.insert tests {:name "string entity store creates entities"
                     :fn string-entity-store-creates-entities})
(table.insert tests {:name "string entity store retrieves entities"
                     :fn string-entity-store-retrieves-entities})
(table.insert tests {:name "string entity store updates entities"
                     :fn string-entity-store-updates-entities})
(table.insert tests {:name "string entity store deletes entities"
                     :fn string-entity-store-deletes-entities})
(table.insert tests {:name "string entity store lists entities"
                     :fn string-entity-store-lists-entities})
(table.insert tests {:name "string entity store emits created signal"
                     :fn string-entity-store-emits-created-signal})
(table.insert tests {:name "string entity store emits updated signal"
                     :fn string-entity-store-emits-updated-signal})
(table.insert tests {:name "string entity store emits deleted signal"
                     :fn string-entity-store-emits-deleted-signal})
(table.insert tests {:name "string entity store preserves multiline values"
                     :fn string-entity-store-preserves-multiline-values})
(table.insert tests {:name "entities node loads"
                     :fn entities-node-loads})
(table.insert tests {:name "entities node creates with correct properties"
                     :fn entities-node-creates-with-correct-properties})
(table.insert tests {:name "string entity list node loads"
                     :fn string-entity-list-node-loads})
(table.insert tests {:name "string entity list node creates with correct properties"
                     :fn string-entity-list-node-creates-with-correct-properties})
(table.insert tests {:name "string entity node loads"
                     :fn string-entity-node-loads})
(table.insert tests {:name "string entity node creates with correct properties"
                     :fn string-entity-node-creates-with-correct-properties})
(table.insert tests {:name "entities node view loads"
                     :fn entities-node-view-loads})
(table.insert tests {:name "string entity list node view loads"
                     :fn string-entity-list-node-view-loads})
(table.insert tests {:name "string entity node view loads"
                     :fn string-entity-node-view-loads})

tests
