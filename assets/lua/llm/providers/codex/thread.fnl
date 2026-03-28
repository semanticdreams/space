(local json (require :json))
(local process (require :process))
(local callbacks (require :callbacks))
(local Input (require :llm/providers/codex/input))
(local Events (require :llm/providers/codex/events))
(local Exec (require :llm/providers/codex/exec))
(local SchemaFile (require :llm/providers/codex/schema-file))

(fn parse-json-line [line]
  (local (ok parsed-or-error) (pcall json.loads line))
  (if ok
      parsed-or-error
      (error (.. "Failed to parse item: " line))))

(fn emit-callback [callback payload]
  (when callback
    (callback payload)))

(fn consume-event! [thread state event]
  (when (= event.type :thread-started)
    (tset thread :id event.thread-id))
  (when (= event.type :item-completed)
    (table.insert state.items event.item)
    (when (= event.item.type :agent-message)
      (set state.final-response event.item.text)))
  (when (= event.type :turn-completed)
    (set state.usage event.usage))
  (when (= event.type :turn-failed)
    (set state.turn-failure event.error))
  (when (= event.type :error)
    (set state.stream-error {:message event.message})))

(fn parse-complete-lines! [thread handle chunk]
  (set handle.stdout-pending (.. handle.stdout-pending chunk))
  (var newline-index (string.find handle.stdout-pending "\n" 1 true))
  (while newline-index
    (local raw-line (string.sub handle.stdout-pending 1 (- newline-index 1)))
    (set handle.stdout-pending (string.sub handle.stdout-pending (+ newline-index 1)))
    (local line (if (and (> (# raw-line) 0) (= (string.sub raw-line -1) "\r"))
                    (string.sub raw-line 1 -2)
                    raw-line))
    (when (> (# line) 0)
      (local parsed (parse-json-line line))
      (local event (Events.normalize-event parsed))
      (consume-event! thread handle.state event)
      (emit-callback handle.on-event event))
    (set newline-index (string.find handle.stdout-pending "\n" 1 true))))

(fn finalize-handle! [thread handle result]
  (when handle.finished
    (if handle.error
        (error handle.error)
        handle.state.summary))
  (when (> (# handle.stdout-pending) 0)
    (local trailing handle.stdout-pending)
    (set handle.stdout-pending "")
    (local parsed (parse-json-line trailing))
    (local event (Events.normalize-event parsed))
    (consume-event! thread handle.state event)
    (emit-callback handle.on-event event))
  (set handle.finished true)
  (set handle.result result)
  (var process-error nil)
  (local (ok err) (pcall (fn [] (Exec.ensure-process-success! result))))
  (when (not ok)
    (set process-error err))
  (local final-error
    (if handle.state.stream-error
        handle.state.stream-error.message
        handle.state.turn-failure
        handle.state.turn-failure.message
        process-error))
  (if final-error
      (do
        (set handle.error final-error)
        (emit-callback handle.on-error {:message final-error}))
      (do
        (set handle.state.summary {:items handle.state.items
                                   :final-response handle.state.final-response
                                   :usage handle.state.usage})
        (emit-callback handle.on-complete handle.state.summary)))
  (when handle.cleanup
    (handle.cleanup))
  (set thread.active-turn nil)
  (if handle.error
      (error handle.error)
      handle.state.summary))

(fn abort-handle! [thread handle err]
  (when (not handle.finished)
    (local (kill-ok _kill-err) (pcall (fn [] (process.kill handle.process-id))))
    (when kill-ok nil)
    (when handle.cleanup
      (local (_cleanup-ok _cleanup-err) (pcall handle.cleanup))
      (when _cleanup-ok nil))
    (set handle.finished true)
    (set handle.error err)
    (emit-callback handle.on-error {:message err})
    (set thread.active-turn nil))
  (error err))

(fn handle-poll [self]
  (if self.finished
      true
      (do
        (local (ok result-or-error)
          (pcall
            (fn []
              (local read-result (process.read self.process-id))
              (parse-complete-lines! self.thread self read-result.stdout)
              (if read-result.finished
                  (do
                    (local result (process.wait self.process-id))
                    (finalize-handle! self.thread self result))
                  false))))
        (if ok
            result-or-error
            (abort-handle! self.thread self result-or-error)))))

(fn handle-wait [self]
  (when self.finished
    (if self.error
        (error self.error)
        self.state.summary))
  (local (ok err)
    (pcall
      (fn []
        (callbacks.run-loop {:poll-jobs false
                             :poll-http false
                             :poll-process false
                             :sleep-ms 1
                             :timeout-ms (or self.timeout-ms 0)
                             :until (fn []
                                      (local done-or-summary (self:poll))
                                      (not (not done-or-summary)))}))))
  (when (not ok)
    (when (not self.finished)
      (abort-handle! self.thread self err)))
  (if self.error
      (error self.error)
      self.state.summary))

(fn handle-cancel [self]
  (when (not self.finished)
    (process.kill self.process-id))
  true)

(fn handle-running? [self]
  (if self.finished
      false
      (process.running self.process-id)))

(fn spawn-turn-handle [thread input turn-options]
  (when thread.active-turn
    (error "codex-sdk only supports one active turn per thread"))
  (local schema-file (SchemaFile.create-output-schema-file turn-options.output-schema))
  (local normalized (Input.normalize-input input))
  (local process-id
    (thread.exec:spawn {:input normalized.prompt
                        :thread-id thread.id
                        :images normalized.images
                        :model thread.thread-options.model
                        :sandbox-mode thread.thread-options.sandbox-mode
                        :working-directory thread.thread-options.working-directory
                        :additional-directories thread.thread-options.additional-directories
                        :skip-git-repo-check thread.thread-options.skip-git-repo-check
                        :output-schema-file schema-file.schema-path
                        :model-reasoning-effort thread.thread-options.model-reasoning-effort
                        :network-access-enabled thread.thread-options.network-access-enabled
                        :web-search-mode thread.thread-options.web-search-mode
                        :web-search-enabled thread.thread-options.web-search-enabled
                        :approval-policy thread.thread-options.approval-policy}))
  (local handle
    {:thread thread
     :process-id process-id
     :stdout-pending ""
     :finished false
     :error nil
     :result nil
     :timeout-ms turn-options.timeout-ms
     :cleanup schema-file.cleanup
     :on-event turn-options.on-event
     :on-complete turn-options.on-complete
     :on-error turn-options.on-error
     :state {:items []
             :final-response ""
             :usage nil
             :turn-failure nil
             :stream-error nil
             :summary nil}
     :poll handle-poll
     :wait handle-wait
     :cancel handle-cancel
     :running? handle-running?})
  (set thread.active-turn handle)
  handle)

(fn thread-run [self input turn-options]
  (local handle (spawn-turn-handle self input (or turn-options {})))
  (handle:wait))

(fn thread-run-streamed [self input turn-options]
  (spawn-turn-handle self input (or turn-options {})))

(fn Thread [exec options thread-options id]
  {:exec exec
   :options options
   :thread-options (or thread-options {})
   :id id
   :active-turn nil
   :run thread-run
   :run-streamed thread-run-streamed})

{:Thread Thread}
