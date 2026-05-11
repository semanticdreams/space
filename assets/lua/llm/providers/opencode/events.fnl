(local json (require :json))
(local Sse (require :llm/providers/opencode/sse))
(local logging (require :logging))

(fn Events [client]
  (assert client "Events requires an opencode client")
  (assert (= (type client.base-url) "function") "client.base-url must be a function")

  (local http-binding (client.http-binding))

  (fn make-sse-callback [on-event]
    (fn [event]
      (when (and event event.data)
        (if (= event.event "error")
            (on-event {:error event.data :_event_type "error"})
            (let [(ok parsed) (pcall json.loads event.data)]
              (if ok
                  (do
                    (tset parsed :_event_type (or event.event "message"))
                    (on-event parsed))
                  (logging.warn "[opencode] failed to parse SSE event data: " event.data)))))))

  (fn build-handle [sse-handle]
    (local handle {})
    (set handle.unsubscribe (fn [] (sse-handle.close)))
    (set handle.closed? (fn [] (sse-handle.done?)))
    handle)

  (fn subscribe [on-event]
    (assert on-event "events.subscribe requires on_event callback")
    (build-handle
      (Sse http-binding
           (.. (client.base-url) "/event")
           {:user-agent "space-opencode/1.0"
            :timeout-ms 0
            :connect-timeout-ms 5000}
           (make-sse-callback on-event))))

  (fn subscribe-global [on-event]
    (assert on-event "events.subscribe-global requires on_event callback")
    (build-handle
      (Sse http-binding
           (.. (client.base-url) "/global/event")
           {:user-agent "space-opencode/1.0"
            :timeout-ms 0
            :connect-timeout-ms 5000}
           (make-sse-callback on-event))))

  {:subscribe subscribe
   :subscribe-global subscribe-global})

Events
