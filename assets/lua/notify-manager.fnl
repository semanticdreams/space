(local notify-module (require :notify))
(local logging (require :logging))

(fn NotifyManager []
  (var disabled-reason nil)

  (fn send [summary body opts]
    (local notify (or notify-module app.notify))
    (if notify
        (do
          (local support (and notify.support (notify.support)))
          (local backend (or (and support support.backend) "unknown"))
          (local icon (if (and opts (= (type opts) :table) opts.icon)
                          opts.icon
                          (app.engine.get-asset-path "pics/space.png")))
          (if support
              (if support.supported
                  (if (notify.send summary body icon opts)
                      true
                      (do
                        (set disabled-reason (or (notify.last-error) "notification send failed"))
                        (logging.warn (.. "[space] notification failed (" backend "): " disabled-reason))
                        false))
                  (do
                    (set disabled-reason (or support.reason "unsupported notification backend"))
                    (logging.warn (.. "[space] notifications unavailable (" backend "): "
                                      disabled-reason))
                    false))
              (do
                (set disabled-reason "notification support missing")
                (logging.warn "[space] notifications unavailable: notification support missing")
                false)))
        (do
          (set disabled-reason "notification binding missing")
          (logging.warn "[space] notifications unavailable: notification binding missing")
          false)))

  {:send send
   :reason (fn [] disabled-reason)})

NotifyManager
