(fn ensure-cache-store [ctx]
  (when (= ctx.__shared-instanced-mesh-cache nil)
    (set ctx.__shared-instanced-mesh-cache {}))
  ctx.__shared-instanced-mesh-cache)

(fn acquire [ctx key create-batch]
  (assert ctx "SharedInstancedMeshCache.acquire requires a build context")
  (assert key "SharedInstancedMeshCache.acquire requires a cache key")
  (assert create-batch "SharedInstancedMeshCache.acquire requires a batch factory")
  (local store (ensure-cache-store ctx))
  (local entry (. store key))
  (if entry
      (do
        (set entry.ref-count (+ entry.ref-count 1))
        entry)
      (do
        (local next-entry {:key key
                           :ref-count 1
                           :batch (create-batch)})
        (set (. store key) next-entry)
        next-entry)))

(fn release [ctx entry]
  (assert ctx "SharedInstancedMeshCache.release requires a build context")
  (assert entry "SharedInstancedMeshCache.release requires an entry")
  (local store (ensure-cache-store ctx))
  (set entry.ref-count (- entry.ref-count 1))
  (when (<= entry.ref-count 0)
    (when (and entry.batch entry.batch.drop)
      (entry.batch:drop))
    (set (. store entry.key) nil)))

{:acquire acquire
 :release release}
