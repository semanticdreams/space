(local _ (require :main))
(local LlmChatView (require :llm-chat-view))
(local LlmRequests (require :llm/requests))
(local LlmStore (require :llm/store))
(local glm (require :glm))
(local fs (require :fs))

(local tests [])

(fn make-vector-buffer []
  (local buffer {})
  (set buffer.allocate (fn [_self _count] 1))
  (set buffer.delete (fn [_self _handle] nil))
  (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
  (set buffer.set-float (fn [_self _handle _offset _value] nil))
  buffer)

(fn make-icons-stub []
  (local glyph {:advance 1
                :planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}
               :advance 1})
  (local stub {:font font
               :codepoints {:move_item 4242
                            :add 4242
                            :close 4242}})
  (set stub.get
       (fn [self name]
         (local value (. self.codepoints name))
         (assert value (.. "Missing icon " name))
         value))
  (set stub.resolve
       (fn [self name]
         (local code (self:get name))
         {:type :font
          :codepoint code
          :font self.font}))
  stub)

(fn make-clickables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  (set stub.register-right-click (fn [_self _obj] nil))
  (set stub.unregister-right-click (fn [_self _obj] nil))
  (set stub.register-double-click (fn [_self _obj] nil))
  (set stub.unregister-double-click (fn [_self _obj] nil))
  stub)

(fn make-hoverables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  stub)

(fn make-system-cursors-stub []
  (local stub {})
  (set stub.set-cursor (fn [_self _name] nil))
  (set stub.reset (fn [_self] nil))
  stub)

(fn make-test-ctx []
  (local triangle (make-vector-buffer))
  (local text-buffer (make-vector-buffer))
  (local ctx {:triangle-vector triangle
              :pointer-target {}})
  (set ctx.get-text-vector (fn [_self _font] text-buffer))
  (set ctx.track-text-handle (fn [_self _font _handle _clip] nil))
  (set ctx.untrack-text-handle (fn [_self _font _handle] nil))
  (set ctx.clickables (make-clickables-stub))
  (set ctx.hoverables (make-hoverables-stub))
  (set ctx.system-cursors (make-system-cursors-stub))
  (set ctx.icons (make-icons-stub))
  ctx)

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "llm-chat-view"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "llm-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn llm-chat-view-updates-on-conversation-change []
  (with-temp-dir
    (fn [root]
      (local store (LlmStore.Store {:base-dir root}))
      (local conversation (store:create-conversation {:name "Test"}))
      (store:set-active-conversation-id conversation.id)
      (local ctx (make-test-ctx))
      (local dialog ((LlmChatView {:store store}) ctx))
      (local view (and dialog dialog.__chat-view))
      (assert view "LlmChatView should expose chat view state on dialog")
      (var refresh-count 0)
      (local original-set-items view.list.set-items)
      (set view.list.set-items
           (fn [self items]
             (set refresh-count (+ refresh-count 1))
             (original-set-items self items)))

      (store:add-message conversation.id {:role "user"
                                          :content "hello"})
      (assert (> refresh-count 0) "LlmChatView should refresh on conversation change")

      (local refresh-after refresh-count)
      (dialog:drop)
      (store:add-message conversation.id {:role "user"
                                          :content "after-drop"})
      (assert (= refresh-count refresh-after)
              "LlmChatView should disconnect from conversation changes on drop"))))

(table.insert tests {:name "LlmChatView refreshes from conversation changes"
                     :fn llm-chat-view-updates-on-conversation-change})

(fn llm-chat-view-conversation-sidebar []
  (with-temp-dir
    (fn [root]
      (local store (LlmStore.Store {:base-dir root}))
      (local convo-a (store:create-conversation {:name "Alpha"
                                                 :created-at 100
                                                 :updated-at 100}))
      (store:add-message convo-a.id {:role "user"
                                     :content "Hello there world"})
      (local convo-b (store:create-conversation {:name "Beta"
                                                 :created-at 200
                                                 :updated-at 200}))
      (store:add-message convo-b.id {:role "user"
                                     :content "Second message"})
      (store:set-active-conversation-id convo-a.id)
      (local ctx (make-test-ctx))
      (local dialog ((LlmChatView {:store store}) ctx))
      (local view (and dialog dialog.__chat-view))
      (assert view "LlmChatView should expose chat view state on dialog")
      (local items view.conversation-list.items)
      (local first-item (. items 1))
      (local second-item (. items 2))
      (assert (= (length items) 2) "Conversation sidebar should list conversations")
      (assert (= first-item.id convo-b.id) "Conversation list should be ordered by recency")
      (assert (= first-item.label "Beta") "Conversation label should prefer name when set")
      (assert (= second-item.label "Alpha") "Conversation label should prefer name when set")
      (local first-row (. view.conversation-list.item-widgets 1))
      (local first-button (and first-row first-row.child))
      (assert first-button "Conversation item should contain a button")
      (first-button.clicked:emit {})
      (assert (= view.conversation-id convo-b.id)
              "Clicking a conversation should update the active conversation")
      (local active-message (. view.list.items 1))
      (assert (= active-message.record.content "Second message")
              "Chat items should refresh to the selected conversation")
      (dialog:drop))))

