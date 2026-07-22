(fn count [m]
  (var n 0)
  (when (= (type m) "table")
    (each [_ _v (pairs m)]
      (set n (+ n 1))))
  n)

{:count count}
