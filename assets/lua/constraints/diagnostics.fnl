;; Diagnostics module for experimental Fennel constraints.
;; Provides diagnostic normalization and summary counting.

(local M {})

(fn assert-required [opts field-name message]
  "Assert that a required field is present in opts, raising message if missing."
  (when (not (. opts field-name))
    (error (or message (.. "constraint diagnostic missing " field-name)) 2)))

(fn M.violation [opts]
  "Create a normalized violation diagnostic from opts.
  Required: :constraint-id, :family, :message, :hint.
  Defaults: :severity -> :error, :evidence -> {}."
  (assert-required opts :constraint-id "constraint diagnostic missing constraint-id")
  (assert-required opts :family "constraint diagnostic missing family")
  (assert-required opts :message "constraint diagnostic missing message")
  (assert-required opts :hint "constraint diagnostic missing hint")
  (let [diagnostic {:constraint-id opts.constraint-id
                    :family opts.family
                    :severity (or opts.severity :error)
                    :message opts.message
                    :evidence (or opts.evidence {})
                    :hint opts.hint}]
    (when opts.target
      (set diagnostic.target opts.target))
    (when opts.file
      (set diagnostic.file opts.file))
    (when opts.line
      (set diagnostic.line opts.line))
    (when opts.column
      (set diagnostic.column opts.column))
    diagnostic))

(fn M.framework-failure [opts]
  "Create a normalized framework-failure diagnostic from opts.
  Required: :constraint-id, :family, :message, :hint.
  Defaults: :severity -> :error, :evidence -> {}.
  Uses the same normalization as violation."
  (M.violation (or opts {})))

(fn M.summary [status diagnostics]
  "Produce a result summary table from a list of diagnostics.
  Returns {:total <n> :by-family <table> :by-severity <table>}."
  (let [by-family {}
        by-severity {}
        total (length diagnostics)]
    (each [_ d (ipairs diagnostics)]
      (let [family (or d.family :unknown)
            severity (or d.severity :error)]
        ;; increment family count
        (tset by-family family (+ (or (. by-family family) 0) 1))
        ;; increment severity count
        (tset by-severity severity (+ (or (. by-severity severity) 0) 1))))
    {:total total
     :by-family by-family
     :by-severity by-severity}))

M
