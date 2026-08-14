(local {:TableNode TableNode} (require :graph/nodes/table))
(local ClassNode (require :graph/nodes/class))
(local {:register-loader register-code-entity-loader} (require :graph/nodes/code-entity))
(local CodeDirNode (require :graph/nodes/code-dir))
(local CppModuleNode (require :graph/nodes/cpp-module))
(local EntitiesNode (require :graph/nodes/entities))
(local FnlModuleNode (require :graph/nodes/fnl-module))
(local {:FsNode FsNode} (require :graph/nodes/fs))
(local HackerNewsRootNode (require :graph/nodes/hackernews-root))
(local HackerNewsStoryListNode (require :graph/nodes/hackernews-story-list))
(local HackerNewsStoryNode (require :graph/nodes/hackernews-story))
(local HackerNewsUserNode (require :graph/nodes/hackernews-user))
(local {:register-loader register-identity-loader} (require :graph/nodes/identity))
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
(local NotebooksNode (require :graph/nodes/notebooks))
(local {:register-loader register-notebook-loader} (require :graph/nodes/notebook))
(local KernelsNode (require :graph/nodes/kernels))
(local {:KernelNode KernelNode} (require :graph/nodes/kernel))
(local {:KernelInstanceNode KernelInstanceNode} (require :graph/nodes/kernel-instance))
(local QuitNode (require :graph/nodes/quit))
(local StartNode (require :graph/nodes/start))
(local {:register-loader register-string-entity-loader} (require :graph/nodes/string-entity))
(local StringEntityListNode (require :graph/nodes/string-entity-list))
(local TextModuleNode (require :graph/nodes/text-module))
(local {:WorldsNode WorldsNode} (require :graph/nodes/worlds))
(local {:WorldNode WorldNode} (require :graph/nodes/world))
(local {:WorldActivitiesNode WorldActivitiesNode} (require :graph/nodes/world-activities))
(local {:WorldActivityNode WorldActivityNode} (require :graph/nodes/world-activity))
(local {:ActivitySurfacesNode ActivitySurfacesNode} (require :graph/nodes/activity-surfaces))
(local {:ActivitySurfaceNode ActivitySurfaceNode} (require :graph/nodes/activity-surface))
(local {:ScenePanelsNode ScenePanelsNode} (require :graph/nodes/scene-panels))
(local {:HudPanelsNode HudPanelsNode} (require :graph/nodes/hud-panels))
(local {:TerrainsNode TerrainsNode} (require :graph/nodes/terrains))
(local {:SkyboxNode SkyboxNode} (require :graph/nodes/skybox))
(local {:BackgroundNode BackgroundNode} (require :graph/nodes/background))
(local {:LightsNode LightsNode} (require :graph/nodes/lights))
(local {:LightTypeNode LightTypeNode} (require :graph/nodes/light-type))
(local {:LightNode LightNode} (require :graph/nodes/light))
(local {:ScenePanelNode ScenePanelNode} (require :graph/nodes/scene-panel))
(local {:HudPanelNode HudPanelNode} (require :graph/nodes/hud-panel))
(local {:TerrainNode TerrainNode} (require :graph/nodes/terrain))
(local TerrainEditors (require :graph/terrain-editors))
(local TerrainTools (require :graph/terrain-tools))
 (local WorldData (require :graph/world-data))
(local {:register-loader register-workflows-loader} (require :graph/nodes/workflows))
(local {:register-loader register-workflow-definition-loader} (require :graph/nodes/workflow-definition))
(local {:register-loader register-workflow-step-loader} (require :graph/nodes/workflow-step))
(local {:register-loader register-workflow-run-loader} (require :graph/nodes/workflow-run))
(local {:register-loader register-workflow-run-step-loader} (require :graph/nodes/workflow-run-step))
(local {:register-loader register-workflow-run-event-loader} (require :graph/nodes/workflow-run-event))

(local LinkEntityStore (require :entities/link))
(local CodeEntityStore (require :entities/code))
(local IdentityStore (require :entities/identity))
(local ListEntityStore (require :entities/list))
(local NotebookStore (require :notebooks/store))
(local StringEntityStore (require :entities/string))
(local LlmStore (require :llm/conversations/store))
(local Kernels (require :kernels))
(local fs (require :fs))

