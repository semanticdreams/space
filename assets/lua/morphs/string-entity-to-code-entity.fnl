(local CodeEntityStore (require :entities/code))
(local IdentityStore (require :entities/identity))
(local StringEntityStore (require :entities/string))
(local KeyLoaderUtils (require :graph/key-loader-utils))

(local STRING_KEY_PREFIX (KeyLoaderUtils.key-prefix "string-entity"))
(local CODE_KEY_PREFIX (KeyLoaderUtils.key-prefix "code-entity"))

(fn extract-string-entity-id [node]
  (if (and node node.entity-id)
      (tostring node.entity-id)
      (do
        (local key (or (and node node.key) ""))
        (if (= (string.sub key 1 (string.len STRING_KEY_PREFIX)) STRING_KEY_PREFIX)
            (string.sub key (+ 1 (string.len STRING_KEY_PREFIX)))
            nil))))

(fn update-identities [identity-store old-key new-key]
  (local updated-identity-keys [])
  (each [_ entity (ipairs (identity-store:list-entities))]
    (when (= (tostring (or entity.target-key "")) (tostring old-key))
      (identity-store:update-entity entity.id {:target-key new-key})
      (table.insert updated-identity-keys (.. "identity:" (tostring entity.id)))))
  updated-identity-keys)

(fn run-morph [ctx]
  (local source-node (and ctx ctx.source-node))
  (assert source-node "string->code morph requires source-node")
  (assert source-node.key "string->code morph requires source-node.key")
  (local source-key (tostring source-node.key))
  (local source-id (extract-string-entity-id source-node))
  (assert source-id "string->code morph requires string-entity source")

  (local string-store (or (and ctx ctx.options ctx.options.string-store)
                          (StringEntityStore.get-default)))
  (local code-store (or (and ctx ctx.options ctx.options.code-store)
                        (CodeEntityStore.get-default)))
  (local identity-store (or (and ctx ctx.options ctx.options.identity-store)
                            (IdentityStore.get-default)))

  (local string-entity (string-store:get-entity source-id))
  (assert string-entity (.. "string->code morph missing source entity " source-id))

  (local code-entity
    (code-store:create-entity {:name ""
                               :language "fnl"
                               :source (or string-entity.value "")}))
  (local code-key (.. CODE_KEY_PREFIX (tostring code-entity.id)))

  (local updated-identities (update-identities identity-store source-key code-key))
  (string-store:delete-entity source-id)

  {:code-entity code-entity
   :code-key code-key
   :target-key code-key
   :target-type "code-entity"
   :updated-identity-keys updated-identities
   :source-key source-key
   :source-id source-id})

(fn register [morphs]
  (assert morphs "register string->code morph requires morphs registry")
  (morphs:register "string-entity" "code-entity" run-morph
                   {:label "code-entity"}))

register
