(local RealtimeCommon (require :realtime.common))

(local ping {:id 1 :name "ping" :version 1})
(local echo {:id 2 :name "echo" :version 1})
(local counter {:id 3 :name "counter" :version 1})

(local all [ping echo counter])

(fn register-all! [registry]
  (RealtimeCommon.register-features! registry all))

{:ping ping
 :echo echo
 :counter counter
 :all all
 :register-all! register-all!}
