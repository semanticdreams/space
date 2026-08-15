(local {: WorkflowStore} (require :workflows/store))
(local {: WorkflowRunner} (require :workflows/runner))
(local {: WorkflowCodeExecutor} (require :workflows/code-executor))
(local {: CodeEntityStore} (require :entities/code))
(local SessionMigration (require :llm/agent/session-migration))

(fn normalized-global-argv []
  (local source (if _G.arg _G.arg []))
  (local start (if (= (. source 1) "--") 2 1))
  (local result [])
  (var index start)
  (while (<= index (# source))
    (table.insert result (. source index))
    (set index (+ index 1)))
  result)

(fn parse-argv [argv]
  (local options {})
  (var index 1)
  (while (<= index (# argv))
    (local arg (. argv index))
    (if (= arg "--base-dir")
        (do
          (set index (+ index 1))
          (tset options :base-dir (. argv index)))
        (error (.. "unknown argument: " (tostring arg))))
    (set index (+ index 1)))
  (assert options.base-dir "agent-session-migrate requires --base-dir <space-user-data-dir>")
  options)

(fn make-deps [base-dir]
  (local workflow-store (WorkflowStore {:base-dir base-dir}))
  (local code-store (CodeEntityStore {:base-dir base-dir}))
  (local executor (WorkflowCodeExecutor {:code-store code-store :app {}}))
  (local workflow-runner (WorkflowRunner {:store workflow-store :executor executor :app {}}))
  {:workflow-store workflow-store
   :code-store code-store
   :workflow-runner workflow-runner})

(fn report-lines [result]
  (local lines [(.. "migrated: " result.migrated)
                (.. "archived: " result.archived)
                (.. "archive-dir: " result.archive-dir)
                "mapping:"])
  (local ids [])
  (each [legacy-id _run-id (pairs result.mapping)]
    (table.insert ids legacy-id))
  (table.sort ids)
  (each [_ legacy-id (ipairs ids)]
    (table.insert lines (.. "  " legacy-id " -> " (. result.mapping legacy-id))))
  lines)

(fn run [argv]
  (local parsed (parse-argv argv))
  (local deps (make-deps parsed.base-dir))
  (SessionMigration.migrate {:base-dir parsed.base-dir
                             :workflow-store deps.workflow-store
                             :workflow-runner deps.workflow-runner
                             :code-store deps.code-store}))

(fn main [opts-or-argv]
  (local argv (if (and (= (type opts-or-argv) "table") opts-or-argv.argv)
                  opts-or-argv.argv
                  (= (type opts-or-argv) "table")
                  opts-or-argv
                  (normalized-global-argv)))
  (local print-fn (if (and (= (type opts-or-argv) "table") opts-or-argv.print)
                    opts-or-argv.print
                    print))
  (local exit-fn (if (and (= (type opts-or-argv) "table") opts-or-argv.exit)
                   opts-or-argv.exit
                   os.exit))
  (local (ok result-or-err) (pcall run argv))
  (if ok
      (do
        (each [_ line (ipairs (report-lines result-or-err))]
          (print-fn line))
        (exit-fn 0))
      (do
        (print-fn (.. "agent-session-migrate failed: " (tostring result-or-err)))
        (exit-fn 1))))

{:run run
 :main main}
