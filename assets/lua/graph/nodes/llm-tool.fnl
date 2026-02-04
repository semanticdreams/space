(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local LlmTools (require :llm/tools/init))
(local appdirs (require :appdirs))
(local fs (require :fs))
(local JsonUtils (require :json-utils))

(fn ensure-data-dir [root]
    (when (and root fs fs.create-dirs)
        (pcall (fn [] (fs.create-dirs root))))
    root)

(fn safe-filename [key]
    (string.gsub (tostring key) "[^%w%._-]" "_"))

(fn path-basename [path]
    (if path
        (or (string.match path "([^/]+)$") path)
        path))

(fn normalize-base-dir [dir]
    (if (and dir fs fs.parent)
        (let [name (path-basename dir)
              parent (fs.parent dir)
              parent-name (path-basename parent)
              type-dirs {"llm-message" true "llm-conversation" true "llm-tool" true "llm-tool-call" true "llm-tool-result" true}]
            (if (= name "node-data")
                (fs.parent (fs.parent dir))
                (if (= name "graph")
                    (fs.parent dir)
                    (if (and (. type-dirs name) (= parent-name "node-data"))
                        (fs.parent (fs.parent parent))
                        (if (= name "llm")
                            (fs.parent dir)
                            (if (and (= name "tools") (= parent-name "llm"))
                                (fs.parent (fs.parent dir))
                                dir))))))
        dir))

(fn LlmToolNode [opts]
    (local options (or opts {}))
    (local tool (or options.tool
                    (and options.name (LlmTools.get options.name))
                    (and (. options "tool-name") (LlmTools.get (. options "tool-name")))
                    nil))
    (local tool-name (or (and tool tool.name)
                         options.name
                         (. options "tool-name")
                         "llm-tool"))
    (local key (or options.key (.. "llm-tool:" tool-name)))
    (local label (or options.label tool-name))
    (local base-dir (normalize-base-dir (or options.base-dir (and appdirs (appdirs.user-data-dir "space")))))
    (local root (and base-dir fs (fs.join-path base-dir "llm" "tools")))
    (local data-path (and root (fs.join-path root (.. (safe-filename key) ".json"))))
    (local node (GraphNode {:key key
                                :label label
                                :color (glm.vec4 0.2 0.7 0.6 1)
                                :sub-color (glm.vec4 0.1 0.6 0.5 1)}))
    (set node.kind "llm-tool")
    (set node.name tool-name)
    (set node.description (or (and tool tool.description) options.description))
    (set node.parameters (or (and tool tool.parameters) options.parameters))
    (set node.created-at (or options.created-at (os.time)))
    (set node.updated-at (or options.updated-at node.created-at))
    (set node.data-root root)
    (set node.data-path (or options.data-path data-path))
    (set node.persist
         (fn [self]
             (assert (and self.data-path JsonUtils) "LlmToolNode missing persistence path")
             (local root (or self.data-root (and self.data-path (fs.parent self.data-path))))
             (when root
                 (ensure-data-dir root))
             (local expected (and root (fs.join-path root (.. (safe-filename self.key) ".json"))))
             (when (and expected (not (= self.data-path expected)))
                 (set self.data-path expected))
             (ensure-data-dir (fs.parent self.data-path))
             (local payload {:type "llm-tool"
                             :key self.key
                             :name self.name
                             :description self.description
                             :parameters self.parameters
                             :created_at self.created-at
                             :updated_at self.updated-at})
             (JsonUtils.write-json! self.data-path payload)
             payload))
    node)

LlmToolNode
