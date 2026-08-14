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

(fn step-context [self definition step]
  (Outcomes.make-context {:definition-id (and definition definition.id)
                          :step-id (and step step.id)
                          :app self.app}))

(fn failed-outcome [message data]
  {:status :failed
   :error {:message message
           :data data}})

(fn evaluation-error-message [result]
  (.. "workflow code entity evaluation failed: " (FennelEvaluator.format-error result)))

(fn validate-method [step-object method-name step context]
  (local method (. step-object method-name))
  (when (not (= (type method) "function"))
    (error (.. "workflow step " (tostring (and step step.id)) " missing required method :" (tostring method-name))))
  method)

(fn WorkflowCodeExecutor [opts]
  (local options (or opts {}))
  (assert options.code-store "WorkflowCodeExecutor requires :code-store")
  (local self {:code-store options.code-store
               :app options.app})

  (fn evaluate-step-object [_self definition step]
    (assert step "evaluate-step-object requires step")
    (assert step.code-entity-id "workflow step requires :code-entity-id")
    (local entity (self.code-store:get-entity step.code-entity-id))
    (when (not entity)
      (error (.. "missing code entity for workflow step " (tostring step.id) ": " (tostring step.code-entity-id))))
    (when (not (fennel-language? entity.language))
      (error (.. "unsupported code entity language for workflow step " (tostring step.id) ": " (tostring entity.language))))
    (local eval-result (FennelEvaluator.eval-source (or entity.source "")))
    (when (not eval-result.ok)
      (error (evaluation-error-message eval-result.result)))
    (local evaluated eval-result.result)
    (local adapted (if (= (type evaluated) "function")
                       (evaluated (or step.config {}))
                       evaluated))
    (when (not (table? adapted))
      (error (.. "workflow code entity factory returned invalid step object for step " (tostring step.id))))
    adapted)

  (fn call-step-method [definition step method-name input state]
    (local context (step-context self definition step))
    (local (object-ok object-or-err) (pcall evaluate-step-object self definition step))
    (if (not object-ok)
        (Outcomes.validate-outcome (failed-outcome object-or-err {:kind :step-object}) context)
        (do
          (local step-object object-or-err)
          (local (method-ok method-or-err) (pcall validate-method step-object method-name step context))
          (if (not method-ok)
              (Outcomes.validate-outcome (failed-outcome method-or-err {:kind :missing-method}) context)
              (do
                (local method method-or-err)
                (local (run-ok outcome-or-err) (pcall method step-object context input state))
                (if (not run-ok)
                    (Outcomes.validate-outcome (failed-outcome outcome-or-err {:kind :method-error}) context)
                    (do
                      (local (valid-ok normalized-or-err) (pcall Outcomes.validate-outcome outcome-or-err context))
                      (if valid-ok
                          normalized-or-err
                          (Outcomes.validate-outcome
                            (failed-outcome (.. "invalid outcome returned by workflow step: " normalized-or-err)
                                            {:kind :invalid-outcome})
                            context)))))))))

  (set self.evaluate-step-object evaluate-step-object)
  (set self.run-step
       (fn [_self definition step input state]
         (call-step-method definition step :run input state)))
  (set self.resume-step
       (fn [_self definition step wait-result state]
         (call-step-method definition step :resume wait-result state)))
  (set self.cancel-step
       (fn [_self definition step state]
         (call-step-method definition step :cancel state nil)))
  self)

{:WorkflowCodeExecutor WorkflowCodeExecutor}
