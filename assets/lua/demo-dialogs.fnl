(local glm (require :glm))
(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))
(local DemoChart (require :demo-chart))
(local DemoPhysicsCuboids (require :demo-physics-cuboids))
(local DefaultDialog (require :default-dialog))
(local FsView (require :fs-view))
(local fs (require :fs))
(local Image (require :image))
(local Input (require :input))
(local LayoutStatsView (require :layout-stats-view))
(local ListView (require :list-view))
(local ObjectBrowser (require :object-browser))
(local Padding (require :padding))
(local Sized (require :sized))
(local Text (require :text))
(local logging (require :logging))

(local DemoDialogs {})

(fn new-checklist-dialog [opts]
  (local options (or opts {}))
  (local mission-items ["Run diagnostics"
                        "Calibrate thrusters"
                        "Plot jump coordinates"
                        "Sync nav telemetry"
                        "Signal ready status"
                        "Inspect hull integrity"
                        "Charge warp capacitors"
                        "Align communication arrays"
                        "Review crew manifests"
                        "Secure cargo locks"
                        "Update star charts"
                        "Stage escape pods"])
  (local list-builder
    (ListView {:title "Mission Checklist"
               :name "mission-list"
               :show-head true
               :item-spacing 0.35
               :paginate true
               :items-per-page 4
               :items mission-items}))
  (DefaultDialog
    {:title "Checklist"
     :on-close options.on-close
     :child (Padding {:edge-insets [0.6 0.6]
                      :child list-builder})}))

(fn new-fs-dialog [opts]
  (local options (or opts {}))
  (local assets-path (and app.engine app.engine.get-asset-path (app.engine.get-asset-path "lua")))
  (local fallback-path (and fs fs.cwd (fs.cwd)))
  (local start-path (or assets-path fallback-path "."))
  (local fs-view
    (FsView {:path start-path
             :items-per-page 8
             :item-padding [0.5 0.45]}))
  (DefaultDialog
    {:title "File Browser"
     :on-close options.on-close
     :child (Padding {:edge-insets [0.6 0.6]
                      :child fs-view})}))

(fn new-object-browser-dialog [opts]
  (local options (or opts {}))
  (local browser
    (ObjectBrowser {:target (or app.engine {})
                    :name "space-browser"
                    :items-per-page 8
                    :item-padding [0.5 0.45]
                    :root-label "space"}))
  (DefaultDialog
    {:title "Object Browser"
     :on-close options.on-close
     :child (Padding {:edge-insets [0.6 0.6]
                      :child browser})}))

(fn new-demo-dialog [opts]
  (local options (or opts {}))
  (local message
    (Padding {:edge-insets [0.8 0.6]
              :child (Text {:text "Hello from the dialog!"})}))
  (DefaultDialog
    {:title "Welcome Aboard"
     :on-close options.on-close
     :actions [["refresh" (fn [_button _event]
                            (logging.info "refresh dialog action"))]]
     :child message}))

(fn new-multiline-text-dialog [opts]
  (local options (or opts {}))
  (local message
    (Padding {:edge-insets [0.8 0.6]
              :child
              (Text
                {:text (.. "Mission Control Online\n"
                           "Preparing telemetry sync\n"
                           "Stand by for updates...")})}))
  (DefaultDialog
    {:title "Operations Console"
     :on-close options.on-close
     :child message}))

