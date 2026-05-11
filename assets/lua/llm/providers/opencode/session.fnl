(local assert-module (require :llm/providers/opencode/assert))
(local assert-callback assert-module.assert-callback)

(fn Session [client]
  (assert client "Session requires an opencode client")

  (fn list [on-response]
    (assert-callback on-response "session.list")
    (client.submit "GET" "/session" {:on_response on-response}))

  (fn create [body on-response]
    (assert-callback on-response "session.create")
    (client.submit "POST" "/session"
                   {:body (or body {})
                    :on_response on-response}))

  (fn get [id on-response]
    (assert id "session.get requires an id")
    (assert-callback on-response "session.get")
    (client.submit "GET" (.. "/session/" id) {:on_response on-response}))

  (fn delete [id on-response]
    (assert id "session.delete requires an id")
    (assert-callback on-response "session.delete")
    (client.submit "DELETE" (.. "/session/" id) {:on_response on-response}))

  (fn update [id body on-response]
    (assert id "session.update requires an id")
    (assert-callback on-response "session.update")
    (client.submit "PATCH" (.. "/session/" id)
                   {:body (or body {})
                    :on_response on-response}))

  (fn prompt [id body on-response]
    (assert id "session.prompt requires an id")
    (assert-callback on-response "session.prompt")
    (client.submit "POST" (.. "/session/" id "/message")
                   {:body (or body {})
                    :on_response on-response}))

  (fn abort [id on-response]
    (assert id "session.abort requires an id")
    (assert-callback on-response "session.abort")
    (client.submit "POST" (.. "/session/" id "/abort") {:on_response on-response}))

  (fn command [id body on-response]
    (assert id "session.command requires an id")
    (assert-callback on-response "session.command")
    (client.submit "POST" (.. "/session/" id "/command")
                   {:body (or body {})
                    :on_response on-response}))

  (fn shell [id body on-response]
    (assert id "session.shell requires an id")
    (assert-callback on-response "session.shell")
    (client.submit "POST" (.. "/session/" id "/shell")
                   {:body (or body {})
                    :on_response on-response}))

  (fn messages [id on-response]
    (assert id "session.messages requires an id")
    (assert-callback on-response "session.messages")
    (client.submit "GET" (.. "/session/" id "/message") {:on_response on-response}))

  (fn children [id on-response]
    (assert id "session.children requires an id")
    (assert-callback on-response "session.children")
    (client.submit "GET" (.. "/session/" id "/children") {:on_response on-response}))

  (fn summarize [id body on-response]
    (assert id "session.summarize requires an id")
    (assert-callback on-response "session.summarize")
    (client.submit "POST" (.. "/session/" id "/summarize")
                   {:body (or body {})
                    :on_response on-response}))

  (fn init [id body on-response]
    (assert id "session.init requires an id")
    (assert-callback on-response "session.init")
    (client.submit "POST" (.. "/session/" id "/init")
                   {:body (or body {})
                    :on_response on-response}))

  (fn share [id on-response]
    (assert id "session.share requires an id")
    (assert-callback on-response "session.share")
    (client.submit "POST" (.. "/session/" id "/share") {:on_response on-response}))

  (fn unshare [id on-response]
    (assert id "session.unshare requires an id")
    (assert-callback on-response "session.unshare")
    (client.submit "DELETE" (.. "/session/" id "/share") {:on_response on-response}))

  (fn revert [id body on-response]
    (assert id "session.revert requires an id")
    (assert-callback on-response "session.revert")
    (client.submit "POST" (.. "/session/" id "/revert")
                   {:body (or body {})
                    :on_response on-response}))

  (fn unrevert [id on-response]
    (assert id "session.unrevert requires an id")
    (assert-callback on-response "session.unrevert")
    (client.submit "POST" (.. "/session/" id "/unrevert") {:on_response on-response}))

  (fn permissions [id permission-id body on-response]
    (assert id "session.permissions requires a session id")
    (assert permission-id "session.permissions requires a permission id")
    (assert-callback on-response "session.permissions")
    (client.submit "POST"
                   (.. "/session/" id "/permissions/" permission-id)
                   {:body (or body {})
                    :on_response on-response}))

  {:list list
   :create create
   :get get
   :delete delete
   :update update
   :prompt prompt
   :abort abort
   :command command
   :shell shell
   :messages messages
   :children children
   :summarize summarize
   :init init
   :share share
   :unshare unshare
   :revert revert
   :unrevert unrevert
   :permissions permissions})

Session
