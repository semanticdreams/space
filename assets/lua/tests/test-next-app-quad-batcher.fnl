(local QuadBatcher (require :next-app/quad-batcher))

(local tests [])

(fn matrix-copy [m]
  [(. m 1) (. m 2) (. m 3) (. m 4)
   (. m 5) (. m 6) (. m 7) (. m 8)
   (. m 9) (. m 10) (. m 11) (. m 12)
   (. m 13) (. m 14) (. m 15) (. m 16)])

(fn next-app-quad-batcher-compacts-identical-clip-groups []
  (local batcher (QuadBatcher {}))
  (local clip-a
    [1 0 0 0
     0 1 0 0
     0 0 1 0
     2 3 0 1])
  (local clip-b (matrix-copy clip-a))

  (batcher:add-quad {:clip-matrix clip-a})
  (batcher:add-quad {:clip-matrix clip-b})

  (assert (= (batcher:get-instance-count) 2))
  (assert (= (batcher:get-clip-count) 2)
          "identical clip matrices should share one clip group"))

(fn next-app-quad-batcher-keeps-default-clip-group-for-nil-or-false []
  (local batcher (QuadBatcher {}))
  (batcher:add-quad {})
  (batcher:add-quad {:clip-matrix false})
  (assert (= (batcher:get-instance-count) 2))
  (assert (= (batcher:get-clip-count) 1)))

(fn next-app-quad-batcher-reused-slot-updates-instance-count []
  (local batcher (QuadBatcher {}))
  (batcher:upsert-quad :a {})
  (batcher:upsert-quad :b {})
  (batcher:upsert-quad :c {})
  (assert (= (batcher:get-instance-count) 3))

  ;; Remove tail first so active-count shrinks.
  (batcher:remove-quad :c)
  (assert (= (batcher:get-instance-count) 2))
  ;; Remove middle slot after shrink; free list now contains a slot above active-count.
  (batcher:remove-quad :b)
  (assert (= (batcher:get-instance-count) 1))

  ;; Reusing slot 2 must bump instance count back to 2, otherwise this quad won't draw.
  (batcher:upsert-quad :d {})
  (assert (= (batcher:get-instance-count) 2)
          "reused slot above active-count must increase instance count"))

(table.insert tests {:name "NextApp quad batcher compacts identical clip groups"
                     :fn next-app-quad-batcher-compacts-identical-clip-groups})
(table.insert tests {:name "NextApp quad batcher keeps default clip group for nil or false"
                     :fn next-app-quad-batcher-keeps-default-clip-group-for-nil-or-false})
(table.insert tests {:name "NextApp quad batcher reused slot updates instance count"
                     :fn next-app-quad-batcher-reused-slot-updates-instance-count})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "next-app-quad-batcher"
                       :tests tests})))

{:name "next-app-quad-batcher"
 :tests tests
 :main main}
