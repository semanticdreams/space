(local FennelEvaluator (require :fennel-evaluator))
(local Outcomes (require :workflows/outcomes))

(fn table? [value]
  (= (type value) "table"))

(fn lower [value]
  (string.lower (tostring (if (= value nil) "" value))))

(fn fennel-language? [language]
  (local normalized (lower language))
  (if (= normalized "fnl")
      true
      (= normalized "fennel")
      true
      false))

(fn step-context [self definition step meta]
  (local options (if (= meta nil) {} meta))
  (Outcomes.make-context {:definition-id (and definition definition.id)
                          :step-id (and step step.id)
                          :app self.app
                          :run-id options.run-id
                          :run options.run
                          :store options.store
                          :runtime options.runtime}))

(fn format-error [value]
  (FennelEvaluator.format-error value))

(fn failed-outcome [message data]
  {:status :failed
   :error {:message (format-error message)
           :data data}})

(fn execution-error [kind message data]
  {:kind kind
   :message message
   :data data})

(fn execution-error-kind [value default-kind]
  (if (and (table? value) value.kind)
      value.kind
      default-kind))

(fn execution-error-message [value]
  (if (and (table? value) (= (type value.message) "string"))
      value.message
      (format-error value)))

(fn execution-error-data [value default-kind]
  (local kind (execution-error-kind value default-kind))
  (local base {:kind kind})
  (when (and (table? value) value.data)
    (set base.details value.data))
  base)

(fn evaluation-error-message [result]
  (.. "workflow code entity evaluation failed: " (FennelEvaluator.format-error result)))

(fn validate-method [step-object method-name step context]
  (local method (. step-object method-name))
  (when (not (= (type method) "function"))
    (error (.. "workflow step " (tostring (and step step.id)) " missing required method :" (tostring method-name))))
  method)

(fn adapt-evaluated-step-object [evaluated config]
  (if (= (type evaluated) "function")
      (evaluated config)
      evaluated))

(fn evaluate-step-object [self _definition step]
  (assert step "evaluate-step-object requires step")
  (assert step.code-entity-id "workflow step requires :code-entity-id")
  (local entity (self.code-store:get-entity step.code-entity-id))
  (when (not entity)
    (error (execution-error :missing-code-entity
                            (.. "missing code entity for workflow step " (tostring step.id) ": " (tostring step.code-entity-id))
                            {:code-entity-id step.code-entity-id})))
  (when (not (fennel-language? entity.language))
    (error (execution-error :unsupported-language
                            (.. "unsupported code entity language for workflow step " (tostring step.id) ": " (tostring entity.language))
                            {:code-entity-id step.code-entity-id
                             :language entity.language})))
  (local source (if (= entity.source nil) "" entity.source))
  (local eval-result (FennelEvaluator.eval-source source))
  (when (not eval-result.ok)
    (error (execution-error :evaluation-failed
                            (evaluation-error-message eval-result.result)
                            {:code-entity-id step.code-entity-id
                             :error eval-result.result})))
  (local config (if (= step.config nil) {} step.config))
  (local (factory-ok adapted-or-err) (pcall adapt-evaluated-step-object eval-result.result config))
  (when (not factory-ok)
    (error (execution-error :factory-error
                            (.. "workflow code entity factory failed: " (format-error adapted-or-err))
                            {:code-entity-id step.code-entity-id
                             :error adapted-or-err})))
  (local adapted adapted-or-err)
  (when (not (table? adapted))
    (error (execution-error :bad-factory-return
                            (.. "workflow code entity factory returned invalid step object for step " (tostring step.id))
                            {:code-entity-id step.code-entity-id
                             :returned-type (type adapted)})))
  adapted)

(fn normalize-returned-outcome [outcome context]
  (local (valid-ok normalized-or-err) (pcall Outcomes.validate-outcome outcome context))
  (if valid-ok
      normalized-or-err
      (Outcomes.validate-outcome
        (failed-outcome (.. "invalid outcome returned by workflow step: " (format-error normalized-or-err))
                        {:kind :invalid-outcome})
        context)))

(fn call-step-method [self definition step method-name input state meta]
  (local context (step-context self definition step meta))
  (local (object-ok object-or-err) (pcall evaluate-step-object self definition step))
  (if (not object-ok)
      (Outcomes.validate-outcome
        (failed-outcome (execution-error-message object-or-err)
                        (execution-error-data object-or-err :step-object))
        context)
      (do
        (local step-object object-or-err)
        (local (method-ok method-or-err) (pcall validate-method step-object method-name step context))
        (if (not method-ok)
            (Outcomes.validate-outcome (failed-outcome method-or-err {:kind :missing-method}) context)
            (do
              (local method method-or-err)
              (local (run-ok outcome-or-err) (pcall method step-object context input state))
              (if run-ok
                  (normalize-returned-outcome outcome-or-err context)
                  (Outcomes.validate-outcome (failed-outcome outcome-or-err {:kind :method-error}) context)))))))

(fn WorkflowCodeExecutor [opts]
  (local options (or opts {}))
  (assert options.code-store "WorkflowCodeExecutor requires :code-store")
  {:code-store options.code-store
   :app options.app
   :evaluate-step-object evaluate-step-object
    :run-step (fn [executor definition step input state meta]
                (call-step-method executor definition step :run input state meta))
    :resume-step (fn [executor definition step wait-result state meta]
                   (call-step-method executor definition step :resume wait-result state meta))
    :cancel-step (fn [executor definition step state meta]
                   (call-step-method executor definition step :cancel state nil meta))})

{:WorkflowCodeExecutor WorkflowCodeExecutor}
