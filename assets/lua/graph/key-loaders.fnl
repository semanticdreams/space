(local {:TableNode TableNode} (require :graph/nodes/table))
(local ClassNode (require :graph/nodes/class))
(local EntitiesNode (require :graph/nodes/entities))
(local {:FsNode FsNode} (require :graph/nodes/fs))
(local HackerNewsRootNode (require :graph/nodes/hackernews-root))
(local HackerNewsStoryListNode (require :graph/nodes/hackernews-story-list))
(local HackerNewsStoryNode (require :graph/nodes/hackernews-story))
(local HackerNewsUserNode (require :graph/nodes/hackernews-user))
(local {:register-loader register-link-entity-loader} (require :graph/nodes/link-entity))
(local LinkEntityListNode (require :graph/nodes/link-entity-list))
(local LlmConversationNode (require :graph/nodes/llm-conversation))
(local LlmConversationsNode (require :graph/nodes/llm-conversations))
(local LlmMessageNode (require :graph/nodes/llm-message))
(local LlmModelNode (require :graph/nodes/llm-model))
(local LlmNode (require :graph/nodes/llm))
(local LlmProviderNode (require :graph/nodes/llm-provider))
(local LlmToolCallNode (require :graph/nodes/llm-tool-call))
(local LlmToolNode (require :graph/nodes/llm-tool))
(local LlmToolResultNode (require :graph/nodes/llm-tool-result))
(local LlmToolsNode (require :graph/nodes/llm-tools))
(local ListEntityListNode (require :graph/nodes/list-entity-list))
(local {:register-loader register-list-entity-loader} (require :graph/nodes/list-entity))
(local QuitNode (require :graph/nodes/quit))
(local StartNode (require :graph/nodes/start))
(local {:register-loader register-string-entity-loader} (require :graph/nodes/string-entity))
(local StringEntityListNode (require :graph/nodes/string-entity-list))

(local LinkEntityStore (require :entities/link))
(local ListEntityStore (require :entities/list))
(local StringEntityStore (require :entities/string))
(local LlmStore (require :llm/store))

(local M {})

(fn starts-with? [text prefix]
  (and text prefix
       (= (type text) "string")
       (= (type prefix) "string")
       (= (string.sub text 1 (string.len prefix)) prefix)))

(fn strip-prefix [text prefix]
  (if (starts-with? text prefix)
      (string.sub text (+ 1 (string.len prefix)))
      nil))

(fn non-empty-string? [value]
  (and value (= (type value) "string") (> (string.len value) 0)))

(fn exact-key-loader [expected make-node]
  (assert (non-empty-string? expected) "exact-key-loader requires expected string key")
  (assert (= (type make-node) "function") "exact-key-loader requires make-node function")
  (fn [key]
    (if (= key expected)
        (make-node)
        nil)))

(fn prefix-loader [prefix make-node]
  (assert (non-empty-string? prefix) "prefix-loader requires string prefix")
  (assert (= (type make-node) "function") "prefix-loader requires make-node function")
  (fn [key]
    (local suffix (strip-prefix key prefix))
    (when (non-empty-string? suffix)
      (make-node suffix key))))

(fn require-table-global [name]
  (when (and name (not (string.find name ":" 1 true)))
    (if (= name "_G")
        _G
        (. _G name))))

