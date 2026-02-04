(local tray-module (require :tray))
(local fs (require :fs))
(local logging (require :logging))

(fn TrayManager []
  (var handle nil)
  (var disabled-reason nil)

  (fn reset-handle []
    (when handle
      (handle:exit)
      (set handle nil)))

  (fn setup []
    (reset-handle)
    (set disabled-reason nil)
    (local tray (or tray-module app.engine.tray))
    (if (and tray tray.support)
        (do
          (local support (tray.support))
          (if support.supported
              (do
                (local tray-spec {:icon (fs.absolute (app.engine.get-asset-path "pics/space.png"))
                                  :menu [{:text "Quit"
                                          :cb (fn [_checked] (app.engine.quit))}]})
                (local new-handle (tray.create tray-spec))
                (if (new-handle:start)
                    (do
                      (set handle new-handle))
                    (do
                      (set disabled-reason (or (new-handle:last-error) "tray_init failed"))
                      (logging.warn (.. "[space] tray unavailable (" support.backend "): " disabled-reason)))))
              (do
                (set disabled-reason support.reason)
                (logging.warn (.. "[space] tray unavailable (" support.backend "): "
                                  (or support.reason "unsupported backend"))))))
        (do
          (set disabled-reason "tray binding missing")
          (logging.warn "[space] tray unavailable: tray binding missing"))))

  (fn loop []
    (when handle
      (local res (handle:loop false))
      (when (< res 0)
        (logging.warn "[space] tray loop reported exit; disabling tray")
        (reset-handle))))

  (fn drop []
    (reset-handle))

  {:setup setup
   :loop loop
   :drop drop
   :reason (fn [] disabled-reason)})

TrayManager
