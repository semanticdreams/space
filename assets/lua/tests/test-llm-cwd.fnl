(if (= nil _G.app)
    (global app {:engine {:get-asset-path (fn [p] nil)}})
    (tset _G.app :engine {:get-asset-path (fn [p] nil)}))

(local Store (require :llm/store))
(local LlmRequests (require :llm/requests))
(local LlmConversationNode (require :graph/nodes/llm-conversation))
(local Bash (require :llm/tools/bash))
(local ReadFile (require :llm/tools/read-file))
(local fs (require :fs))
(local shell (require :shell))

(fn test-cwd-persistence []
  (local store (Store.Store {:base-dir "/tmp/test-llm-cwd-store"}))
  (local cwd "/tmp/custom-cwd")
  
  (local conv (store:create-conversation {:name "Test CWD" :cwd cwd}))
  (assert (= conv.cwd cwd) "CWD should be saved in conversation")
  
  (local loaded (store:get-conversation conv.id))
  (assert (= loaded.cwd cwd) "CWD should be loaded from store")
  
  (store:update-conversation conv.id {:cwd "/tmp/updated-cwd"})
  (local updated (store:get-conversation conv.id))
  (assert (= updated.cwd "/tmp/updated-cwd") "CWD should be updatable")
  
  (store:delete-conversation conv.id))

(fn test-default-cwd []
  (local store (Store.Store {:base-dir "/tmp/test-llm-cwd-store-default"}))
  (local conv (store:create-conversation {:name "Default CWD"}))
  (local expected (fs.cwd))
  (assert (= conv.cwd expected) (.. "Default CWD should be process CWD: " expected " vs " (tostring conv.cwd)))
  (store:delete-conversation conv.id))

(fn test-node-sync []
  (local store (Store.Store {:base-dir "/tmp/test-llm-cwd-node"}))
  (local cwd "/tmp/node-cwd")
  (local node (LlmConversationNode {:store store
                                    :name "Node CWD"
                                    :cwd cwd}))
  (assert (= node.cwd cwd) "Node should initialize with CWD")
  
  (node:set-cwd "/tmp/node-updated")
  (assert (= node.cwd "/tmp/node-updated") "Node should update CWD locally")
  
  (local record (store:get-conversation node.llm-id))
  (assert (= record.cwd "/tmp/node-updated") "Node should sync CWD to store")
  
  (node:delete))

(fn test-tool-execution-context []
  (local store (Store.Store {:base-dir "/tmp/test-llm-cwd-exec"}))
  (local cwd "/tmp/exec-cwd")
  (local conv (store:create-conversation {:cwd cwd}))
  
  (var captured-ctx nil)
  (local mock-tool {:name "test_tool"
                    :call (fn [args ctx]
                            (set captured-ctx ctx)
                            "ok")})
  
  (local mock-registry {:call (fn [name args ctx]
                                (mock-tool.call args ctx))})
  
  (local tool-call-output [{:type "function_call"
                            :id "call_1"
                            :name "test_tool"
                            :call_id "call_1"
                            :arguments "{}"}])

  (local mock-openai {:create-response (fn [payload opts]
                                         (opts.callback {:ok true 
                                                         :data {:output tool-call-output}})
                                         "req_id")})

  (LlmRequests.run-request store conv.id 
                           {:tool-registry mock-registry
                            :tools [mock-tool]
                            :input-items (fn [] [])
                            :openai mock-openai})
                                                        
  (assert captured-ctx "Tool should be called")
  (assert (= captured-ctx.cwd cwd) (.. "Tool context should receive CWD: " cwd " vs " (tostring (and captured-ctx captured-ctx.cwd))))
  (store:delete-conversation conv.id))

(fn test-bash-tool []
  (local ctx {:cwd "/tmp/bash-cwd"})
  (local original-bash shell.bash)
  (var captured-opts nil)
  
  (set shell.bash (fn [opts]
                    (set captured-opts opts)
                    {:stdout "" :stderr "" :exit_code 0}))
  
  (Bash.call {:command "pwd" :timeout 1} ctx)
  
  (set shell.bash original-bash)
  
  (assert captured-opts "Bash binding should be called")
  (assert (= captured-opts.cwd "/tmp/bash-cwd") "Bash binding should receive CWD from context"))

(fn test-fs-tools []
  (local ctx {:cwd "/tmp/fs-cwd"})
  
  ; Mock fs
  (local original-read-file fs.read-file)
  (var captured-path nil)
  (set fs.read-file (fn [path]
                      (set captured-path path)
                      "content"))
  
  (ReadFile.call {:path "foo.txt"} ctx)
  
  (set fs.read-file original-read-file)
  
  (assert captured-path "fs.read-file should be called")
  ; Check if it ends with /tmp/fs-cwd/foo.txt
  (assert (string.match captured-path "/tmp/fs%-cwd/foo%.txt$") 
          (.. "Path should be resolved against CWD: " captured-path)))

(fn main []
  (test-cwd-persistence)
  (test-default-cwd)
  (test-node-sync)
  (test-tool-execution-context)
  (test-bash-tool)
  (test-fs-tools)
  (print "All LLM CWD tests passed!"))

{:main main}