(local M {})

(fn split-key-parts [text]
  (assert text "split-key-parts requires text")
  (local parts [])
  (each [part (string.gmatch text "[^:]+")]
    (table.insert parts part))
  parts)

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

(fn existing-path-loader [prefix kind make-node]
  (assert (non-empty-string? prefix) "existing-path-loader requires string prefix")
  (assert (= (type make-node) "function") "existing-path-loader requires make-node function")
  (fn [key]
    (local path (strip-prefix key prefix))
    (when (non-empty-string? path)
      (local stat (and fs.stat (fs.stat path)))
      (when (and stat stat.exists
                 (if (= kind :dir) stat.is-dir stat.is-file))
        (make-node path key)))))

(fn existing-any-path-loader [prefix make-node]
  (assert (non-empty-string? prefix) "existing-any-path-loader requires string prefix")
  (assert (= (type make-node) "function") "existing-any-path-loader requires make-node function")
  (fn [key]
    (local path (strip-prefix key prefix))
    (when (non-empty-string? path)
      (local stat (and fs.stat (fs.stat path)))
      (when (and stat stat.exists)
        (make-node path key)))))

(fn activity-surface-key [surface-key]
  (if (= surface-key "scene") "activity-scene"
      (= surface-key "hud") "activity-hud"
      (= surface-key "canvas") "activity-canvas"
      (error (.. "unsupported activity surface " (tostring surface-key)))))

(fn activity-pair-loader [prefix make-node]
  (assert (non-empty-string? prefix) "activity-pair-loader requires string prefix")
  (assert (= (type make-node) "function") "activity-pair-loader requires make-node function")
  (prefix-loader prefix
    (fn [rest key]
      (local parts (split-key-parts rest))
      (when (= (length parts) 2)
        (make-node (. parts 1) (. parts 2) key)))))

(fn activity-triple-loader [prefix make-node]
  (assert (non-empty-string? prefix) "activity-triple-loader requires string prefix")
  (assert (= (type make-node) "function") "activity-triple-loader requires make-node function")
  (prefix-loader prefix
    (fn [rest key]
      (local parts (split-key-parts rest))
      (when (= (length parts) 3)
        (make-node (. parts 1) (. parts 2) (. parts 3) key)))))

(fn activity-quad-loader [prefix make-node]
  (assert (non-empty-string? prefix) "activity-quad-loader requires string prefix")
  (assert (= (type make-node) "function") "activity-quad-loader requires make-node function")
  (prefix-loader prefix
    (fn [rest key]
      (local parts (split-key-parts rest))
      (when (= (length parts) 4)
        (make-node (. parts 1) (. parts 2) (. parts 3) (. parts 4) key)))))

(fn require-table-global [name]
  (when (and name (not (string.find name ":" 1 true)))
    (if (= name "_G")
        _G
        (. _G name))))

(fn make-activity-surface-loader [world-manager asset-path-resolver surface-key]
  (activity-pair-loader (.. (activity-surface-key surface-key) ":")
    (fn [world-id activity-id key]
      (local surface-state
        (and world-manager
             (WorldData.resolve-activity-surface-state world-manager world-id activity-id surface-key)))
      (when surface-state
        (ActivitySurfaceNode {:world-id world-id
                              :activity-id activity-id
                              :surface-key surface-key
                              :world-manager world-manager
                              :asset-path-resolver asset-path-resolver
                              :key key})))))

(fn resolve-activity-scene [world-manager world-id activity-id]
  (and world-manager
       (WorldData.resolve-activity-surface-state world-manager world-id activity-id "scene")))

