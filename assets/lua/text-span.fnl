(local {: Layout} (require :layout))

(fn TextSpan [opts]
  (fn build [ctx]
    (local e {})

    (fn measurer [self]
      )

    (fn layouter [self]
      )

    (set e.layout
         (Layout {:name "text-span"
                  : measurer
                  : layouter}))

    (set e.drop (fn [self]
                  (e.layout:drop)))

    e)
  )
