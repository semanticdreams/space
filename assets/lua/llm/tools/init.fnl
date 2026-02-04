(local ListDir (require :llm/tools/list-dir))
(local ReadFile (require :llm/tools/read-file))
(local WriteFile (require :llm/tools/write-file))
(local DeleteFile (require :llm/tools/delete-file))
(local ApplyPatch (require :llm/tools/apply-patch))
(local Bash (require :llm/tools/bash))
(local EditFile (require :llm/tools/edit-file))

(local tool-list [ListDir ReadFile WriteFile DeleteFile ApplyPatch Bash EditFile])

(fn validate-tool [tool]
    (assert tool "llm tool missing table")
    (assert (= (type tool.name) "string") "llm tool missing name")
    (assert (= (type tool.description) "string") (.. "llm tool " tool.name " missing description"))
    (assert (= (type tool.parameters) "table") (.. "llm tool " tool.name " missing parameters"))
    (assert (= (type tool.call) "function") (.. "llm tool " tool.name " missing call"))
    tool)

(fn index-tools [tools]
    (local map {})
    (each [_ tool (ipairs tools)]
        (local validated (validate-tool tool))
        (tset map validated.name validated))
    map)

(local tool-map (index-tools tool-list))

(fn to-openai-definition [tool]
    {:type "function"
     :name tool.name
     :description tool.description
     :parameters tool.parameters
     :strict (if (not (= tool.strict nil)) tool.strict true)})

(fn openai-tools []
    (local result [])
    (each [_ tool (ipairs tool-list)]
        (table.insert result (to-openai-definition tool)))
    result)

(fn get-tool [name]
    (if name
        (. tool-map (tostring name))
        nil))

(fn call [name args ctx]
    (local tool (get-tool name))
    (assert tool (.. "Unknown llm tool: " (tostring name)))
    (tool.call (or args {}) ctx))

{:tools tool-list
 :tool-map tool-map
 :get get-tool
 :call call
 :openai-tools openai-tools
 :to-openai to-openai-definition}