(fn new-input-dialog [opts]
  (local options (or opts {}))
  (local instructions
    (Text {:text "Capture a mission title and message using the inputs below."}))
  (local title-input
    (Input {:placeholder "Mission title"
            :name "mission-log-title"
            :min-width 10
            :min-height 1.8
            :on-change (fn [_ text]
                         (logging.info (.. "[mission-log:title] " text)))}))
  (local message-input
    (Input {:placeholder "Enter mission details..."
            :name "mission-log-message"
            :multiline? true
            :line-count 5
            :min-width 10
            :on-change (fn [_ text]
                         (logging.info (.. "[mission-log:message] " text)))}))
  (local content
    (Flex {:axis 2
           :xalign :stretch
           :yspacing 0.5
           :children
           [(FlexChild (Padding {:edge-insets [0 0.25]
                               :child instructions}) 0)
            (FlexChild (Padding {:edge-insets [0 0.15]
                                 :child title-input}) 0)
            (FlexChild (Padding {:edge-insets [0 0.15]
                                 :child message-input}) 0)]}))
  (DefaultDialog
    {:title "Mission Log"
     :on-close options.on-close
     :child (Padding {:edge-insets [0.8 0.6]
                      :child content})}))

(fn new-layout-stats-dialog [opts]
  (local options (or opts {}))
  (local stats-view
    (LayoutStatsView {:size (glm.vec3 11 6.5 0)
                      :padding (glm.vec3 0.6 0.55 0)}))
  (DefaultDialog
    {:title "Layout Dirt (first 10 frames)"
     :on-close options.on-close
     :child (Padding {:edge-insets [0.6 0.6]
                      :child stats-view})}))

(local dialog-padding
  (fn [child-builder]
    (fn [ctx runtime-opts]
      (child-builder ctx runtime-opts))))

(local demo-entries
  [{:key :physics-cuboid
    :label "Physics Cuboid"
    :builder (Sized {:size (glm.vec3 4 4 4)
                     :child (DemoPhysicsCuboids.new-cuboid)})}
   {:key :space-image
    :label "Space Image"
    :builder (Image {:path "pics/space.png"
                     :width 18})}
   {:key :welcome-dialog
    :label "Welcome Dialog"
    :builder (dialog-padding (new-demo-dialog))}
   {:key :operations-console
    :label "Operations Console"
    :builder (dialog-padding (new-multiline-text-dialog))}
   {:key :telemetry-chart
    :label "Telemetry Chart"
    :builder (dialog-padding (DemoChart.new-dialog))}
   {:key :layout-stats
    :label "Layout Dirt"
    :builder (dialog-padding (new-layout-stats-dialog))}
   {:key :mission-checklist
    :label "Mission Checklist"
    :builder (dialog-padding (new-checklist-dialog))}
   {:key :file-browser
    :label "File Browser"
    :builder (dialog-padding (new-fs-dialog))}
   {:key :object-browser
    :label "Object Browser"
    :builder (dialog-padding (new-object-browser-dialog))}
   {:key :mission-log
    :label "Mission Log Inputs"
    :builder (dialog-padding (new-input-dialog))}])

(fn DemoDialogs.list []
  demo-entries)

(fn DemoDialogs.find-entry [key]
  (accumulate [result nil _ entry (ipairs demo-entries)]
    (if (or (= entry.key key) (= entry.label key))
        entry
        result)))

(fn DemoDialogs.collect-movables [root]
  (if (and root root.children)
      (icollect [_ metadata (ipairs root.children)]
        {:target metadata.element.layout
         :handle metadata.element})
      []))

(fn DemoDialogs.new-browser-dialog [opts]
  (local options (or opts {}))
  (local on-open (or options.on-open (fn [_entry] nil)))
  (local entries (or options.entries (DemoDialogs.list)))
  (local list-view
    (ListView {:title "Available Demos"
               :name "demo-browser-list"
               :items entries
               :items-per-page 8
               :item-spacing 0.25
               :builder
               (fn [entry child-ctx]
                 ((Button {:text (or entry.label (tostring entry.key))
                           :variant :ghost
                           :padding [0.45 0.35]
                           :on-click (fn [_button _event]
                                       (on-open entry))})
                  child-ctx))}))
  (DefaultDialog
    {:title "Demo Browser"
     :on-close options.on-close
     :child (Padding {:edge-insets [0.6 0.6]
                      :child list-view})}))

DemoDialogs