(fn register-activity-scene-category-loaders [graph world-manager asset-path-resolver]
  (graph:register-key-loader "activity-scene-panels"
    (activity-pair-loader "activity-scene-panels:"
      (fn [world-id activity-id key]
        (when (resolve-activity-scene world-manager world-id activity-id)
          (ScenePanelsNode {:world-id world-id :activity-id activity-id :world-manager world-manager :key key})))))
  (graph:register-key-loader "activity-terrains"
    (activity-pair-loader "activity-terrains:"
      (fn [world-id activity-id key]
        (when (resolve-activity-scene world-manager world-id activity-id)
          (TerrainsNode {:world-id world-id :activity-id activity-id :world-manager world-manager :key key})))))
  (graph:register-key-loader "activity-skybox"
    (activity-pair-loader "activity-skybox:"
      (fn [world-id activity-id key]
        (when (resolve-activity-scene world-manager world-id activity-id)
          (SkyboxNode {:world-id world-id :activity-id activity-id :world-manager world-manager :asset-path-resolver asset-path-resolver :key key})))))
  (graph:register-key-loader "activity-background"
    (activity-pair-loader "activity-background:"
      (fn [world-id activity-id key]
        (when (resolve-activity-scene world-manager world-id activity-id)
          (BackgroundNode {:world-id world-id :activity-id activity-id :world-manager world-manager :key key})))))
  (graph:register-key-loader "activity-lights"
    (activity-pair-loader "activity-lights:"
      (fn [world-id activity-id key]
        (when (resolve-activity-scene world-manager world-id activity-id)
          (LightsNode {:world-id world-id :activity-id activity-id :world-manager world-manager :key key}))))))

(fn register-activity-scene-child-loaders [graph world-manager]
  (graph:register-key-loader "activity-scene-panel"
    (activity-triple-loader "activity-scene-panel:"
      (fn [world-id activity-id index-text key]
        (local panel-index (tonumber index-text))
        (local panel-entry (and panel-index (resolve-activity-scene world-manager world-id activity-id)
                                (WorldData.find-scene-panel world-manager world-id activity-id panel-index)))
        (when panel-entry
          (ScenePanelNode {:world-id world-id :activity-id activity-id :world-manager world-manager :panel-index panel-index :panel-entry panel-entry :key key})))))
  (graph:register-key-loader "activity-terrain"
    (activity-triple-loader "activity-terrain:"
      (fn [world-id activity-id terrain-id key]
        (local terrain-entry (and (resolve-activity-scene world-manager world-id activity-id)
                                  (WorldData.find-terrain world-manager world-id activity-id terrain-id)))
        (when terrain-entry
          (TerrainNode {:world-id world-id :activity-id activity-id :world-manager world-manager :terrain-id terrain-id :terrain-entry terrain-entry :key key})))))
  (graph:register-key-loader "activity-light-type"
    (activity-triple-loader "activity-light-type:"
      (fn [world-id activity-id type-key key]
        (when (resolve-activity-scene world-manager world-id activity-id)
          (LightTypeNode {:world-id world-id :activity-id activity-id :world-manager world-manager :type-key type-key :key key})))))
  (graph:register-key-loader "activity-light"
    (activity-quad-loader "activity-light:"
      (fn [world-id activity-id type-key light-id key]
        (local light-entry (and (resolve-activity-scene world-manager world-id activity-id)
                                (WorldData.find-light world-manager world-id activity-id type-key light-id)))
        (when light-entry
          (LightNode {:world-id world-id :activity-id activity-id :world-manager world-manager :type-key type-key :light-id light-id :light-entry light-entry :key key}))))))

(fn register-activity-terrain-action-loaders [graph world-manager]
  (graph:register-key-loader "activity-terrain-editor"
    (activity-triple-loader "activity-terrain-editor:"
      (fn [world-id activity-id terrain-id key]
        (local terrain-entry (and (resolve-activity-scene world-manager world-id activity-id)
                                  (WorldData.find-terrain world-manager world-id activity-id terrain-id)))
        (when terrain-entry
          (TerrainEditors.create-editor-node {:world-id world-id :activity-id activity-id :world-manager world-manager :terrain-id terrain-id :terrain-entry terrain-entry :key key})))))
  (graph:register-key-loader "activity-terrain-tool"
    (activity-quad-loader "activity-terrain-tool:"
      (fn [world-id activity-id terrain-id tool-id key]
        (local terrain-entry (and (resolve-activity-scene world-manager world-id activity-id)
                                  (WorldData.find-terrain world-manager world-id activity-id terrain-id)))
        (local terrain-kind (and terrain-entry terrain-entry.kind))
        (when terrain-kind
          (TerrainTools.create-tool-node {:world-id world-id :activity-id activity-id :world-manager world-manager :terrain-id terrain-id :terrain-kind terrain-kind :tool-id tool-id :key key}))))))

