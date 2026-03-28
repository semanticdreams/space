(local Items (require :codex-sdk/items))

(fn normalize-usage [usage]
  (if usage
      {:input-tokens usage.input_tokens
       :cached-input-tokens usage.cached_input_tokens
       :output-tokens usage.output_tokens}
      nil))

(fn normalize-event [event]
  (when (not (= (type event) :table))
    (error "codex-sdk event payload must be a table"))
  (if (= event.type "thread.started")
      {:type :thread-started
       :thread-id event.thread_id}
      (= event.type "turn.started")
      {:type :turn-started}
      (= event.type "turn.completed")
      {:type :turn-completed
       :usage (normalize-usage event.usage)}
      (= event.type "turn.failed")
      {:type :turn-failed
       :error {:message (. event.error :message)}}
      (= event.type "item.started")
      {:type :item-started
       :item (Items.normalize-item event.item)}
      (= event.type "item.updated")
      {:type :item-updated
       :item (Items.normalize-item event.item)}
      (= event.type "item.completed")
      {:type :item-completed
       :item (Items.normalize-item event.item)}
      (= event.type "error")
      {:type :error
       :message event.message}
      {:type :unknown-event
       :raw event}))

{:normalize-event normalize-event
 :normalize-usage normalize-usage}
