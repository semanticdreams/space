(fn require-function [value message]
  (assert (= (type value) "function") message)
  value)

(fn require-runtime-function [ctx key]
  (assert ctx "agent chat step requires workflow context")
  (local runtime (assert ctx.runtime "agent chat step requires ctx.runtime"))
  (require-function (. runtime key)
                    (.. "agent chat step requires ctx.runtime." (tostring key))))

(fn table-or-empty [value]
  (if (= value nil) {} value))

(fn AgentChatStep [config]
  (local options (table-or-empty config))
  {:run (fn [_self ctx _input _state]
          (assert ctx "agent chat step run requires workflow context")
          (require-function ctx.wait "agent chat step run requires ctx:wait")
          (ctx:wait :agent-user-input {:agent-id options.agent-id}))
   :resume (fn [_self ctx wait-result state]
             (local run-agent-turn (require-runtime-function ctx :run-agent-turn))
             (run-agent-turn ctx.runtime ctx wait-result state))
   :cancel (fn [_self ctx state]
             (assert ctx "agent chat step cancel requires workflow context")
             (local runtime ctx.runtime)
             (when (and runtime runtime.cancel-agent-turn)
               (require-function runtime.cancel-agent-turn
                                 "agent chat step cancel requires ctx.runtime.cancel-agent-turn to be a function")
               (runtime.cancel-agent-turn runtime ctx state))
             (require-function ctx.cancelled "agent chat step cancel requires ctx:cancelled")
             (ctx:cancelled {:cancelled true}))})

{:AgentChatStep AgentChatStep}
