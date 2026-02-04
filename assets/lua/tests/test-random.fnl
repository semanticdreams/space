(local tests [])
(local random (require :random))

(fn random-seed-reproducible []
  (random.seed 12345)
  (local a1 (random.randint 1 100))
  (local b1 (random.randint 1 100))
  (local c1 (random.randrange 10))
  (local d1 (random.random))
  (local e1 (random.uniform -2.0 3.0))
  (local f1 (random.randbytes-hex 8))

  (random.seed 12345)
  (local a2 (random.randint 1 100))
  (local b2 (random.randint 1 100))
  (local c2 (random.randrange 10))
  (local d2 (random.random))
  (local e2 (random.uniform -2.0 3.0))
  (local f2 (random.randbytes-hex 8))

  (assert (= a1 a2))
  (assert (= b1 b2))
  (assert (= c1 c2))
  (assert (= d1 d2))
  (assert (= e1 e2))
  (assert (= f1 f2)))

(fn random-randint-bounds []
  (random.seed 9001)
  (for [_ 1 200]
    (local v (random.randint 5 7))
    (assert (>= v 5))
    (assert (<= v 7))))

(fn random-randrange-bounds-and-step []
  (random.seed 4242)
  (for [_ 1 200]
    (local v (random.randrange 0 10 2))
    (assert (>= v 0))
    (assert (< v 10))
    (assert (= (% v 2) 0))))

(fn random-float-ranges []
  (random.seed 111)
  (for [_ 1 200]
    (local v (random.random))
    (assert (>= v 0.0))
    (assert (< v 1.0)))
  (for [_ 1 200]
    (local v (random.uniform -1.5 2.5))
    (assert (>= v -1.5))
    (assert (<= v 2.5))))

(fn random-bytes-lengths []
  (random.seed 7)
  (local bytes (random.randbytes 16))
  (assert (= (# bytes) 16))
  (local hex (random.randbytes-hex 16))
  (assert (= (# hex) 32))
  (assert (hex:match "^[0-9a-f]+$")))

(fn list-contains? [items needle]
  (var found false)
  (each [_ item (ipairs items)]
    (when (= item needle)
      (set found true)))
  found)

(fn random-choice-and-errors []
  (random.seed 12)
  (local items ["a" "b" "c"])
  (local v (random.choice items))
  (assert (list-contains? items v))
  (local (ok _err) (pcall (fn [] (random.choice []))))
  (assert (not ok) "choice should error for empty sequences"))

(fn random-shuffle-in-place []
  (random.seed 55)
  (local items [1 2 3 4 5])
  (local out (random.shuffle items))
  (assert (= out items))
  (assert (= (# items) 5))
  (for [i 1 5]
    (assert (list-contains? items i))))

(fn random-sample-unique []
  (random.seed 99)
  (local items [1 2 3 4 5 6 7])
  (local out (random.sample items 3))
  (assert (= (# out) 3))
  (for [i 1 3]
    (assert (list-contains? items (. out i))))
  (assert (not= (. out 1) (. out 2)))
  (assert (not= (. out 1) (. out 3)))
  (assert (not= (. out 2) (. out 3))))

(table.insert tests {:name "random seed reproducible" :fn random-seed-reproducible})
(table.insert tests {:name "randint bounds are inclusive" :fn random-randint-bounds})
(table.insert tests {:name "randrange bounds and step" :fn random-randrange-bounds-and-step})
(table.insert tests {:name "random and uniform float ranges" :fn random-float-ranges})
(table.insert tests {:name "randbytes and hex lengths" :fn random-bytes-lengths})
(table.insert tests {:name "choice and error cases" :fn random-choice-and-errors})
(table.insert tests {:name "shuffle in-place" :fn random-shuffle-in-place})
(table.insert tests {:name "sample unique elements" :fn random-sample-unique})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "random"
                       :tests tests})))

{:name "random"
 :tests tests
 :main main}
