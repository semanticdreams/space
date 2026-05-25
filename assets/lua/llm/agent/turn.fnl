;; TurnHandle and TurnController — lifecycle for a single agent turn.
;; TurnHandle is the public handle returned to callers.
;; TurnController is passed to agents as ctx.turn.

(local Uuid (require :uuid))
(local callbacks-binding (require :callbacks))

(fn new-id []
  (.. "turn-" (Uuid.v4)))

(fn TurnPair [session-id callbacks]
  "Create a paired TurnHandle and TurnController.
  callbacks: {:on-complete :on-error :on-item :on-update :on-upsert :on-status :persist}"
  (var status :created)
  (var result nil)
  (var error-msg nil)
  (var cancel-fn nil)
  (var cancelled false)
  (local handle-id (new-id))

  (fn fire-callback [name ...]
    (local cb (and callbacks (. callbacks name)))
    (when cb
      (cb ...)))

  ;; ── TurnController methods ──
  ;; Each accepts self as first param for :method syntax

  (fn controller-append-item [self item]
    (when callbacks.on-item
      (callbacks.on-item item)))

  (fn controller-update-item [self item-id updates]
    (when callbacks.on-update
      (callbacks.on-update item-id updates)))

  (fn controller-upsert-item [self item]
    (when callbacks.on-upsert
      (callbacks.on-upsert item)))

  (fn controller-set-cancel [self fn-to-cancel]
    (when (= (type fn-to-cancel) "function")
      (set cancel-fn fn-to-cancel)))

  (fn controller-finish [self turn-result]
    (when (= status :running)
      (set status :completed)
      (set result turn-result)
      (when callbacks.persist
        (callbacks.persist))
      (fire-callback :on-complete {:id handle-id
                                    :session-id session-id
                                    :status :completed
                                    :result turn-result})))

  (fn controller-fail [self err]
    (when (= status :running)
      (set status :failed)
      (set error-msg err)
      (when callbacks.persist
        (callbacks.persist))
      (fire-callback :on-error {:id handle-id
                                 :session-id session-id
                                 :status :failed
                                 :error err})))

  (fn controller-cancelled? [self]
    cancelled)

  ;; ── TurnHandle methods ──
  ;; Each accepts self as first param for :method syntax

  (fn handle-status [self]
    status)

  (fn handle-result [self]
    result)

  (fn handle-error [self]
    error-msg)

  (fn handle-cancel [self]
    (when (= status :running)
      (set cancelled true)
      (var cancel-error nil)
      (when cancel-fn
        (local (ok err) (pcall cancel-fn))
        (when (not ok)
          (set cancel-error (tostring err))))
      (set status :cancelled)
      (set error-msg
           (if cancel-error
               (.. "turn cancelled; cancel hook failed: " cancel-error)
               "turn cancelled"))
      (when callbacks.persist
        (callbacks.persist))
      (fire-callback :on-error {:id handle-id
                                 :session-id session-id
                                 :status :cancelled
                                 :error error-msg}))
    true)

  (fn handle-running? [self]
    (= status :running))

  (fn handle-wait [self timeout-ms]
    (local poll-ms (or timeout-ms 30000))
    (local deadline (+ (os.time) (/ poll-ms 1000)))
    (while (and (= status :running) (< (os.time) deadline))
      (callbacks-binding.run-loop {:poll-jobs true
                                   :poll-http true
                                   :poll-process true
                                   :sleep-ms 10
                                   :timeout-ms 10}))
    status)

  (fn handle-start [self]
    (when (= status :created)
      (set status :running)
      (fire-callback :on-status {:id handle-id
                                  :session-id session-id
                                  :status :running})))

  ;; Assemble tables
  (local controller
    {:id handle-id
     :session-id session-id
     :append-item controller-append-item
     :update-item controller-update-item
     :upsert-item controller-upsert-item
     :set-cancel controller-set-cancel
     :finish controller-finish
     :fail controller-fail
     :cancelled? controller-cancelled?})

  (local handle
    {:id handle-id
     :session-id session-id
     :status handle-status
     :result handle-result
     :error handle-error
     :cancel handle-cancel
     :running? handle-running?
     :wait handle-wait
     :start handle-start})

  (values handle controller))

{:TurnPair TurnPair}