(fn M.register [graph opts]
  (assert graph "GraphKeyLoaders.register requires graph")
  (assert graph.register-key-loader "GraphKeyLoaders.register requires graph.register-key-loader")
  (local options (or opts {}))

  (local string-store (or options.string-store options.string_store (StringEntityStore.get-default)))
  (local list-store (or options.list-store options.list_store (ListEntityStore.get-default)))
  (local link-store (or options.link-store options.link_store (LinkEntityStore.get-default)))
  (local llm-store (or options.llm-store options.llm_store (LlmStore.get-default)))
  (local hackernews-ensure-client (or options.hackernews-ensure-client options.hackernews_ensure_client))

  (register-string-entity-loader graph {:store string-store})
  (register-list-entity-loader graph {:store list-store})
  (register-link-entity-loader graph {:store link-store})

  (graph:register-key-loader "string-entity-list"
    (exact-key-loader "string-entity-list"
      (fn [] (StringEntityListNode {:store string-store}))))
  (graph:register-key-loader "list-entity-list"
    (exact-key-loader "list-entity-list"
      (fn [] (ListEntityListNode {:store list-store}))))
  (graph:register-key-loader "link-entity-list"
    (exact-key-loader "link-entity-list"
      (fn [] (LinkEntityListNode {:store link-store}))))

  (graph:register-key-loader "entities"
    (exact-key-loader "entities"
      (fn [] (EntitiesNode {}))))
  (graph:register-key-loader "start"
    (exact-key-loader "start"
      (fn [] (StartNode))))
  (graph:register-key-loader "quit"
    (exact-key-loader "quit"
      (fn [] (QuitNode {}))))

  (graph:register-key-loader "class"
    (prefix-loader "class:"
      (fn [id _key]
        (ClassNode {:id id :name id}))))

  (graph:register-key-loader "fs"
    (prefix-loader "fs:"
      (fn [path key]
        (FsNode {:path path :key key}))))

  (graph:register-key-loader "table"
    (prefix-loader "table:"
      (fn [name key]
        (local tbl (require-table-global name))
        (when (= (type tbl) :table)
          (TableNode {:table tbl
                      :label name
                      :key key})))))

  (graph:register-key-loader "llm"
    (exact-key-loader "llm"
      (fn [] (LlmNode))))
  (graph:register-key-loader "llm-provider"
    (exact-key-loader "llm-provider"
      (fn [] (LlmProviderNode {}))))
  (graph:register-key-loader "llm-model"
    (exact-key-loader "llm-model"
      (fn [] (LlmModelNode {}))))
  (graph:register-key-loader "llm-tools"
    (exact-key-loader "llm-tools"
      (fn [] (LlmToolsNode {}))))
  (graph:register-key-loader "llm-conversations"
    (exact-key-loader "llm-conversations"
      (fn [] (LlmConversationsNode {:store llm-store}))))

  (graph:register-key-loader "llm-tool"
    (prefix-loader "llm-tool:"
      (fn [name key]
        (LlmToolNode {:name name :key key}))))

  (graph:register-key-loader "llm-conversation"
    (prefix-loader "llm-conversation:"
      (fn [id key]
        (local record (llm-store:get-conversation id))
        (when record
          (LlmConversationNode {:llm-id id
                                :store llm-store
                                :key key})))))

  (graph:register-key-loader "llm-message"
    (prefix-loader "llm-message:"
      (fn [id key]
        (local record (llm-store:get-item id))
        (when record
          (assert (= record.type "message") (.. "llm-message loader expected record.type == message"))
          (LlmMessageNode {:llm-id id
                           :store llm-store
                           :key key})))))

  (graph:register-key-loader "llm-tool-call"
    (prefix-loader "llm-tool-call:"
      (fn [id key]
        (local record (llm-store:get-item id))
        (when record
          (assert (= record.type "tool-call") (.. "llm-tool-call loader expected record.type == tool-call"))
          (LlmToolCallNode {:llm-id id
                            :store llm-store
                            :key key})))))

  (graph:register-key-loader "llm-tool-result"
    (prefix-loader "llm-tool-result:"
      (fn [id key]
        (local record (llm-store:get-item id))
        (when record
          (assert (= record.type "tool-result") (.. "llm-tool-result loader expected record.type == tool-result"))
          (LlmToolResultNode {:llm-id id
                              :store llm-store
                              :key key})))))

  (graph:register-key-loader "hackernews-root"
    (exact-key-loader "hackernews-root"
      (fn [] (HackerNewsRootNode {:ensure-client hackernews-ensure-client}))))

  (graph:register-key-loader "hackernews-story-list"
    (prefix-loader "hackernews-story-list:"
      (fn [kind key]
        (HackerNewsStoryListNode {:kind kind
                                  :key key
                                  :ensure-client hackernews-ensure-client}))))

  (graph:register-key-loader "hackernews-story"
    (prefix-loader "hackernews-story:"
      (fn [id _key]
        (HackerNewsStoryNode {:id id
                              :ensure-client hackernews-ensure-client}))))

  (graph:register-key-loader "hackernews-user"
    (prefix-loader "hackernews-user:"
      (fn [id _key]
        (HackerNewsUserNode {:id id
                             :ensure-client hackernews-ensure-client}))))
  true)

M
