(local DefaultDialog (require :default-dialog))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Text (require :text))
(local Label (require :label))
(local Input (require :input))

(local center-force-min 0.0)
(local center-force-max 0.0009)

(fn finite-number? [v]
    (and (= (type v) :number)
         (= v v)
         (not (= v math.huge))
         (not (= v (- math.huge)))))

(fn format-center-force [v]
    (string.format "%.6g" v))

(fn GraphViewControlView [opts]
    (local base-options (or opts {}))

    (fn build [ctx runtime-opts]
        (local options (or runtime-opts base-options))
        (local graph-view (or options.graph-view app.graph-view))
        (assert graph-view "GraphViewControlView requires a graph-view")
        (local layout (and graph-view graph-view.layout))
        (assert layout "GraphViewControlView requires graph-view.layout")

        (local view {:handlers []
                     :continuous? false
                     :status-text nil
                     :toggle-button nil
                     :center-force-input nil
                     :center-force-apply-button nil})

        (fn get-current-center-force []
            (local value (. layout :center-force))
            (assert (finite-number? value) "GraphViewControlView requires finite layout.center-force")
            value)

        (fn get-status-text []
            (if view.continuous?
                "Continuous"
                (if layout.active
                    "Running"
                    "Stabilized")))

        (fn get-button-text []
            "Start/Stop")

        (fn update-ui []
            (when view.status-text
                (view.status-text:set-text (get-status-text))))

        (fn handle-stabilized []
            (when view.continuous?
                (layout:start))
            (update-ui))

        (fn handle-changed []
            (update-ui))

        (fn validate-center-force [value]
            (and (finite-number? value)
                 (>= value center-force-min)
                 (<= value center-force-max)))

        (fn reset-center-force-input []
            (when (and view.center-force-input view.center-force-input.set-text)
                (view.center-force-input:set-text
                    (format-center-force (get-current-center-force))
                    {:reset-cursor? true})))

        (fn apply-center-force []
            (when view.center-force-input
                (local text (view.center-force-input:get-text))
                (local parsed (and text (tonumber text)))
                (if (validate-center-force parsed)
                    (do
                        (set (. layout :center-force) parsed)
                        (layout:start)
                        (reset-center-force-input))
                    (reset-center-force-input))))

        (fn start-continuous []
            (set view.continuous? true)
            (layout:start)
            (update-ui))

        (fn stop-continuous []
            (set view.continuous? false)
            (update-ui))

        (fn toggle-continuous []
            (if view.continuous?
                (stop-continuous)
                (start-continuous)))

        (when layout.stabilized
            (local handler (layout.stabilized:connect handle-stabilized))
            (table.insert view.handlers {:signal layout.stabilized
                                         :handler handler}))
        (when layout.changed
            (local handler (layout.changed:connect handle-changed))
            (table.insert view.handlers {:signal layout.changed
                                         :handler handler}))

        (fn build-content [child-ctx]
            (local status-text
                ((Text {:text (get-status-text)}) child-ctx))
            (local toggle-button
                ((Button {:text (get-button-text)
                          :variant :primary
                          :on-click (fn [_button _event]
                                        (toggle-continuous))})
                 child-ctx))
            (set view.status-text status-text)
            (set view.toggle-button toggle-button)
            (local status-row
                ((Flex {:axis 1
                        :xspacing 0.6
                        :yalign :center
                        :children [(FlexChild (fn [_] ((Label {:text "Status:"}) child-ctx)) 0)
                                   (FlexChild (fn [_] status-text) 0)]})
                 child-ctx))
            (local center-force-input
                ((Input {:text (format-center-force (get-current-center-force))
                         :min-columns 8
                         :max-columns 12})
                 child-ctx))
            (local center-force-apply-button
                ((Button {:text "Apply"
                          :variant :secondary
                          :on-click (fn [_button _event]
                                        (apply-center-force))})
                 child-ctx))
            (set view.center-force-input center-force-input)
            (set view.center-force-apply-button center-force-apply-button)
            (local center-force-row
                ((Flex {:axis 1
                        :xspacing 0.6
                        :yalign :center
                        :children [(FlexChild (fn [_] ((Label {:text "Center force:"}) child-ctx)) 0)
                                   (FlexChild (fn [_] center-force-input) 0)
                                   (FlexChild (fn [_] center-force-apply-button) 0)]})
                 child-ctx))
            ((Flex {:axis 2
                    :reverse true
                    :xalign :stretch
                    :yspacing 0.6
                    :children [(FlexChild (fn [_] status-row) 0)
                               (FlexChild (fn [_] center-force-row) 0)
                               (FlexChild (fn [_] toggle-button) 0)]})
             child-ctx))

        (local dialog
            ((DefaultDialog {:title (or options.title "Graph View Control")
                             :name (or options.name "graph-view-control-view")
                             :on-close options.on-close
                             :child build-content})
             ctx))
        (set dialog.__control-view view)
        (local base-drop dialog.drop)
        (set dialog.drop
             (fn [self]
                 (each [_ record (ipairs view.handlers)]
                     (when (and record record.signal record.handler)
                         (record.signal:disconnect record.handler true)))
                 (when base-drop
                     (base-drop self))))
        dialog)
    build)

(local exports {:GraphViewControlView GraphViewControlView})

(setmetatable exports {:__call (fn [_ ...]
                                   (GraphViewControlView ...))})

exports
