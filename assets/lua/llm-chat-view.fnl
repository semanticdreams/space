(local DefaultDialog (require :default-dialog))
(local ListView (require :list-view))
(local Input (require :input))
(local Sized (require :sized))
(local glm (require :glm))
(local Button (require :button))
(local Padding (require :padding))
(local ScrollView (require :scroll-view))
(local {: Flex : FlexChild} (require :flex))
(local Label (require :label))
(local LlmStore (require :llm/store))
(local LlmRequests (require :llm/requests))
(local {: truncate-with-ellipsis} (require :graph/view/utils))

(fn entry-label [record]
    (if (= record.type "message")
        (do
            (local role (string.upper (or record.role "user")))
            (local body (or record.content ""))
            (.. role ": " body))
        (if (= record.type "tool-call")
            (do
                (local name (or record.name "tool"))
                (.. "Tool call: " name "\n" (or record.arguments "")))
            (if (= record.type "tool-result")
                (do
                    (local name (or record.name "tool"))
                    (.. "Tool result: " name "\n" (or record.output "")))
                (tostring (or record.type "item"))))))

(fn make-entry [record options]
    (local label (entry-label record))
    (var line-count 1)
    (when label
        (each [_ _ (string.gmatch label "\n")]
            (set line-count (+ line-count 1))))
    {:id record.id
     :type record.type
     :label label
     :line-count line-count
     :record record})

(fn first-message-content [store conversation-id]
    (local items (store:list-conversation-items conversation-id))
    (var first-message nil)
    (each [_ record (ipairs items)]
        (when (and (= record.type "message") (not first-message))
            (set first-message record)))
    (and first-message first-message.content))

(fn first-line [text]
    (if text
        (or (string.match text "([^\n]*)") text)
        text))

(fn conversation-label [store conversation]
    (local name (and conversation conversation.name))
    (local content (if (and name (string.match name "%S"))
                      name
                      (first-message-content store conversation.id)))
    (local trimmed (if (and (not (= content nil)) (not (= content name)))
                      (first-line content)
                      content))
    (local selected (if (and trimmed (string.match trimmed "%S"))
                       trimmed
                       (tostring (or conversation.id ""))))
    (truncate-with-ellipsis selected 15))

(fn build-conversations [store]
    (local items [])
    (each [_ conversation (ipairs (store:list-conversations))]
        (table.insert items {:id conversation.id
                             :label (conversation-label store conversation)}))
    items)

(fn build-items [store conversation-id options]
    (local items [])
    (each [_ record (ipairs (store:list-conversation-items conversation-id))]
        (table.insert items (make-entry record options)))
    items)

(fn build-message-entry [entry options child-ctx]
    (local text-input
        ((Input {:text ""
                 :multiline? true
                 :min-lines (or entry.line-count 1)
                 :max-lines (or entry.line-count 1)
                 :min-columns 12
                 :max-columns (or options.output-max-columns 64)})
         child-ctx))
    (when (and text-input text-input.set-text)
        (text-input:set-text entry.label {:reset-cursor? false}))
    ((Padding {:edge-insets [0.35 0.35]
               :child (fn [_] text-input)})
     child-ctx))

(fn build-conversation-entry [entry child-ctx on-select]
    (local label (or entry.label ""))
        (local button
        ((Button {:text label
                  :variant :ghost
                  :on-click (fn [_button _event]
                                (on-select entry.id))
                  :on-right-click (fn [button event]
                                      (when entry.on-menu
                                        (entry.on-menu button event)))})
         child-ctx))
    ((Padding {:edge-insets [0.25 0.25]
               :child (fn [_] button)})
     child-ctx))

