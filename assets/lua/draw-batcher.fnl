(fn DrawBatcher [opts]
  (local stride (math.max 1 (or opts.stride 1)))
  (local state {:stride stride
                :entries {}
                :batches []
                :dirty true})

  (fn rebuild [self]
    (local collected [])
    (each [handle entry (pairs self.entries)]
      (when (and handle entry)
        (table.insert collected {:handle handle
                                 :clip entry.clip
                                 :model entry.model})))
    (table.sort collected
                (fn [a b]
                  (< a.handle.index b.handle.index)))

    (local batch-index {})
    (fn state-key [value]
      (if (= value nil) false value))
    (fn resolve-batch [clip model]
      (local clip-key (state-key clip))
      (local model-key (state-key model))
      (when (not (. batch-index clip-key))
        (set (. batch-index clip-key) {}))
      (local by-clip (. batch-index clip-key))
      (when (not (. by-clip model-key))
        (set (. by-clip model-key) {:clip clip
                                    :model model
                                    :handles []
                                    :min-index nil}))
      (. by-clip model-key))

    (each [_ entry (ipairs collected)]
      (local batch (resolve-batch entry.clip entry.model))
      (table.insert batch.handles entry.handle)
      (if batch.min-index
          (set batch.min-index (math.min batch.min-index entry.handle.index))
          (set batch.min-index entry.handle.index)))

    (local batches [])
    (each [_ by-clip (pairs batch-index)]
      (each [_ batch (pairs by-clip)]
        (table.insert batches batch)))

    (each [_ batch (ipairs batches)]
      (table.sort batch.handles (fn [a b] (< a.index b.index)))
      (local firsts [])
      (local counts [])
      (var run-start nil)
      (var run-size 0)
      (fn flush-run []
        (when (and run-start (> run-size 0))
          (local start (math.floor (/ run-start self.stride)))
          (local count (math.floor (/ run-size self.stride)))
          (when (> count 0)
            (table.insert firsts start)
            (table.insert counts count)))
        (set run-start nil)
        (set run-size 0))
      (each [_ handle (ipairs batch.handles)]
        (when (> handle.size 0)
          (if (and run-start (= (+ run-start run-size) handle.index))
              (set run-size (+ run-size handle.size))
              (do
                (flush-run)
                (set run-start handle.index)
                (set run-size handle.size)))))
      (flush-run)
      (set batch.firsts firsts)
      (set batch.counts counts))

    (table.sort batches
                (fn [a b]
                  (local ai (or a.min-index 0))
                  (local bi (or b.min-index 0))
                  (< ai bi)))
    (set self.batches batches)

    (set self.dirty false))

  (fn track-handle [self handle clip-region model]
    (when handle
      (set (. self.entries handle) {:clip clip-region
                                    :model model})
      (set self.dirty true)))

  (fn untrack-handle [self handle]
    (when handle
      (set (. self.entries handle) nil)
      (set self.dirty true)))

  (fn get-batches [self]
    (when self.dirty
      (self:rebuild))
    self.batches)

  (set state.rebuild rebuild)
  (set state.track-handle track-handle)
  (set state.untrack-handle untrack-handle)
  (set state.get-batches get-batches)
  state)

DrawBatcher
