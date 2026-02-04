;; set.fnl
(fn Set []
  (local self {})
  ;; same methods as before…
  (fn self:add [val]
    (tset self val true)
    self)

  (fn self:discard [val]
    (tset self val nil)
    self)

  (fn self:union [other]
    (local result (Set))
    (each [k _ (pairs self)] (tset result k true))
    (each [k _ (pairs other)] (tset result k true))
    result)

  (fn self:intersection [other]
    (local result (Set))
    (each [k _ (pairs self)]
      (when (tget other k)
        (tset result k true)))
    result)

  (fn self:difference [other]
    (local result (Set))
    (each [k _ (pairs self)]
      (when (not (tget other k))
        (tset result k true)))
    result)

  (fn self:to-array []
    (local arr [])
    (each [k _ (pairs self)] (table.insert arr k))
    arr)

  self)

Set
