;; Runner module for experimental Fennel constraints.
;; Aggregates rule execution, status precedence, and JSON output.

(local Diagnostics (require :constraints.diagnostics))
(local json (require :json))

(local M {})

;; Status precedence: :interrupted > :fail > :violations > :pass
(local status-precedence {:interrupted 4
                          :fail 3
                          :violations 2
                          :pass 1})

(fn worse-status [a b]
  "Return the worse (higher precedence) of two statuses."
  (let [pa (or (. status-precedence a) 0)
        pb (or (. status-precedence b) 0)]
    (if (>= pa pb) a b)))

(fn make-error-handler [diagnostics rule-id target timed-out]
  "Build an xpcall error handler that differentiates crash vs interrupt."
  (fn [err-obj]
    (if (. timed-out :flag)
        (let [d (Diagnostics.framework-failure
                  {:constraint-id rule-id
                   :family :framework
                   :message (.. "rule interrupted: " (tostring err-obj))
                   :evidence {}
                   :target target
                   :hint "check the rule for hangs or infinite loops"})]
          (tset d :interrupted true)
          (table.insert diagnostics d))
        (let [tb (if _G.debug
                     (_G.debug.traceback err-obj 3)
                     (tostring err-obj))]
          (table.insert diagnostics
            (Diagnostics.framework-failure
              {:constraint-id rule-id
               :family :framework
               :message (.. "rule crashed: " (tostring err-obj))
               :evidence {:traceback tb}
               :target target
                :hint "check the rule implementation for errors"}))))))

(fn execute-guarded [diagnostics rule target on-error]
  "Execute rule within xpcall and collect diagnostics."
  (let [(ok result) (xpcall (fn [] (rule target)) on-error)]
    (when (and ok result (= (type result) :table))
      (if (. result :constraint-id)
          (table.insert diagnostics result)
          (each [_ d (ipairs result)]
            (table.insert diagnostics d))))))

(fn make-timeout-hook [started-at timeout-seconds timed-out]
  "Build a debug.sethook callback that errors on timeout."
  (fn []
    (when (>= (- (os.clock) started-at) timeout-seconds)
      (tset timed-out :flag true)
      (error (.. "rule timed out after " timeout-seconds "s") 2))))

(fn M.run-rule [rule target timeout-seconds]
  "Run a single rule function against a target using xpcall.
  Returns nil on pass, or a list of diagnostics on failure/crash/interrupt.
  Uses debug.traceback for crash diagnostics, debug.sethook for timeouts."
  (let [diagnostics []
        rule-id (or (and (= (type rule) :table) (. rule :constraint-id)) :unknown-rule)
        timed-out {:flag false}
        on-error (make-error-handler diagnostics rule-id target timed-out)]
    (if (and timeout-seconds (> timeout-seconds 0)
             _G.debug _G.debug.sethook _G.debug.gethook)
        ;; Timeout-enabled execution
        (let [debug-lib _G.debug
              started-at (os.clock)
              (old-hook old-mask old-count) (debug-lib.gethook)
              hook (make-timeout-hook started-at timeout-seconds timed-out)]
          (debug-lib.sethook hook "" 10000)
          (execute-guarded diagnostics rule target on-error)
          ;; Restore original hook immediately after rule completes
          (debug-lib.sethook old-hook old-mask old-count))
        ;; No timeout — simple execution
        (execute-guarded diagnostics rule target on-error))
    (if (= (# diagnostics) 0) nil diagnostics)))

(fn M.run [opts]
  "Run a set of rules against a target.
  opts: {:rules [] :target <target> :timeout-seconds <int|nil>}
  Returns {:status :pass|:violations|:fail|:interrupted
           :counts {:total <int> :by-family <table> :by-severity <table>}
           :diagnostics []}"
  (var status :pass)
  (let [rules (or opts.rules [])
        target (or opts.target {:kind :repo :name "default"})
        all-diagnostics []]
    (each [_ rule (ipairs rules)]
      (let [result (M.run-rule rule target opts.timeout-seconds)]
        (when result
          ;; result is a list of diagnostics
          (each [_ d (ipairs result)]
            ;; Ensure every diagnostic identifies the target
            (when (not (. d :target))
              (tset d :target target))
            (table.insert all-diagnostics d))
          ;; Determine status from these diagnostics
          (var worst :pass)
          (each [_ d (ipairs result)]
            (if (. d :interrupted)
                (set worst (worse-status worst :interrupted))
                (= d.family :framework)
                (set worst (worse-status worst :fail))
                (set worst (worse-status worst :violations))))
          (set status (worse-status status worst)))))
    (let [counts (Diagnostics.summary status all-diagnostics)]
      {:status status
       :counts counts
       :diagnostics all-diagnostics})))

(fn M.main [opts]
  "Entry point for the constraints runner.
  Accepts injectable :print and :exit for testability; tolerates nil opts
  for the runtime's zero-argument module entry-point convention.
  opts: {:rules [] :target <target> :print <fn> :exit <fn> :argv []}"
  (local o (or opts {}))
  (let [print-fn (or o.print print)
        exit-fn (or o.exit os.exit)
        rules (or o.rules [])
        target (or o.target {:kind :repo :name "default"})
        result (M.run {:rules rules :target target})]
    (print-fn (json.dumps result))
    (if (= result.status :pass)
        (exit-fn 0)
        (exit-fn 1))))

M
