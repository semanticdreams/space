(local default-cursor "arrow")

(fn call-setter [setter name]
  (when (and setter name (= (type setter) "function"))
    (setter name)))

(fn SystemCursors [opts]
  (local options (or opts {}))
  (local setter (or options.set-cursor app.engine.set-system-cursor))
  (local fallback (or options.default default-cursor))
  (local self {:set-fn setter
               :default fallback
               :current nil})

  (fn apply-cursor [self name]
    (when (and name (not (= name self.current)))
      (call-setter self.set-fn name)
      (set self.current name)))

  (fn reset [self]
    (when self.default
      (self:set-cursor self.default)))

  (fn drop [self]
    (self:reset)
    (set self.set-fn nil))

  (set self.set-cursor apply-cursor)
  (set self.reset reset)
  (set self.drop drop)
  self)

SystemCursors
