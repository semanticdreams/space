(local json (require :json))

(fn value-present? [value]
  (not (= value nil)))

(fn stringify [value]
  (if (= (type value) :table)
      (do
        (local (ok encoded) (pcall json.dumps value))
        (if ok encoded (tostring value)))
      (tostring value)))

(fn append-field [parts label value]
  (when (value-present? value)
    (table.insert parts (.. label ": " (stringify value)))))

(fn run-step-summary [run-step]
  (local step (assert run-step "PreviewSummary.run-step-summary requires run-step"))
  (local parts [])
  (append-field parts "Status" step.status)
  (append-field parts "Attempt" step.attempt)
  (append-field parts "Output" step.output)
  (append-field parts "Wait" step.wait)
  (append-field parts "Error" step.error)
  (table.concat parts " · "))

(local metadata-fields {:id true
                        "id" true
                        :run-id true
                        "run-id" true
                        :created-at true
                        "created-at" true
                        :kind true
                        "kind" true
                        :step-id true
                        "step-id" true})

(fn metadata-field? [key]
  (= (. metadata-fields key) true))

(fn event-payload [event]
  (local payload {})
  (var count 0)
  (each [key value (pairs event)]
    (when (not (metadata-field? key))
      (set count (+ count 1))
      (set (. payload key) value)))
  (when (> count 0)
    payload))

(fn run-event-summary [event]
  (local record (assert event "PreviewSummary.run-event-summary requires event"))
  (local parts [])
  (append-field parts "Kind" record.kind)
  (append-field parts "Step" record.step-id)
  (append-field parts "Payload" (event-payload record))
  (table.concat parts " · "))

{:run-step-summary run-step-summary
 :run-event-summary run-event-summary}