(fn register-activity-hierarchy-loaders [graph world-manager asset-path-resolver]
  (graph:register-key-loader "world-activities"
    (prefix-loader "world-activities:"
      (fn [world-id key]
        (local world-entry (and world-manager
                               (WorldData.resolve-world-entry world-manager world-id)))
        (when world-entry
          (WorldActivitiesNode {:world-id world-id
                                :world-manager world-manager
                                :key key})))))
  (graph:register-key-loader "world-activity"
    (activity-pair-loader "world-activity:"
      (fn [world-id activity-id key]
        (local session (and world-manager
                            (WorldData.resolve-activity-session world-manager world-id activity-id)))
        (when session
          (WorldActivityNode {:world-id world-id
                              :activity-id activity-id
                              :world-manager world-manager
                              :key key})))))
  (graph:register-key-loader "activity-surfaces"
    (activity-pair-loader "activity-surfaces:"
      (fn [world-id activity-id key]
        (local session (and world-manager
                            (WorldData.resolve-activity-session world-manager world-id activity-id)))
        (when session
          (ActivitySurfacesNode {:world-id world-id
                                 :activity-id activity-id
                                 :world-manager world-manager
                                 :asset-path-resolver asset-path-resolver
                                 :key key})))))
  (each [_ surface-key (ipairs ["scene" "hud" "canvas"])]
    (graph:register-key-loader (activity-surface-key surface-key)
      (make-activity-surface-loader world-manager asset-path-resolver surface-key)))
  (register-activity-scene-category-loaders graph world-manager asset-path-resolver)
  (register-activity-scene-child-loaders graph world-manager)
  (register-activity-terrain-action-loaders graph world-manager))

