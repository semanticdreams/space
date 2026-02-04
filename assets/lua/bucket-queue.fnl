(fn make-depth-bucket-queue [opts]
  (local options (or opts {}))
  (local queue {:buckets {} :lookup {} :depths [] :depth-set {}
                :label options.label})
  (local DebugLog (require :layout-debug-log))

  (fn ensure-depth [self depth]
    (when (not (. self.depth-set depth))
      (set (. self.depth-set depth) true)
      (table.insert self.depths depth)
      (table.sort self.depths)))

  (fn remove [self node]
    (local depth (. self.lookup node))
    (when depth
      (local bucket (. self.buckets depth))
      (when bucket
        (set (. bucket node) nil))
      (set (. self.lookup node) nil)))

  (fn enqueue [self node depth]
    (local target-depth (or depth 0))
    (when (not (= (. self.lookup node) target-depth))
      (self:remove node)
      (self:ensure-depth target-depth)
      (local bucket (. self.buckets target-depth))
      (if bucket
          (set (. bucket node) true)
          (do
            (local new-bucket {})
            (set (. new-bucket node) true)
            (set (. self.buckets target-depth) new-bucket)))
      (set (. self.lookup node) target-depth)))

  (fn iterate [self f]
    (each [_ depth (ipairs self.depths)]
      (local bucket (. self.buckets depth))
      (when bucket
        (var key nil)
        (var keep-going true)
        (while keep-going
          (local (ok next-key _value) (pcall next bucket key))
          (when (not ok)
            (DebugLog.log-next-error next-key bucket key depth self.depths self)
            (error next-key))
          (if (not next-key)
              (set keep-going false)
              (do
                (f next-key depth)
                (set key next-key)))))))

  (fn clear [self]
    (set self.buckets {})
    (set self.lookup {})
    (set self.depths [])
    (set self.depth-set {}))

  (set queue.ensure-depth ensure-depth)
  (set queue.enqueue enqueue)
  (set queue.remove remove)
  (set queue.iterate iterate)
  (set queue.clear clear)
  queue)

make-depth-bucket-queue
