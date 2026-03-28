(fn normalize-todo-item [item]
  {:text item.text
   :completed item.completed})

(fn normalize-file-change [change]
  {:path change.path
   :kind (if (= change.kind "add")
             :add
             (= change.kind "delete")
             :delete
             (= change.kind "update")
             :update
             :unknown)})

(fn normalize-item [item]
  (when (not (= (type item) :table))
    (error "codex-sdk item payload must be a table"))
  (if (= item.type "agent_message")
      {:id item.id
       :type :agent-message
       :text item.text}
      (= item.type "reasoning")
      {:id item.id
       :type :reasoning
       :text item.text}
      (= item.type "command_execution")
      {:id item.id
       :type :command-execution
       :command item.command
       :aggregated-output item.aggregated_output
       :exit-code item.exit_code
       :status item.status}
      (= item.type "file_change")
      {:id item.id
       :type :file-change
       :changes (icollect [_ change (ipairs (or item.changes []))]
                  (normalize-file-change change))
       :status item.status}
      (= item.type "mcp_tool_call")
      {:id item.id
       :type :mcp-tool-call
       :server item.server
       :tool item.tool
       :arguments item.arguments
       :result (and item.result
                    {:content item.result.content
                     :structured-content item.result.structured_content})
       :error (and item.error
                   {:message item.error.message})
       :status item.status}
      (= item.type "web_search")
      {:id item.id
       :type :web-search
       :query item.query}
      (= item.type "todo_list")
      {:id item.id
       :type :todo-list
       :items (icollect [_ todo (ipairs (or item.items []))]
                (normalize-todo-item todo))}
      (= item.type "error")
      {:id item.id
       :type :error
       :message item.message}
      {:type :unknown-item
       :raw item}))

{:normalize-item normalize-item}