(fn M.register [graph opts]
  (assert graph "GraphKeyLoaders.register requires graph")
  (assert graph.register-key-loader "GraphKeyLoaders.register requires graph.register-key-loader")
  (local options (or opts {}))

  (local string-store (or options.string-store options.string_store (StringEntityStore.get-default)))
  (local code-store (or options.code-store (and app app.code-store) (CodeEntityStore.get-default)))
  (local list-store (or options.list-store options.list_store (ListEntityStore.get-default)))
  (local link-store (or options.link-store options.link_store (LinkEntityStore.get-default)))
  (local identity-store (or options.identity-store (IdentityStore.get-default)))
  (local notebook-store (or options.notebook-store options.notebook_store (NotebookStore.get-default)))
  (local llm-store (or options.llm-store options.llm_store (LlmStore.get-default)))
  (local kernels (or options.kernels (Kernels.get-default)))
  (local world-manager (or options.world-manager (and app app.world-manager)))
  (local asset-path-resolver options.asset-path-resolver)
  (local hackernews-ensure-client (or options.hackernews-ensure-client options.hackernews_ensure_client))
  (local workflow-store options.workflow-store)
  (local workflow-runner options.workflow-runner)

  (register-string-entity-loader graph {:store string-store})
  (register-code-entity-loader graph {:store code-store})
  (when workflow-store
    (register-workflows-loader graph {:store workflow-store :runner workflow-runner})
    (when workflow-runner
      (register-workflow-definition-loader graph {:store workflow-store :runner workflow-runner})
      (register-workflow-run-loader graph {:store workflow-store :runner workflow-runner}))
    (register-workflow-step-loader graph {:store workflow-store})
    (register-workflow-run-step-loader graph {:store workflow-store})
    (register-workflow-run-event-loader graph {:store workflow-store}))
  (register-list-entity-loader graph {:store list-store
                                      :identity-store identity-store})
  (register-link-entity-loader graph {:store link-store})
  (register-identity-loader graph {:store identity-store})
  (register-notebook-loader graph {:store notebook-store
                                   :identity-store identity-store
                                   :string-store string-store})

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
  (graph:register-key-loader "notebooks"
    (exact-key-loader "notebooks"
      (fn [] (NotebooksNode {:store notebook-store}))))
  (graph:register-key-loader "kernels"
    (exact-key-loader "kernels"
      (fn [] (KernelsNode {:kernels kernels}))))
  (graph:register-key-loader "start"
    (exact-key-loader "start"
      (fn []
          (local node (StartNode))
          (set node.auto-focus? true)
          node)))
  (graph:register-key-loader "quit"
    (exact-key-loader "quit"
      (fn [] (QuitNode {}))))

  (graph:register-key-loader "class"
    (prefix-loader "class:"
      (fn [id _key]
        (ClassNode {:id id :name id}))))

  (graph:register-key-loader "fs"
    (existing-any-path-loader "fs:"
      (fn [path key]
        (FsNode {:path path :key key}))))

  (graph:register-key-loader "code-dir"
    (existing-path-loader "code-dir:" :dir
      (fn [path key]
        (CodeDirNode {:path path :root path :key key}))))

  (graph:register-key-loader "fnl-module"
    (existing-path-loader "fnl-module:" :file
      (fn [path key]
        (when (string.match path "%.fnl$")
          (FnlModuleNode {:path path :key key})))))

  (graph:register-key-loader "cpp-module"
    (existing-path-loader "cpp-module:" :file
      (fn [path key]
        (when (or (string.match path "%.cpp$")
                  (string.match path "%.cc$")
                  (string.match path "%.cxx$")
                  (string.match path "%.h$")
                  (string.match path "%.hpp$")
                  (string.match path "%.hh$"))
          (CppModuleNode {:path path :key key})))))

  (graph:register-key-loader "text-module"
    (existing-path-loader "text-module:" :file
      (fn [path key]
        (TextModuleNode {:path path :key key}))))

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

  (graph:register-key-loader "kernel"
    (prefix-loader "kernel:"
      (fn [id _key]
        (local kernel (kernels:get-kernel id))
        (when kernel
          (KernelNode {:kernel-id kernel.id
                       :kernels kernels})))))

  (graph:register-key-loader "kernel-instance"
    (prefix-loader "kernel-instance:"
      (fn [id _key]
        (local instance (kernels:get-instance id))
        (when instance
          (KernelInstanceNode {:instance-id instance.id
                               :kernels kernels})))))

  (graph:register-key-loader "worlds"
    (exact-key-loader "worlds"
      (fn []
        (when world-manager
          (WorldsNode {:world-manager world-manager
                       :asset-path-resolver asset-path-resolver})))))

  (graph:register-key-loader "world"
    (prefix-loader "world:"
      (fn [world-id key]
        (local world-entry (and world-manager
                               (WorldData.resolve-world-entry world-manager world-id)))
        (when world-entry
          (WorldNode {:world-id world-id
                      :world-manager world-manager
                      :asset-path-resolver asset-path-resolver
                       :world-entry world-entry
                       :key key})))))

  (register-activity-hierarchy-loaders graph world-manager asset-path-resolver)

  (graph:register-key-loader "hud-panels"
    (prefix-loader "hud-panels:"
      (fn [world-id key]
        (when world-manager
          (HudPanelsNode {:world-id world-id
                          :world-manager world-manager
                          :key key})))))

  (graph:register-key-loader "hud-panel"
    (prefix-loader "hud-panel:"
      (fn [rest key]
        (local parts (split-key-parts rest))
        (when (>= (length parts) 3)
          (local world-id (. parts 1))
          (local layer (. parts 2))
          (local panel-index (tonumber (. parts 3)))
          (local panel-entry (and world-manager panel-index
                                  (WorldData.find-hud-panel world-manager world-id layer panel-index)))
          (when panel-entry
            (HudPanelNode {:world-id world-id
                           :world-manager world-manager
                           :layer layer
                           :panel-index panel-index
                           :panel-entry panel-entry
                           :key key}))))))

	  true)

M
