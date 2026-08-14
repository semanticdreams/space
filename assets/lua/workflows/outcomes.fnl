(local allowed-statuses
  {:succeeded true
   :failed true
   :waiting true
   :retry true
   :cancelled true
   :skipped true})

(fn context-label [context]
  (local ctx (if (= context nil) {} context))
  (local parts [])
  (when ctx.run-id
    (table.insert parts (.. "run " (tostring ctx.run-id))))
  (when ctx.step-id
    (table.insert parts (.. "step " (tostring ctx.step-id))))
  (if (> (length parts) 0)
      (.. " (" (table.concat parts ", ") ")")
      ""))

(fn fail-validation [message context]
  (error (.. message (context-label context))))

(fn table? [value]
  (= (type value) "table"))

(fn validate-next-step-ids [outcome context]
  (when (not (= outcome.next-step-ids nil))
    (when (if (= outcome.status :succeeded)
              false
              (= outcome.status :skipped)
              false
              true)
      (fail-validation "workflow outcome next-step-ids are only allowed for succeeded or skipped statuses" context))
    (when (not (table? outcome.next-step-ids))
      (fail-validation "workflow outcome next-step-ids must be a table of strings" context))
    (each [_ step-id (ipairs outcome.next-step-ids)]
      (when (not (= (type step-id) "string"))
        (fail-validation "workflow outcome next-step-ids must be a table of strings" context)))))

(fn validate-outcome [outcome context]
  (when (not (table? outcome))
    (fail-validation "invalid outcome: expected table" context))
  (when (not (. allowed-statuses outcome.status))
    (fail-validation (.. "invalid outcome status: " (tostring outcome.status)) context))
  (validate-next-step-ids outcome context)
  (when (= outcome.status :failed)
    (when (not (and (table? outcome.error)
                    (= (type outcome.error.message) "string")
                    (> (string.len outcome.error.message) 0)))
      (fail-validation "failed workflow outcome requires error.message" context)))
  (when (= outcome.status :waiting)
    (when (= outcome.wait-kind nil)
      (fail-validation "waiting workflow outcome requires wait-kind" context)))
  (when (= outcome.status :retry)
    (when (not (and (= (type outcome.delay-ms) "number")
                    (>= outcome.delay-ms 0)))
      (fail-validation "retry workflow outcome requires numeric delay-ms >= 0" context)))
  outcome)

(fn make-context [opts]
  (local options (or opts {}))
  {:run-id options.run-id
   :step-id options.step-id
   :definition-id options.definition-id
   :app options.app
   :succeed (fn [_self output helper-opts]
              (local result {:status :succeeded
                             :output output})
              (when (and helper-opts helper-opts.next-step-ids)
                (set result.next-step-ids helper-opts.next-step-ids))
              result)
   :fail (fn [_self message data]
           {:status :failed
            :error {:message (tostring message)
                    :data data}})
   :wait (fn [_self wait-kind request state]
           {:status :waiting
            :wait-kind wait-kind
            :request request
            :state state})
   :retry (fn [_self delay-ms state]
            {:status :retry
             :delay-ms delay-ms
             :state state})
   :cancelled (fn [_self output]
                {:status :cancelled
                 :output output})
   :skip (fn [_self reason]
           {:status :skipped
            :reason reason})})

{:make-context make-context
 :validate-outcome validate-outcome}
