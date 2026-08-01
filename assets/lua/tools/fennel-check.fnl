(local json (require :json))
(local ServiceModule (require :llm/fennel-validation/service))

(fn failure-result [message]
  {:ok false
   :status :fail
   :checked []
   :diagnostics [{:kind :input
                  :file ""
                  :line nil
                  :column nil
                  :message (tostring message)
                  :hint "Pass a valid fennel-check target."}]
   :summary {:checked 0
             :failed 1}})

(fn service-result [argv opts]
  (local service (ServiceModule.FennelValidationService opts))
  (local target (service:resolve-target argv))
  (if (= target.kind :files)
      (service:check-files {:files target.files})
      (service:check-target target)))

(fn run [argv opts]
  (local resolved-argv (if argv argv []))
  (local resolved-opts (if opts opts {}))
  (local (ok result-or-error)
    (pcall service-result resolved-argv resolved-opts))
  (if ok
      result-or-error
      (failure-result result-or-error)))

(fn normalized-global-argv []
  (local source (if _G.arg _G.arg []))
  (local start (if (= (. source 1) "--") 2 1))
  (local result [])
  (var index start)
  (while (<= index (# source))
    (table.insert result (. source index))
    (set index (+ index 1)))
  result)

(fn io-options? [arg]
  (and (= (type arg) :table)
       (not arg.argv)
       (if arg.print
           true
           arg.exit
           true
           false)))

(fn main-options [opts-or-argv]
  (local arg (if opts-or-argv opts-or-argv {}))
  (if (and (= (type arg) :table) arg.argv)
      {:argv arg.argv
       :opts arg
       :print arg.print
       :exit arg.exit}
      (io-options? arg)
      {:argv (normalized-global-argv)
       :opts arg
       :print arg.print
       :exit arg.exit}
      (not opts-or-argv)
      {:argv (normalized-global-argv)
       :opts {}
       :print nil
       :exit nil}
      {:argv (if (= (type arg) :table) arg [])
       :opts {}
       :print nil
       :exit nil}))

(fn main [opts-or-argv]
  (local options (main-options opts-or-argv))
  (local print-fn (if options.print options.print print))
  (local exit-fn (if options.exit options.exit os.exit))
  (local result (run options.argv options.opts))
  (print-fn (json.dumps result))
  (if result.ok
      (exit-fn 0)
      (exit-fn 1)))

{:run run
 :main main}
