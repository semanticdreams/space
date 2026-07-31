;; Presentation helper functions shared between production (main.fnl)
;; and e2e test harness (harness.fnl).  These are installed as methods on
;; the global `app` table so that callers such as `resizables.fnl` can
;; invoke them without knowing whether a full production runtime is active.

(fn install-presentation-helpers! [app]
  (set app.active-presentation
       (fn []
         (and app.active-world-runtime
              app.active-world-runtime.presentation)))

  (set app.presentation-screen-pos-ray
       (fn [pos opts]
         (let [provider (app.active-presentation)]
           (assert provider "app.presentation-screen-pos-ray requires an active presentation provider")
           (provider:screen-pos-ray pos opts))))

  (set app.presentation-input-controls
       (fn []
         (let [provider (app.active-presentation)]
           (and provider (provider:input-controls)))))

  (set app.presentation-camera
       (fn [opts]
         (let [provider (app.active-presentation)]
           (if provider
               (provider:camera opts)
               (let [options (or opts {})]
                 (when options.required?
                   (assert provider "app.presentation-camera requires an active presentation provider")))))))

  app)

{: install-presentation-helpers!}
