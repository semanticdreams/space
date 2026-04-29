(local NativeRealtime (require :realtime))

(fn register-features! [registry features]
  (each [_ feature (ipairs features)]
    (registry:register-feature feature))
  registry)

(fn new-feature-registry [features]
  (local registry (NativeRealtime.FeatureRegistry))
  (when features
    (register-features! registry features))
  registry)

{:native NativeRealtime
 :available NativeRealtime.available
 :version NativeRealtime.version
 :Service NativeRealtime.Service
 :FeatureRegistry NativeRealtime.FeatureRegistry
 :make-dev-ticket NativeRealtime.make-dev-ticket
 :verify-dev-ticket NativeRealtime.verify-dev-ticket
 :register-features! register-features!
 :new-feature-registry new-feature-registry}
