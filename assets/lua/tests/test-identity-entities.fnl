(local fs (require :fs))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "identity-entities"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "identity-" (os.time) "-" temp-counter)))

(fn with-temp-store [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result)
    (pcall
      (fn []
        (local IdentityStore (require :entities/identity))
        (local store (IdentityStore.IdentityStore {:base-dir dir}))
        (f store dir))))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn identity-store-creates-entities []
  (with-temp-store
    (fn [store _dir]
      (local entity (store:create-entity {:target-key "string-entity:a"}))
      (assert entity "entity should be created")
      (assert entity.id "entity should have id")
      (assert (= entity.target-key "string-entity:a") "entity should have target-key")
      (assert entity.created-at "entity should have created-at")
      (assert entity.updated-at "entity should have updated-at"))))

(fn identity-store-updates-target-key []
  (with-temp-store
    (fn [store _dir]
      (local entity (store:create-entity {:target-key "a"}))
      (store:update-entity entity.id {:target-key "b"})
      (local loaded (store:get-entity entity.id))
      (assert (= loaded.target-key "b") "target-key should be updated"))))

(fn identity-store-emits-signals []
  (with-temp-store
    (fn [store _dir]
      (var created-count 0)
      (var updated-count 0)
      (var deleted-count 0)
      (store.identity-created:connect (fn [_] (set created-count (+ created-count 1))))
      (store.identity-updated:connect (fn [_] (set updated-count (+ updated-count 1))))
      (store.identity-deleted:connect (fn [_] (set deleted-count (+ deleted-count 1))))
      (local entity (store:create-entity {:target-key "a"}))
      (store:update-entity entity.id {:target-key "b"})
      (store:delete-entity entity.id)
      (assert (= created-count 1) "created signal should emit once")
      (assert (= updated-count 1) "updated signal should emit once")
      (assert (= deleted-count 1) "deleted signal should emit once"))))

(fn identity-store-finds-entity-by-target-key []
  (with-temp-store
    (fn [store _dir]
      (store:create-entity {:target-key "node-a"})
      (store:create-entity {:target-key "node-b"})
      (local entity (store:find-by-target-key "node-b"))
      (assert entity "find-by-target-key should return an entity")
      (assert (= entity.target-key "node-b")
              "find-by-target-key should return entity with matching target key"))))

(table.insert tests {:name "identity store creates entities"
                     :fn identity-store-creates-entities})
(table.insert tests {:name "identity store updates target key"
                     :fn identity-store-updates-target-key})
(table.insert tests {:name "identity store emits signals"
                     :fn identity-store-emits-signals})
(table.insert tests {:name "identity store finds entity by target key"
                     :fn identity-store-finds-entity-by-target-key})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "identity-entities"
                       :tests tests})))

{:name "identity-entities"
 :tests tests
 :main main}
