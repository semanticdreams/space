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

(fn M.run-rule [rule target]
  "Run a single rule function against a target using xpcall.
  Returns nil on pass, or a list of diagnostics on failure/crash.
  Uses debug.traceback for crash diagnostics."
  (let [diagnostics []
        ;; Capture the rule name if available, before calling
        rule-id (or (and (= (type rule) :table) (. rule :constraint-id)) :unknown-rule)
        (ok result) (xpcall
                      ;; protected function
                      (fn [] (rule target))
                      ;; error handler: runs on crash, populates diagnostics in-place
                      (fn [err-obj]
                        (let [tb (if _G.debug
                                    (_G.debug.traceback err-obj 3)
                                    (tostring err-obj))]
                          (table.insert diagnostics
                            (Diagnostics.framework-failure
                              {:constraint-id rule-id
                               :family :framework
                               :message (.. "rule crashed: " (tostring err-obj))
                               :evidence {:traceback tb}
                               :hint "check the rule implementation for errors"})))))]
    (when (and ok result)
      ;; Rule succeeded and returned something
      (when (= (type result) :table)
        (if (. result :constraint-id)
            (table.insert diagnostics result)
            (each [_ d (ipairs result)]
              (table.insert diagnostics d)))))
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
      (let [result (M.run-rule rule target)]
        (when result
          ;; result is a list of diagnostics
          (each [_ d (ipairs result)]
            (table.insert all-diagnostics d))
          ;; Determine status from these diagnostics
          ;; A crashing rule produces framework-failure diagnostics → :fail
          ;; A violation-producing rule → :violations
          (var worst :pass)
          (each [_ d (ipairs result)]
            (if (= d.family :framework)
                (set worst (worse-status worst :fail))
                (set worst (worse-status worst :violations))))
          (set status (worse-status status worst)))))
    (let [counts (Diagnostics.summary status all-diagnostics)]
      {:status status
       :counts counts
       :diagnostics all-diagnostics})))

(fn M.main [opts]
  "Entry point for the constraints runner.
  Accepts injectable :print and :exit for testability.
  opts: {:rules [] :target <target> :print <fn> :exit <fn> :argv []}"
  (let [print-fn (or opts.print print)
        exit-fn (or opts.exit os.exit)
        rules (or opts.rules [])
        target (or opts.target {:kind :repo :name "default"})
        result (M.run {:rules rules :target target})]
    (print-fn (json.dumps result))
    (if (= result.status :pass)
        (exit-fn 0)
        (exit-fn 1))))

M
