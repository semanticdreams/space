(local OpenAIProvider (require :llm/conversations/providers/openai))
(local ZaiProvider (require :llm/conversations/providers/zai))

(local providers {:openai OpenAIProvider
                  :zai ZaiProvider})

(fn resolve-provider-id [options conversation]
  (or (and options options.provider)
      (and conversation conversation.provider)
      "openai"))

(fn get-provider [provider-id]
  (local provider (. providers provider-id))
  (if provider
      provider
      (error (.. "Unsupported LLM provider: " (tostring provider-id)))))

{:resolve-provider-id resolve-provider-id
 :get-provider get-provider}
