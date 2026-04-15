(local BucketQueue (require :bucket-queue))

(local tests [])

(fn bucket-queue-rejects-removal-during-iteration []
  (local queue (BucketQueue))
  (local nodes [{:name "a"} {:name "b"} {:name "c"}])
  (each [_ node (ipairs nodes)]
    (queue:enqueue node 0))
  (local (ok err)
    (pcall
      (fn []
        (queue:iterate
          (fn [node _depth]
            (queue:remove node)
            (queue:enqueue {:name "new"} 0))))))
  (assert (not ok) "bucket queue should reject active-bucket mutation during iteration")
  (assert (string.find (tostring err) "do not harden BucketQueue")
          "bucket queue should explain that callers must stop mutating the queue during iteration"))

(table.insert tests {:name "BucketQueue rejects active-bucket mutation during iteration"
                     :fn bucket-queue-rejects-removal-during-iteration})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "bucket-queue"
                       :tests tests})))

{:name "bucket-queue"
 :tests tests
 :main main}
