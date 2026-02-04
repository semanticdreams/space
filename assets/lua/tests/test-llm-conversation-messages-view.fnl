(local _ (require :main))
(local LlmConversationMessagesView (require :llm-conversation-messages-view))
(local LlmStore (require :llm/store))
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
(local temp-root (fs.join-path "/tmp/space/tests" "llm-conversation-messages-view"))

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

(fn llm-conversation-messages-view-switches-branches []
  (with-temp-dir
    (fn [root]
      (local store (LlmStore.Store {:base-dir root}))
      (local conversation (store:create-conversation {:name "Branches"}))
      (local root-msg (store:add-message conversation.id {:role "user"
                                                          :content "root"}))
      (local left (store:add-message conversation.id {:role "assistant"
                                                      :content "left"
                                                      :parent-id root-msg.id}))
      (store:add-message conversation.id {:role "user"
                                          :content "left-child"
                                          :parent-id left.id})
      (local right (store:add-message conversation.id {:role "assistant"
                                                       :content "right"
                                                       :parent-id root-msg.id}))
      (store:add-message conversation.id {:role "user"
                                          :content "right-child"
                                          :parent-id right.id})
      (local ctx (make-test-ctx))
      (local dialog
        ((LlmConversationMessagesView {:store store
                                       :conversation-id conversation.id})
         ctx))
      (local view (and dialog dialog.__messages-view))
      (assert view "Dialog should expose __messages-view state")

      (var items view.list.items)
      (assert (= (length items) 3) "Default path should contain three messages")
      (local first (. items 1))
      (local second (. items 2))
      (local third (. items 3))
      (assert (= (and first (. (. first :record) :content)) "root")
              "First entry should be the root message")
      (assert (= (and second (. (. second :record) :content)) "left")
              "Default branch should choose the left subtree")
      (assert (= (and third (. (. third :record) :content)) "left-child")
              "Default branch should include left subtree descendants")

      (local second-row (. view.list.item-widgets 2))
      (assert second-row "Second row should exist")
      (assert second-row.right-button "Left entry should include a right sibling button")
      (second-row.right-button:on-click {})
      (set items view.list.items)
      (local shifted-second (. items 2))
      (local shifted-third (. items 3))
      (assert (= (and shifted-second (. (. shifted-second :record) :content)) "right")
              "Right click should shift to the right sibling")
      (assert (= (and shifted-third (. (. shifted-third :record) :content)) "right-child")
              "Sibling shift should update all descendants below the branch point")

      (local shifted-row (. view.list.item-widgets 2))
      (assert shifted-row.left-button "Right entry should include a left sibling button")
      (shifted-row.left-button:on-click {})
      (set items view.list.items)
      (local restored-second (. items 2))
      (assert (= (and restored-second (. (. restored-second :record) :content)) "left")
              "Left click should shift back to the left sibling")

      (dialog:drop))))

(table.insert tests {:name "LlmConversationMessagesView switches sibling branches"
                     :fn llm-conversation-messages-view-switches-branches})

(fn llm-conversation-messages-view-disconnects-on-drop []
  (with-temp-dir
    (fn [root]
      (local store (LlmStore.Store {:base-dir root}))
      (local conversation (store:create-conversation {:name "Refresh"}))
      (local msg (store:add-message conversation.id {:role "user"
                                                     :content "hello"}))
      (local ctx (make-test-ctx))
      (local dialog
        ((LlmConversationMessagesView {:store store
                                       :conversation-id conversation.id})
         ctx))
      (local view (and dialog dialog.__messages-view))
      (assert view "Dialog should expose __messages-view state")

      (var refresh-count 0)
      (local original-set-items view.list.set-items)
      (set view.list.set-items
           (fn [self items]
             (set refresh-count (+ refresh-count 1))
             (original-set-items self items)))

      (store:update-item msg.id {:content "updated"})
      (assert (> refresh-count 0) "View should refresh when a conversation message changes")

      (local refresh-after refresh-count)
      (dialog:drop)
      (store:update-item msg.id {:content "after-drop"})
      (assert (= refresh-count refresh-after)
              "View should disconnect from store signals on drop"))))

(table.insert tests {:name "LlmConversationMessagesView disconnects on drop"
                     :fn llm-conversation-messages-view-disconnects-on-drop})

{:name "test-llm-conversation-messages-view"
 :tests tests}
