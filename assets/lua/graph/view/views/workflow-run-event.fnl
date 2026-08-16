(local {: Flex : FlexChild} (require :flex))
(local Input (require :input))
(local JsonUtils (require :json-utils))
(local ScrollView (require :scroll-view))
(local Text (require :text))

(local METADATA_KEYS {:id true
                      :run-id true
                      :kind true
                      :step-id true
                      :created-at true})

(fn existing-widget [widget]
  (fn [_ctx] widget))

(fn render-value [value]
  (if (= value nil)
      "nil"
      (= (type value) :table)
      (JsonUtils.stable-json value)
      (tostring value)))

(fn sorted-extra-keys [event]
  (local keys [])
  (each [key _value (pairs event)]
    (when (not (. METADATA_KEYS key))
      (table.insert keys key)))
  (table.sort keys (fn [left right]
                     (< (tostring left) (tostring right))))
  keys)

(fn field-label [key]
  (case key
    :payload "Payload"
    :error "Error"
    :output "Output"
    _ (tostring key)))

(fn payload-text [event]
  (local current (assert event "WorkflowRunEventNodeView requires event"))
  (local lines [(.. "Event: " (render-value current.id))
                (.. "Kind: " (render-value current.kind))])
  (when current.step-id
    (table.insert lines (.. "Step: " (render-value current.step-id))))
  (when current.created-at
    (table.insert lines (.. "Created At: " (render-value current.created-at))))
  (each [_ key (ipairs (sorted-extra-keys current))]
    (table.insert lines (.. (field-label key) ": " (render-value (. current key)))))
  (table.concat lines "\n"))

(fn WorkflowRunEventNodeView [node opts]
  (local options (or opts {}))
  (local target (assert (or node options.node) "WorkflowRunEventNodeView requires node"))
  (fn build [ctx]
    (local build-ctx (assert ctx "WorkflowRunEventNodeView requires a build context"))
    (local view {})
    (assert target.get-event "WorkflowRunEventNodeView requires node:get-event")
    (local event (assert (target:get-event) "WorkflowRunEventNodeView requires event"))
    (local label (if target.label target.label target.key target.key "Workflow run event"))
    (local title ((Text {:text (tostring label)}) build-ctx))
    (local payload-input
      ((Input {:text (payload-text event)
               :multiline? true
               :focusable? false
               :min-lines 6
               :max-lines 16
               :min-columns 24
               :max-columns 80})
       build-ctx))
    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.4
              :children [(FlexChild (existing-widget title) 0)
                         (FlexChild (existing-widget payload-input) 1)]})
       build-ctx))
    (local scroll-view
      ((ScrollView {:child (existing-widget flex)
                    :padding false
                    :scrollbar-policy :as-needed})
       build-ctx))
    (set view.layout scroll-view.layout)
    (set view.title title)
    (set view.payload-input payload-input)
    (set view.flex flex)
    (set view.scroll-view scroll-view)
    (set view.drop
         (fn [_self]
           (scroll-view:drop)))
    view))

WorkflowRunEventNodeView
