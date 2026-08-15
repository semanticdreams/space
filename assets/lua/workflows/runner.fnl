(fn table-or-empty [value]
  (if (= value nil) {} value))

(fn array-or-empty [value]
  (if (= value nil) [] value))

(fn now []
  (os.time))

(fn contains? [items value]
  (var found false)
  (each [_ item (ipairs (array-or-empty items))]
    (when (= item value)
      (set found true)))
  found)

(fn find-step [definition step-id]
  (var found nil)
  (each [_ step (ipairs (array-or-empty definition.steps))]
    (when (= step.id step-id)
      (set found step)))
  found)

(fn control-edge? [edge]
  (if (= edge.kind nil)
      true
      (= edge.kind :control)
      true
      false))

(fn data-edge? [edge]
  (= edge.kind :data))

(fn inbound-control-edges [definition step-id]
  (local edges [])
  (each [_ edge (ipairs (array-or-empty definition.edges))]
    (when (and (control-edge? edge) (= edge.target-step-id step-id))
      (table.insert edges edge)))
  edges)

(fn outgoing-control-edges [definition step-id]
  (local edges [])
  (each [_ edge (ipairs (array-or-empty definition.edges))]
    (when (and (control-edge? edge) (= edge.source-step-id step-id))
      (table.insert edges edge)))
  edges)

(fn terminal-success? [run-step]
  (if (= run-step.status :succeeded)
      true
      (= run-step.status :skipped)
      true
      false))

(fn terminal? [run-step]
  (if (= run-step.status :succeeded)
      true
      (= run-step.status :failed)
      true
      (= run-step.status :skipped)
      true
      (= run-step.status :cancelled)
      true
      false))

(fn nonterminal? [run-step]
  (not (terminal? run-step)))

(fn cancellable-run-status? [status]
  (if (= status :queued)
      true
      (= status :running)
      true
      (= status :waiting)
      true
      false))

(fn unselected-skip? [run-step]
  (and run-step (= run-step.status :skipped) (= run-step.skip-reason :unselected)))

(fn selected-target? [source-run-step target-step-id source-step-id]
  (if (unselected-skip? source-run-step)
      false
      (= source-run-step.next-step-ids nil)
      (not (= source-step-id target-step-id))
      (= source-run-step.next-step-ids :all)
      (not (= source-step-id target-step-id))
      (contains? source-run-step.next-step-ids target-step-id)))

(fn append-event [self run-id kind data]
  (local event (table-or-empty data))
  (set event.kind kind)
  (self.store:append-event run-id event))

(fn update-run-status [self run status extra]
  (local updates (table-or-empty extra))
  (set updates.status status)
  (self.store:update-run run.id updates))

(fn step-update [self run step-id updates]
  (self.store:upsert-run-step run.id step-id updates))

(fn create-run-steps [self definition run]
  (each [_ step (ipairs (array-or-empty definition.steps))]
    (step-update self run step.id {:status :pending})))

(fn source-output-value [source-step source-port]
  (if (= source-port nil)
      source-step.output
      (. (table-or-empty source-step.output) source-port)))

(fn apply-data-edge! [input edge source-step]
  (local value (source-output-value source-step edge.source-port))
  (local target-port edge.target-port)
  (local source-port edge.source-port)
  (if edge.target-port
      (set (. input target-port) value)
      (= source-port nil)
      (when (= (type value) "table")
        (each [k v (pairs value)]
          (set (. input k) v)))
      (set (. input source-port) value))
  input)

(fn build-step-input [definition run step-id]
  (local input {})
  (each [k v (pairs (table-or-empty run.input))]
    (set (. input k) v))
  (each [_ edge (ipairs (array-or-empty definition.edges))]
    (when (and (data-edge? edge) (= edge.target-step-id step-id))
      (local source-step-id edge.source-step-id)
      (local source-step (. run.steps source-step-id))
      (when (and source-step (= source-step.status :succeeded))
        (apply-data-edge! input edge source-step))))
  input)

(fn step-ready? [definition run step-id]
  (local inbound (inbound-control-edges definition step-id))
  (if (= (length inbound) 0)
      true
      (and (= (length inbound) 1) (= (. inbound 1 :source-step-id) step-id) (= (. run.steps step-id :status) :pending))
      true
      (do
        (var selected-count 0)
        (var pending-selected false)
        (var failed-source false)
        (each [_ edge (ipairs inbound)]
          (local source-step-id edge.source-step-id)
          (local source-step (. run.steps source-step-id))
          (when source-step
            (if (terminal-success? source-step)
                (when (selected-target? source-step step-id source-step-id)
                  (set selected-count (+ selected-count 1)))
                (nonterminal? source-step)
                (set pending-selected true)
                (= source-step.status :failed)
                (set failed-source true))))
        (and (> selected-count 0)
             (not pending-selected)
             (not failed-source)))))

