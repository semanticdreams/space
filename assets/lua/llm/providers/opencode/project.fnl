(local assert-module (require :llm/providers/opencode/assert))
(local assert-callback assert-module.assert-callback)

(fn Project [client]
  (assert client "Project requires an opencode client")

  (fn list [on-response]
    (assert-callback on-response "project.list")
    (client.submit "GET" "/project" {:on_response on-response}))

  (fn current [on-response]
    (assert-callback on-response "project.current")
    (client.submit "GET" "/project/current" {:on_response on-response}))

  {:list list
   :current current})

Project
