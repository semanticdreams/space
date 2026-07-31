;; set.fnl
(fn Set []
  (local methods
    {:add (fn [self val]
            (tset self val true)
            self)
     :discard (fn [self val]
                (tset self val nil)
                self)
     :union (fn [self other]
              (local result (Set))
              (each [k _ (pairs self)] (tset result k true))
              (each [k _ (pairs other)] (tset result k true))
              result)
     :intersection (fn [self other]
                     (local result (Set))
                     (each [k _ (pairs self)]
                       (when (tget other k)
                         (tset result k true)))
                     result)
     :difference (fn [self other]
                   (local result (Set))
                   (each [k _ (pairs self)]
                     (when (not (tget other k))
                       (tset result k true)))
                   result)
     :to-array (fn [self]
                 (local arr [])
                 (each [k _ (pairs self)] (table.insert arr k))
                 arr)})
  (setmetatable {} {:__index methods}))

Set