(fn mark-ready-steps [self definition run]
  (local ready [])
  (each [_ step (ipairs (array-or-empty definition.steps))]
    (local step-id step.id)
    (local run-step (. run.steps step-id))
    (when (and run-step (= run-step.status :pending) (step-ready? definition run step.id))
      (step-update self run step.id {:status :ready})
      (append-event self run.id :step-ready {:step-id step.id})
      (table.insert ready step.id)))
  ready)

(fn unselected-reachable? [run edge]
  (local source-step (. run.steps edge.source-step-id))
  (if (unselected-skip? source-step)
      true
      (terminal-success? source-step)
      (not (selected-target? source-step edge.target-step-id edge.source-step-id))
      false))

(fn can-skip-as-unselected? [definition run step-id]
  (local inbound (inbound-control-edges definition step-id))
  (if (= (length inbound) 0)
      false
      (do
        (var skippable true)
        (each [_ edge (ipairs inbound)]
          (when (not (unselected-reachable? run edge))
            (set skippable false)))
        skippable)))

(fn skip-unselected-subgraph [self definition run step-id source-step-id]
  (local target (. run.steps step-id))
  (when (and target (= target.status :pending) (can-skip-as-unselected? definition run step-id))
    (step-update self run step-id {:status :skipped :finished-at (now) :skip-reason :unselected})
    (append-event self run.id :step-skipped {:step-id step-id :source-step-id source-step-id})
    (local fresh (self.store:get-run run.id))
    (each [_ edge (ipairs (outgoing-control-edges definition step-id))]
      (skip-unselected-subgraph self definition fresh edge.target-step-id step-id))))

(fn explicit-selection? [selected]
  (and selected (not (= selected :all))))

(fn target-selected? [selected target-step-id source-step-id]
  (if (= selected :all)
      (not (= source-step-id target-step-id))
      (contains? selected target-step-id)))

(fn skip-unselected-targets [self definition run source-step-id selected]
  (when (explicit-selection? selected)
    (each [_ edge (ipairs (outgoing-control-edges definition source-step-id))]
      (when (not (contains? selected edge.target-step-id))
        (skip-unselected-subgraph self definition run edge.target-step-id source-step-id)))))

(fn reset-selected-terminal-targets [self definition run source-step-id selected]
  (when selected
    (each [_ edge (ipairs (outgoing-control-edges definition source-step-id))]
      (when (target-selected? selected edge.target-step-id source-step-id)
        (local target-step-id edge.target-step-id)
        (local target (. run.steps target-step-id))
        (when (and target (terminal-success? target))
          (step-update self run edge.target-step-id {:status :ready :finished-at nil}))))))

(fn run-output-from-steps [run]
  (local output {})
  (each [step-id run-step (pairs (table-or-empty run.steps))]
    (when (= run-step.status :succeeded)
      (set (. output step-id) run-step.output)))
  output)

(fn any-status? [run status]
  (var found false)
  (each [_ run-step (pairs (table-or-empty run.steps))]
    (when (= run-step.status status)
      (set found true)))
  found)

(fn unresolved-pending? [run]
  (if (any-status? run :pending)
      true
      (any-status? run :ready)
      true
      (any-status? run :running)
      true
      false))

(fn all-terminal-success? [run]
  (var all true)
  (each [_ run-step (pairs (table-or-empty run.steps))]
    (when (not (terminal-success? run-step))
      (set all false)))
  all)

(fn refresh-run [self run-id]
  (self.store:get-run run-id))

(fn execution-metadata [self run opts]
  (local options (table-or-empty opts))
  {:run-id run.id
   :run run
   :store self.store
   :runtime options.runtime})

(fn finish-run-if-complete [self run]
  (local fresh (refresh-run self run.id))
  (if (any-status? fresh :failed)
      (do
        (append-event self fresh.id :run-failed {})
        (update-run-status self fresh :failed {:finished-at (now)}))
      (any-status? fresh :cancelled)
      (do
        (append-event self fresh.id :run-cancelled {})
        (update-run-status self fresh :cancelled {:finished-at (now)}))
      (any-status? fresh :waiting)
      (do
        (append-event self fresh.id :run-waiting {})
        (update-run-status self fresh :waiting {}))
      (all-terminal-success? fresh)
      (do
        (append-event self fresh.id :run-succeeded {})
        (update-run-status self fresh :succeeded {:finished-at (now) :output (run-output-from-steps fresh)}))
      fresh))

