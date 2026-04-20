(fn make-depth-bucket-queue [opts]
  (local options (or opts {}))
  (local queue {:buckets {} :lookup {} :depths [] :depth-set {}
                :label options.label
                :active-depth nil
                :active-key nil
                :iterating? false})

  (fn node-label [node]
    (or (and node node.name)
        (tostring node)))

  (fn mutation-error [self node depth]
    (error (string.format
             "BucketQueue %s callback mutated the active bucket at depth %s (active=%s requested=%s). Fix the caller; do not harden BucketQueue to mask layout/measure pass bugs."
             (or self.label "<unlabeled>")
             (tostring depth)
             (node-label self.active-key)
             (node-label node))))

  (fn assert-not-active-bucket-mutation [self node depth]
    (when (and self.iterating?
               (not (= self.active-depth nil))
               (= depth self.active-depth))
      (if (= node self.active-key)
          false
          (mutation-error self node depth))))

  (fn ensure-depth [self depth]
    (when (not (. self.depth-set depth))
      (set (. self.depth-set depth) true)
      (table.insert self.depths depth)
      (table.sort self.depths)))

  (fn remove [self node]
    (local depth (. self.lookup node))
    (when depth
      (assert-not-active-bucket-mutation self node depth)
      (local bucket (. self.buckets depth))
      (when bucket
        (set (. bucket node) nil))
      (set (. self.lookup node) nil)))

  (fn enqueue [self node depth]
    (local target-depth (or depth 0))
    (when (not (= (. self.lookup node) target-depth))
      (local current-depth (. self.lookup node))
      (when (and (not (= self.active-depth nil))
                 (or (= target-depth self.active-depth)
                     (= current-depth self.active-depth)))
        (mutation-error self node (or current-depth target-depth)))
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
        ;; Do not make BucketQueue tolerate active-bucket mutation here.
        ;; Layout/measure callbacks must stop mutating the queue during iteration.
        (set self.iterating? true)
        (set self.active-depth depth)
        (local (ok err)
          (pcall
            (fn []
              (var key nil)
              (var keep-going true)
              (while keep-going
                (local next-key (next bucket key))
                (if (not next-key)
                    (set keep-going false)
                    (do
                      (set self.active-key next-key)
                      (f next-key depth)
                      (set self.active-key nil)
                      (set key next-key)))))))
        (set self.active-depth nil)
        (set self.active-key nil)
        (set self.iterating? false)
        (when (not ok)
          (error err)))))

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
