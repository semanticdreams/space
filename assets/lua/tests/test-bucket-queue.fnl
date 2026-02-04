(local BucketQueue (require :bucket-queue))

(local tests [])

(fn bucket-queue-iterate-allows-removal []
  (local queue (BucketQueue))
  (local nodes [1 2 3 4 5])
  (each [_ node (ipairs nodes)]
    (queue:enqueue node 0))
  (local (ok err)
    (pcall
      (fn []
        (queue:iterate
          (fn [node _depth]
            (queue:remove node)
            (queue:enqueue 99 0)))))) 
  (assert ok (.. "bucket queue iterate failed: " (tostring err)))
  (each [_ node (ipairs nodes)]
    (assert (not (. queue.lookup node)) "bucket queue should remove nodes during iteration")))

(table.insert tests {:name "BucketQueue iterate allows removal" :fn bucket-queue-iterate-allows-removal})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "bucket-queue"
                       :tests tests})))

{:name "bucket-queue"
 :tests tests
 :main main}