(fn outcome-error [outcome]
  (if outcome.error
      outcome.error
      {:message "workflow step failed"}))

(fn valid-outcome-status? [status]
  (if (= status :succeeded)
      true
      (= status :skipped)
      true
      (= status :waiting)
      true
      (= status :retry)
      true
      (= status :cancelled)
      true
      (= status :failed)
      true
      false))

(fn invalid-outcome [outcome]
  {:status :failed
   :error {:message "invalid outcome returned by workflow step"
           :data {:kind :invalid-outcome
                  :returned-type (type outcome)
                  :returned-status (if (= (type outcome) "table") outcome.status nil)}}})

(fn normalize-outcome [outcome]
  (if (not (= (type outcome) "table"))
      (invalid-outcome outcome)
      (not (valid-outcome-status? outcome.status))
      (invalid-outcome outcome)
      outcome))

(fn routing-selection [outcome]
  (if (= outcome.next-step-ids nil)
      :all
      outcome.next-step-ids))

(fn fail-step [self run step-id outcome]
  (step-update self run step-id {:status :failed :error (outcome-error outcome) :finished-at (now)})
  (append-event self run.id :step-failed {:step-id step-id :error (outcome-error outcome)}))

(fn apply-outcome [self definition run step outcome]
  (local normalized (normalize-outcome outcome))
  (local status normalized.status)
  (local step-id step.id)
  (if (= status :succeeded)
      (do
        (local selection (routing-selection normalized))
        (step-update self run step-id {:status :succeeded :output (table-or-empty normalized.output) :state (table-or-empty normalized.state) :next-step-ids selection :finished-at (now)})
        (append-event self run.id :step-succeeded {:step-id step-id})
        (skip-unselected-targets self definition (self.store:get-run run.id) step-id selection)
        (reset-selected-terminal-targets self definition (self.store:get-run run.id) step-id selection))
      (= status :skipped)
      (do
        (local selection (routing-selection normalized))
        (step-update self run step-id {:status :skipped :reason normalized.reason :next-step-ids selection :finished-at (now)})
        (append-event self run.id :step-skipped {:step-id step-id :reason normalized.reason})
        (skip-unselected-targets self definition (self.store:get-run run.id) step-id selection))
      (= status :waiting)
      (do
        (step-update self run step-id {:status :waiting
                                       :wait {:kind normalized.wait-kind :request normalized.request}
                                       :state (table-or-empty normalized.state)})
        (append-event self run.id :step-waiting {:step-id step-id :wait-kind normalized.wait-kind}))
      (= status :retry)
      (do
        (local current (. run.steps step-id))
        (local attempt (if (= current.attempt nil) 0 current.attempt))
        (local next-attempt (+ attempt 1))
        (local max-attempts (if (and step.retry step.retry.max-attempts) step.retry.max-attempts 0))
        (if (<= next-attempt max-attempts)
            (do
              (step-update self run step-id {:status :ready :attempt next-attempt :state (table-or-empty normalized.state) :retry-after-ms normalized.delay-ms})
              (append-event self run.id :step-retried {:step-id step-id :attempt next-attempt :delay-ms normalized.delay-ms}))
            (fail-step self run step-id {:error {:message "workflow step retry attempts exhausted" :data {:attempt next-attempt :max-attempts max-attempts}}})))
      (= status :cancelled)
      (do
        (step-update self run step-id {:status :cancelled :output (table-or-empty normalized.output) :finished-at (now)})
        (append-event self run.id :step-cancelled {:step-id step-id}))
      (= status :failed)
      (fail-step self run step-id normalized)))

(fn execute-ready-step [self definition run step-id]
  (local step (assert (find-step definition step-id) (.. "missing workflow step: " step-id)))
  (local current (. run.steps step-id))
  (local input (build-step-input definition run step-id))
  (step-update self run step-id {:status :running :input input :started-at (now)})
  (append-event self run.id :step-started {:step-id step-id})
  (local outcome (self.executor:run-step definition step input (table-or-empty current.state) (execution-metadata self run nil)))
  (local fresh (refresh-run self run.id))
  (apply-outcome self definition fresh step outcome))

(fn no-ready-failure? [run ready-count]
  (and (= ready-count 0)
       (unresolved-pending? run)
       (not (any-status? run :cancelled))
       (not (any-status? run :waiting))))

(fn fail-stalled-run [self run]
  (append-event self run.id :run-failed {:error {:message "workflow run stalled with unresolved pending steps"}})
  (update-run-status self run :failed {:finished-at (now)
                                       :error {:message "workflow run stalled with unresolved pending steps"}}))

