(local tests [])

(local {:VectorBuffer VectorBuffer} (require :vector-buffer))

(fn capacity-and-free-stats-roundtrip []
  (local vector (VectorBuffer 0))
  (local handle-a (vector:allocate 4))
  (local handle-b (vector:allocate 6))
  (assert (= (vector:length) 10))
  (assert (>= (vector:capacity) 10))
  (assert (= (vector:free-count) 0))
  (assert (= (vector:free-size) 0))

  (vector:delete handle-a)
  (assert (= (vector:length) 10))
  (assert (= (vector:free-count) 1))
  (assert (= (vector:free-size) 4))

  (local reused (vector:allocate 4))
  (assert (= reused.index handle-a.index))
  (assert (= (vector:free-count) 0))
  (assert (= (vector:free-size) 0))

  (vector:delete reused)
  (vector:delete handle-b)
  (assert (= (vector:length) 0))
  (assert (= (vector:free-count) 0))
  (assert (= (vector:free-size) 0)))

(fn stale-handle-errors-propagate-through-lua-api []
  (local vector (VectorBuffer 0))
  (local handle (vector:allocate 4))
  (vector:delete handle)

  (local (ok-view err-view) (pcall vector.view vector handle))
  (assert (not ok-view))
  (assert (string.find err-view "handle is not active" 1 true))

  (local (ok-float err-float) (pcall vector.set-float vector handle 0 1.0))
  (assert (not ok-float))
  (assert (string.find err-float "handle is not active" 1 true))

  (local bytes (string.char 0 0 128 63))
  (local (ok-bytes err-bytes) (pcall vector.set-floats-from-bytes vector handle 0 bytes))
  (assert (not ok-bytes))
  (assert (string.find err-bytes "handle is not active" 1 true)))

(table.insert tests {:name "VectorBuffer Lua API reports capacity and free stats"
                     :fn capacity-and-free-stats-roundtrip})
(table.insert tests {:name "VectorBuffer Lua API surfaces stale handle errors"
                     :fn stale-handle-errors-propagate-through-lua-api})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "vector-buffer"
                       :tests tests})))

{:name "vector-buffer"
 :tests tests
 :main main}
