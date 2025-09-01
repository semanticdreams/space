(fn Widget [opts]
  (fn build [ctx]
    (local e {})

    ;(local e {:children (or opts.children [])})

    ;(when opts.children
    ;  (icollect [_ v (ipairs opts.children)]
    ;            ))

    (set e.drop (fn [self]
                  (each [_ x (ipairs self.children)]
                    (x:drop))
                  ))
    e))