(fn start-run [self definition-id input context]
  (local definition (assert (self.store:get-definition definition-id) (.. "missing workflow definition: " (tostring definition-id))))
  (local run (self.store:create-run definition.id input context))
  (create-run-steps self definition run)
  (append-event self run.id :run-created {:definition-id definition.id})
  (refresh-run self run.id))

(fn tick-run [self run-id opts]
  (local options (table-or-empty opts))
  (local max-steps (if (= options.max-steps nil) 1 options.max-steps))
  (var run (refresh-run self run-id))
  (when (= run.status :queued)
    (append-event self run.id :run-started {})
    (set run (update-run-status self run :running {:started-at (now)})))
  (when (if (= run.status :running) true (= run.status :queued) true false)
    (local definition (assert (self.store:get-definition run.definition-id) (.. "missing workflow definition: " (tostring run.definition-id))))
    (var executed 0)
    (while (< executed max-steps)
      (set run (refresh-run self run.id))
      (mark-ready-steps self definition run)
      (set run (refresh-run self run.id))
      (var next-step-id nil)
      (each [_ step (ipairs (array-or-empty definition.steps))]
        (local step-id step.id)
        (local run-step (. run.steps step-id))
        (when (and (not next-step-id) run-step (= run-step.status :ready))
          (set next-step-id step.id)))
      (if next-step-id
          (do
            (execute-ready-step self definition run next-step-id)
            (set executed (+ executed 1)))
          (do
            (set executed max-steps))))
    (set run (refresh-run self run.id))
    (mark-ready-steps self definition run)
    (set run (refresh-run self run.id))
    (if (no-ready-failure? run (if (any-status? run :ready) 1 0))
        (fail-stalled-run self run)
        (finish-run-if-complete self run)))
  (refresh-run self run-id))

(fn tick [self opts]
  (local runs [])
  (local active-runs (if self.store.list-active-runs
                         (self.store:list-active-runs {})
                         (self.store:list-runs {})))
  (each [_ run (ipairs active-runs)]
    (when (if (= run.status :queued) true (= run.status :running) true false)
      (table.insert runs (self:tick-run run.id opts))))
  runs)

(fn resume-step [self run-id step-id wait-result opts]
  (var run (refresh-run self run-id))
  (local definition (assert (self.store:get-definition run.definition-id) (.. "missing workflow definition: " run.definition-id)))
  (local step (assert (find-step definition step-id) (.. "missing workflow step: " step-id)))
  (local run-step (assert (. run.steps step-id) (.. "missing workflow run step: " step-id)))
  (assert (= run-step.status :waiting) (.. "workflow run step is not waiting: " step-id))
  (set run (update-run-status self run :running {}))
  (step-update self run step-id {:status :running})
  (append-event self run.id :step-started {:step-id step-id :resume true})
  (local outcome (self.executor:resume-step definition step wait-result (table-or-empty run-step.state) (execution-metadata self run opts)))
  (apply-outcome self definition (refresh-run self run.id) step outcome)
  (finish-run-if-complete self (refresh-run self run.id))
  (self.store:get-run-step run.id step-id))

(fn cancel-run [self run-id reason]
  (local run (refresh-run self run-id))
  (assert (cancellable-run-status? run.status)
          (.. "workflow run is not cancellable: " run-id " status=" (tostring run.status)))
  (local definition (assert (self.store:get-definition run.definition-id) (.. "missing workflow definition: " run.definition-id)))
  (each [_ step (ipairs (array-or-empty definition.steps))]
    (local step-id step.id)
    (local run-step (. run.steps step-id))
    (when (and run-step (nonterminal? run-step))
      (when (and (= run-step.status :waiting) self.executor.cancel-step)
        (self.executor:cancel-step definition step (table-or-empty run-step.state)))
      (step-update self run step.id {:status :cancelled :finished-at (now)})
      (append-event self run.id :step-cancelled {:step-id step.id :reason reason})))
  (append-event self run.id :run-cancelled {:reason reason})
  (update-run-status self run :cancelled {:finished-at (now) :error {:message (tostring reason)}}))

(fn WorkflowRunner [opts]
  (local options (table-or-empty opts))
  (assert options.store "WorkflowRunner requires :store")
  (assert options.executor "WorkflowRunner requires :executor")
  {:store options.store
   :executor options.executor
   :app options.app
   :start-run start-run
   :tick-run tick-run
   :tick tick
   :resume-step resume-step
   :cancel-run cancel-run})

{:WorkflowRunner WorkflowRunner}