(table.insert tests {:name "LlmChatView conversation sidebar"
                     :fn llm-chat-view-conversation-sidebar})

(fn llm-chat-view-conversation-menu []
  (with-temp-dir
    (fn [root]
      (local store (LlmStore.Store {:base-dir root}))
      (local conversation (store:create-conversation {:name "Menu"}))
      (store:add-message conversation.id {:role "user"
                                          :content "Menu item"})
      (store:set-active-conversation-id conversation.id)
      (var opened nil)
      (local menu-manager
        {:open (fn [self opts]
                 (set opened opts))})
      (local ctx (make-test-ctx))
      (local dialog ((LlmChatView {:store store
                                   :menu-manager menu-manager})
                     ctx))
      (local view (and dialog dialog.__chat-view))
      (assert view "LlmChatView should expose chat view state on dialog")
      (local row (. view.conversation-list.item-widgets 1))
      (local button (and row row.child))
      (assert button "Conversation item should contain a button")
      (button:on-right-click {:point (glm.vec3 1 2 0)
                              :button 3})
      (assert opened "Conversation menu should open on right click")
      (assert (= (length opened.actions) 1) "Conversation menu should have one action")
      (local action (. opened.actions 1))
      (assert (= action.name "Archive")
              "Conversation menu should include Archive action")
      (assert (= opened.open-button 3) "Conversation menu should track click button")
      (dialog:drop))))

(table.insert tests {:name "LlmChatView conversation context menu"
                     :fn llm-chat-view-conversation-menu})

(fn llm-chat-view-does-not-auto-create []
  (with-temp-dir
    (fn [root]
      (local store (LlmStore.Store {:base-dir root}))
      (local ctx (make-test-ctx))
      (local dialog ((LlmChatView {:store store}) ctx))
      (local view (and dialog dialog.__chat-view))
      (assert view "LlmChatView should expose chat view state on dialog")
      (assert (= view.conversation-id nil) "LlmChatView should not auto-create a conversation")
      (assert (= (length view.conversation-list.items) 0)
              "Conversation list should start empty")
      (local add-button view.conversation-add)
      (assert add-button "LlmChatView should expose add conversation button")
      (add-button:on-click {})
      (assert view.conversation-id "Add button should create and select a conversation")
      (assert (= (length view.conversation-list.items) 1)
              "Conversation list should include newly created conversation")
      (dialog:drop))))

(table.insert tests {:name "LlmChatView does not auto-create conversation"
                     :fn llm-chat-view-does-not-auto-create})

(fn llm-chat-view-metadata-row []
  (with-temp-dir
    (fn [root]
      (local store (LlmStore.Store {:base-dir root}))
      (local conversation (store:create-conversation {:name "Alpha"
                                                      :temperature 0.2}))
      (store:set-active-conversation-id conversation.id)
      (local ctx (make-test-ctx))
      (local dialog ((LlmChatView {:store store}) ctx))
      (local view (and dialog dialog.__chat-view))
      (assert view "LlmChatView should expose chat view state on dialog")
      (assert view.name-input "LlmChatView should expose name input")
      (assert view.temperature-input "LlmChatView should expose temperature input")
      (assert (= (view.name-input:get-text) "Alpha")
              "Name input should reflect conversation name")
      (assert (= (tonumber (view.temperature-input:get-text)) 0.2)
              "Temperature input should reflect conversation temperature")
      (view.name-input:set-text "Beta")
      (local updated (store:get-conversation conversation.id))
      (assert (= updated.name "Beta") "Editing name should update conversation")
      (view.temperature-input:set-text "0.7")
      (local updated-temp (store:get-conversation conversation.id))
      (assert (= updated-temp.temperature 0.7)
              "Editing temperature should update conversation")
      (dialog:drop))))

(table.insert tests {:name "LlmChatView metadata row updates conversation"
                     :fn llm-chat-view-metadata-row})

(fn llm-chat-view-sends-conversation-temperature []
  (with-temp-dir
    (fn [root]
      (local store (LlmStore.Store {:base-dir root}))
      (local conversation (store:create-conversation {:name "Alpha"
                                                      :temperature 0.4}))
      (store:set-active-conversation-id conversation.id)
      (local ctx (make-test-ctx))
      (var captured nil)
      (local original-run LlmRequests.run-request)
      (set LlmRequests.run-request
           (fn [_store _conversation-id opts]
             (set captured opts)))
      (local dialog ((LlmChatView {:store store}) ctx))
      (local view (and dialog dialog.__chat-view))
      (assert view "LlmChatView should expose chat view state on dialog")
      (view.temperature-input:set-text "0.9")
      (view.input:set-text "Hello")
      (view.send-button:on-click {})
      (set LlmRequests.run-request original-run)
      (assert captured "Send should invoke LlmRequests.run-request")
      (assert (= captured.temperature 0.9)
              "Send should pass conversation temperature to OpenAI")
      (dialog:drop))))

(table.insert tests {:name "LlmChatView send uses conversation temperature"
                     :fn llm-chat-view-sends-conversation-temperature})

tests