(fn LlmChatView [opts]
    (local base-options (or opts {}))

    (fn copy-table [source]
        (local clone {})
        (when source
            (each [k v (pairs source)]
                (set (. clone k) v)))
        clone)

    (fn merge-options [base incoming]
        (local merged (copy-table base))
        (each [k v (pairs (or incoming {}))]
            (set (. merged k) v))
        merged)

    (fn build [ctx runtime-opts]
        (local options (merge-options base-options runtime-opts))
        (local store (or options.store (LlmStore.get-default)))
        (local view {:store store
                     :handlers []
                     :conversation-id nil
                     :conversation nil
                     :item-ids {}
                     :suspend-input-updates? false})

        (fn parse-temperature [text]
            (if (and text (string.match text "%S"))
                (tonumber text)
                0))

        (fn sync-header-fields []
            (when (and view.name-input view.temperature-input)
                (set view.suspend-input-updates? true)
                (view.name-input:set-text (or (and view.conversation view.conversation.name) "")
                                          {:reset-cursor? false})
                (local temperature
                    (if (and view.conversation
                             (not (= view.conversation.temperature nil)))
                        (tostring view.conversation.temperature)
                        ""))
                (view.temperature-input:set-text temperature {:reset-cursor? false})
                (set view.suspend-input-updates? false)))

        (fn update-conversation [conversation-id]
            (set view.conversation-id conversation-id)
            (set view.conversation (store:get-conversation conversation-id))
            (when (and store store.set-active-conversation-id)
                (store:set-active-conversation-id conversation-id))
            (sync-header-fields))

        (fn ensure-conversation []
            (local active (and store store.get-active-conversation-id
                               (store:get-active-conversation-id)))
            (local requested (or options.conversation-id active))
            (if requested
                (do
                    (store:ensure-conversation requested {:name options.name
                                                          :model options.model
                                                          :temperature options.temperature})
                    (update-conversation requested)
                    (local updates {})
                    (when (not (= options.name nil))
                        (set updates.name options.name))
                    (when (not (= options.model nil))
                        (set updates.model options.model))
                    (when (not (= options.temperature nil))
                        (set updates.temperature options.temperature))
                    (when (and (next updates) view.conversation-id)
                        (store:update-conversation view.conversation-id updates))
                    view.conversation-id)
                (do
                    (local existing (store:list-conversations))
                    (when (> (length existing) 0)
                        (local first (. existing 1))
                        (update-conversation first.id))
                    view.conversation-id)))

        (fn track-items [items]
            (local ids {})
            (each [_ entry (ipairs items)]
                (set (. ids (tostring entry.id)) true))
            (set view.item-ids ids))

        (fn refresh-items []
            (local items
                (if view.conversation-id
                    (build-items store view.conversation-id options)
                    []))
            (track-items items)
            (when (and view.list view.list.set-items)
                (view.list:set-items items)))

        (fn refresh-conversations []
            (local conversations (build-conversations store))
            (when (and view.conversation-list view.conversation-list.set-items)
                (view.conversation-list:set-items conversations)))

        (fn select-conversation [conversation-id]
            (update-conversation conversation-id)
            (refresh-items))

        (fn create-conversation []
            (local created
                (store:create-conversation {:name options.name
                                            :model options.model
                                            :temperature options.temperature}))
            created.id)

        (fn ensure-editable-conversation []
            (if view.conversation-id
                view.conversation-id
                (do
                    (select-conversation (create-conversation))
                    view.conversation-id)))

        (fn update-name-from-input [text]
            (when (not view.suspend-input-updates?)
                (local conversation-id (ensure-editable-conversation))
                (when conversation-id
                    (store:update-conversation conversation-id
                                               {:name (or text "")}))))

        (fn update-temperature-from-input [text]
            (when (not view.suspend-input-updates?)
                (local parsed (parse-temperature text))
                (when (not (= parsed nil))
                    (local conversation-id (ensure-editable-conversation))
                    (when conversation-id
                        (store:update-conversation conversation-id
                                                   {:temperature parsed})))))

        (fn attach-name-input-handler []
            (when (and (not view.__name-input-handler)
                       view.name-input
                       view.name-input.model
                       view.name-input.model.changed)
                (local handler
                    (view.name-input.model.changed:connect
                        (fn [text]
                            (update-name-from-input text))))
                (set view.__name-input-handler handler)
                (table.insert view.handlers {:signal view.name-input.model.changed
                                             :handler handler})))

        (fn attach-temperature-input-handler []
            (when (and (not view.__temperature-input-handler)
                       view.temperature-input
                       view.temperature-input.model
                       view.temperature-input.model.changed)
                (local handler
                    (view.temperature-input.model.changed:connect
                        (fn [text]
                            (update-temperature-from-input text))))
                (set view.__temperature-input-handler handler)
                (table.insert view.handlers {:signal view.temperature-input.model.changed
                                             :handler handler})))

        (fn resolve-menu-position [event]
            (assert (and event event.point)
                    "LlmChatView conversation menu requires event.point")
            event.point)

        (fn archive-conversation [conversation-id]
            (when (and store store.archive-conversation)
                (store:archive-conversation conversation-id))
            (refresh-conversations)
            (when (= conversation-id view.conversation-id)
                (local remaining (store:list-conversations))
                (if (> (length remaining) 0)
                    (do
                        (local first (. remaining 1))
                        (select-conversation first.id))
                    (select-conversation (create-conversation)))))

        (fn handle-send []
            (local text (and view.input view.input.get-text (view.input:get-text)))
            (if (and text (string.match text "%S"))
                (do
                    (when (not view.conversation-id)
                        (select-conversation (create-conversation)))
                    (store:add-message view.conversation-id {:role "user"
                                                             :content text})
                    (when (and view.input view.input.set-text)
                        (view.input:set-text ""))
                    (LlmRequests.run-request store view.conversation-id
                                             {:openai options.openai
                                              :openai-opts options.openai-opts
                                              :tool-registry options.tool-registry
                                              :model options.model
                                              :temperature (and view.conversation
                                                                view.conversation.temperature)
                                              :tools options.tools
                                              :tool-choice options.tool-choice
                                              :parallel-tool-calls options.parallel-tool-calls
                                              :max-tool-rounds options.max-tool-rounds}))))

        (local list-builder
            (ListView {:items []
                       :name "llm-chat-items"
                       :show-head false
                       :paginate false
                       :scroll false
                       :scroll-items-per-page (or options.items-per-page 8)
                       :reverse true
                       :item-spacing 0.3
                       :builder (fn [entry child-ctx]
                                    (build-message-entry entry options child-ctx))}))

        (local conversation-list-builder
            (ListView {:items []
                       :name "llm-chat-conversations"
                       :show-head false
                       :paginate false
                       :scroll true
                       :scroll-items-per-page (or options.conversations-per-page 10)
                       :scrollbar-policy (or options.conversations-scrollbar-policy :as-needed)
                       :reverse true
                       :item-spacing 0.3
                       :builder (fn [entry child-ctx]
                                    (local menu-manager (or options.menu-manager app.menu-manager))
                                    (local menu-entry
                                        (if menu-manager
                                            (do
                                                (local actions [{:name "Archive"
                                                                 :fn (fn [_button _event]
                                                                       (archive-conversation entry.id))}])
                                                (set entry.on-menu
                                                     (fn [_button event]
                                                         (menu-manager:open
                                                           {:actions actions
                                                            :position (resolve-menu-position event)
                                                            :open-button (and event event.button)})))
                                                entry)
                                            entry))
                                    (build-conversation-entry menu-entry child-ctx select-conversation))}))

        (fn build-content [child-ctx]
            (local list (list-builder child-ctx))
            (local list-scroll
                ((ScrollView {:child (fn [_] list)
                              :scrollbar-policy (or options.messages-scrollbar-policy :as-needed)
                              :scrollbar-width options.messages-scrollbar-width})
                 child-ctx))
            (local conversation-list (conversation-list-builder child-ctx))
            (local add-button
                ((Button {:icon "add"
                          :variant :tertiary
                          :padding [0.35 0.35]
                          :xalign :center
                          :yalign :center
                          :focusable? true
                          :on-click (fn [_button _event]
                                        (select-conversation (create-conversation))
                                        (refresh-conversations))})
                 child-ctx))
            (local sidebar-width (or options.sidebar-width 14))
            (local sidebar-body
                ((Flex {:axis 2
                        :reverse true
                        :xalign :stretch
                        :yspacing 0.4
                        :children [(FlexChild (fn [_] add-button) 0)
                                   (FlexChild (fn [_] conversation-list) 1)]})
                 child-ctx))
            (local sidebar
                ((Sized {:size (glm.vec3 sidebar-width 0 0)
                         :child (fn [_] sidebar-body)})
                 child-ctx))
            (local input
                ((Input {:text ""
                         :name "llm-chat-input"
                         :multiline? true
                         :min-lines 2
                         :max-lines 6
                         :min-columns 12
                         :max-columns 60
                         :placeholder "Type a message..."})
                 child-ctx))
            (local name-label ((Label {:text "Name:"}) child-ctx))
            (local name-input
                ((Input {:text ""
                         :name "llm-chat-name"
                         :min-columns 12
                         :max-columns 28
                         :placeholder "Conversation name"})
                 child-ctx))
            (local temperature-label ((Label {:text "Temp:"}) child-ctx))
            (local temperature-input
                ((Input {:text ""
                         :name "llm-chat-temperature"
                         :min-columns 3
                         :max-columns 6
                         :placeholder "0.0"})
                 child-ctx))
            (local header-row
                ((Flex {:axis 1
                        :reverse false
                        :children [(FlexChild (fn [_] name-label) 0)
                                   (FlexChild (fn [_] name-input) 0)
                                   (FlexChild (fn [_] temperature-label) 0)
                                   (FlexChild (fn [_] temperature-input) 0)]})
                 child-ctx))
            (local send-button
                ((Button {:text "Send"
                          :variant :primary
                          :on-click (fn [_button _event]
                                        (handle-send))})
                 child-ctx))
            (local input-row
                ((Flex {:axis 1
                        :reverse false
                        :xalign :stretch
                        :yalign :stretch
                        :xspacing 0.6
                        :children [(FlexChild (fn [_] input) 1)
                                   (FlexChild (fn [_] send-button) 0)]})
                 child-ctx))
            (local content-builder
                (Flex {:axis 2
                       :reverse true
                       :xalign :stretch
                       :yspacing 0.6
                       :children [(FlexChild (fn [_] header-row) 0)
                                  (FlexChild (fn [_] list-scroll) 1)
                                  (FlexChild (fn [_] input-row) 0)]}))
            (local layout-builder
                (Flex {:axis 1
                       :reverse false
                       :xalign :stretch
                       :yalign :stretch
                       :xspacing 0.6
                       :children [(FlexChild (fn [_] sidebar) 0)
                                  (FlexChild (fn [_] (content-builder child-ctx)) 1)]}))
            (local content
                (layout-builder child-ctx))
            (set view.list list)
            (set view.conversation-list conversation-list)
            (set view.conversation-add add-button)
            (set view.input input)
            (set view.name-input name-input)
            (set view.temperature-input temperature-input)
            (set view.send-button send-button)
            (set view.layout content.layout)
            (sync-header-fields)
            (attach-name-input-handler)
            (attach-temperature-input-handler)
            content)

        (set view.refresh refresh-items)

        (when (and store store.conversation-items-changed)
            (local handler
                (store.conversation-items-changed:connect
                    (fn [payload]
                        (when (and payload
                                   (= payload.conversation_id view.conversation-id))
                            (refresh-items)))))
            (table.insert view.handlers {:signal store.conversation-items-changed
                                         :handler handler}))
        (when (and store store.conversation-items-changed)
            (local handler
                (store.conversation-items-changed:connect
                    (fn [_payload]
                        (refresh-conversations))))
            (table.insert view.handlers {:signal store.conversation-items-changed
                                         :handler handler}))
        (when (and store store.message-changed)
            (local handler
                (store.message-changed:connect
                    (fn [record]
                        (when (and record (. view.item-ids (tostring record.id)))
                            (refresh-items)))))
            (table.insert view.handlers {:signal store.message-changed
                                         :handler handler}))
        (when (and store store.conversations-changed)
            (local handler
                (store.conversations-changed:connect
                    (fn [_record]
                        (refresh-conversations))))
            (table.insert view.handlers {:signal store.conversations-changed
                                         :handler handler}))
        (when (and store store.conversation-changed)
            (local handler
                (store.conversation-changed:connect
                    (fn [record]
                        (when (and record view.conversation-id
                                   (= (tostring record.id)
                                      (tostring view.conversation-id)))
                            (set view.conversation record)
                            (sync-header-fields))
                        (refresh-conversations))))
            (table.insert view.handlers {:signal store.conversation-changed
                                         :handler handler}))
        (when (and store store.active-conversation-changed)
            (local handler
                (store.active-conversation-changed:connect
                    (fn [conversation-id]
                        (when (and conversation-id (not (= conversation-id view.conversation-id)))
                            (update-conversation conversation-id)
                            (refresh-items)))))
            (table.insert view.handlers {:signal store.active-conversation-changed
                                         :handler handler}))

        (local dialog
            ((DefaultDialog {:title (or options.title "LLM Chat")
                             :name (or options.name "llm-chat-view")
                             :on-close options.on-close
                             :child build-content})
             ctx))
        (set dialog.__chat-view view)
        (ensure-conversation)
        (refresh-items)
        (refresh-conversations)
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

(local exports {:LlmChatView LlmChatView})

(setmetatable exports {:__call (fn [_ ...]
                                 (LlmChatView ...))})

exports
