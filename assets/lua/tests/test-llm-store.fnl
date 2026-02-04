(local LlmStore (require :llm/store))
(local fs (require :fs))
(local json (require :json))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "llm-store"))

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

(fn with-temp-store [f]
    (with-temp-dir
        (fn [root]
            (local store (LlmStore.Store {:base-dir root}))
            (f store root))))

(fn llm-store-creates-and-lists-conversations []
    (with-temp-store
        (fn [store _root]
            (local convo (store:create-conversation {:name "First"}))
            (local items (store:list-conversations))
            (assert (> (length items) 0) "Store should list created conversations")
            (var found nil)
            (each [_ record (ipairs items)]
                (when (= record.id convo.id)
                    (set found record)))
            (assert found "Store should include the created conversation"))))

(fn llm-store-links-items-in-order []
    (with-temp-store
        (fn [store _root]
            (local convo (store:create-conversation {:name "Ordered"}))
            (local first (store:add-message convo.id {:role "user"
                                                      :content "one"}))
            (local second (store:add-tool-call convo.id {:name "tool"
                                                         :arguments "{\"text\":\"two\"}"
                                                         :call-id "call-1"}))
            (local third (store:add-message convo.id {:role "assistant"
                                                      :content "three"}))
            (local items (store:list-conversation-items convo.id))
            (assert (= (length items) 3) "Conversation should contain three items")
            (assert (= (. (. items 1) :id) first.id) "Items should preserve insertion order")
            (assert (= (. (. items 2) :id) second.id) "Items should preserve insertion order")
            (assert (= (. (. items 3) :id) third.id) "Items should preserve insertion order")
            (assert (= (. (. items 1) :order) 1) "First item should have order 1")
            (assert (= (. (. items 2) :order) 2) "Second item should have order 2")
            (assert (= (. (. items 3) :order) 3) "Third item should have order 3")
            (local link-path (fs.join-path store.links-dir (.. convo.id ".json")))
            (assert (fs.exists link-path) "Conversation link file should exist")
            (local (ok content) (pcall fs.read-file link-path))
            (assert ok "Link file should be readable")
            (local (parse-ok payload) (pcall json.loads content))
            (assert parse-ok "Link file should be valid JSON")
            (local link-items (or (. payload :items) []))
            (assert (= (length link-items) 3) "Link file should contain item list")
            (assert (= (. (. link-items 1) :id) first.id) "Link file order should match")
            (assert (= (. (. link-items 2) :id) second.id) "Link file order should match")
            (assert (= (. (. link-items 3) :id) third.id) "Link file order should match"))))

(fn llm-store-reuses-message-across-conversations []
    (with-temp-store
        (fn [store _root]
            (local shared (store:create-item {:type "message"
                                              :role "user"
                                              :content "shared"}))
            (local convo-a (store:create-conversation {:name "A"}))
            (local convo-b (store:create-conversation {:name "B"}))
            (store:link-item convo-a.id shared)
            (store:link-item convo-b.id shared)
            (local items-a (store:list-conversation-items convo-a.id))
            (local items-b (store:list-conversation-items convo-b.id))
            (assert (= (length items-a) 1) "Conversation A should include shared item")
            (assert (= (length items-b) 1) "Conversation B should include shared item")
            (assert (= (. (. items-a 1) :id) shared.id) "Shared item should appear in conversation A")
            (assert (= (. (. items-b 1) :id) shared.id) "Shared item should appear in conversation B"))))

(fn llm-store-archives-conversations []
    (with-temp-store
        (fn [store _root]
            (local convo-a (store:create-conversation {:name "A"}))
            (local convo-b (store:create-conversation {:name "B"}))
            (store:archive-conversation convo-a.id)
            (local visible (store:list-conversations))
            (local visible-ids {})
            (each [_ record (ipairs visible)]
                (set (. visible-ids record.id) true))
            (assert (not (. visible-ids convo-a.id))
                    "Archived conversations should be hidden by default")
            (assert (. visible-ids convo-b.id)
                    "Unarchived conversations should still be listed")
            (local all (store:list-conversations {:include-archived? true}))
            (local all-ids {})
            (each [_ record (ipairs all)]
                (set (. all-ids record.id) true))
            (assert (. all-ids convo-a.id)
                    "Archived conversations should be returned when requested"))))

(fn llm-store-deletes-conversations []
    (with-temp-store
        (fn [store _root]
            (local convo (store:create-conversation {:name "Delete"}))
            (local message (store:add-message convo.id {:role "user"
                                                        :content "hello"}))
            (local call (store:add-tool-call convo.id {:name "tool"
                                                       :arguments "{}"
                                                       :call-id "call-1"}))
            (local result (store:add-tool-result convo.id {:name "tool"
                                                          :output "ok"
                                                          :call-id "call-1"}))
            (local convo-path (fs.join-path store.conversations-dir (.. convo.id ".json")))
            (local link-path (fs.join-path store.links-dir (.. convo.id ".json")))
            (local message-path (fs.join-path store.messages-dir (.. message.id ".json")))
            (local call-path (fs.join-path store.messages-dir (.. call.id ".json")))
            (local result-path (fs.join-path store.messages-dir (.. result.id ".json")))
            (assert (fs.exists convo-path) "Conversation file should exist before delete")
            (assert (fs.exists link-path) "Link file should exist before delete")
            (assert (fs.exists message-path) "Message file should exist before delete")
            (assert (fs.exists call-path) "Tool call file should exist before delete")
            (assert (fs.exists result-path) "Tool result file should exist before delete")
            (store:delete-conversation convo.id)
            (assert (not (fs.exists convo-path)) "Conversation file should be removed")
            (assert (not (fs.exists link-path)) "Link file should be removed")
            (assert (not (fs.exists message-path)) "Message file should be removed")
            (assert (not (fs.exists call-path)) "Tool call file should be removed")
            (assert (not (fs.exists result-path)) "Tool result file should be removed")
            (local remaining (store:list-conversations {:include-archived? true}))
            (assert (= (length remaining) 0) "Deleted conversation should be removed from list"))))

(table.insert tests {:name "llm store creates and lists conversations"
                     :fn llm-store-creates-and-lists-conversations})
(table.insert tests {:name "llm store links items in order"
                     :fn llm-store-links-items-in-order})
(table.insert tests {:name "llm store reuses messages across conversations"
                     :fn llm-store-reuses-message-across-conversations})
(table.insert tests {:name "llm store archives conversations"
                     :fn llm-store-archives-conversations})
(table.insert tests {:name "llm store deletes conversations"
                     :fn llm-store-deletes-conversations})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "llm-store"
                       :tests tests})))

{:name "llm-store"
 :tests tests
 :main main}
