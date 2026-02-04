(local tests [])
(local CliArgs (require :cli-args))

(fn parse-basic-flags []
  (local spec {:name "tool"
               :options [{:key "verbose" :short "v" :count? true :help "Verbosity"}
                         {:key "output" :short "o" :long "output" :takes-value? true}
                         {:key "dry-run" :long "dry-run"}]
               :positionals [{:key "input" :required? true}]})
  (local result (CliArgs.parse spec ["-vv" "--output=out.txt" "file.txt"]))
  (assert result.ok)
  (assert (= (. result.values "verbose") 2))
  (assert (= (. result.values "output") "out.txt"))
  (assert (= (. result.values "dry-run") nil))
  (assert (= (. result.values "input") "file.txt"))
  true)

(fn parse-short-value []
  (local spec {:name "tool"
               :options [{:key "output" :short "o" :takes-value? true}]
               :positionals [{:key "input"}]})
  (local result (CliArgs.parse spec ["-ooutput.bin" "data.bin"]))
  (assert result.ok)
  (assert (= (. result.values "output") "output.bin"))
  (assert (= (. result.values "input") "data.bin"))
  true)

(fn parse-flag-with-value []
  (local spec {:name "tool"
               :options [{:key "color" :long "color"}]})
  (local result (CliArgs.parse spec ["--color=false"]))
  (assert result.ok)
  (assert (= (. result.values "color") false))
  true)

(fn parse-repeatable []
  (local spec {:name "tool"
               :options [{:key "include" :short "I" :takes-value? true :repeatable? true}]
               :positionals [{:key "files" :repeatable? true}]})
  (local result (CliArgs.parse spec ["-Iinc1" "-I" "inc2" "a.txt" "b.txt"]))
  (assert result.ok)
  (assert (= (length (. result.values "include")) 2))
  (assert (= (. (. result.values "include") 1) "inc1"))
  (assert (= (. (. result.values "include") 2) "inc2"))
  (assert (= (length (. result.values "files")) 2))
  (assert (= (. (. result.values "files") 1) "a.txt"))
  (assert (= (. (. result.values "files") 2) "b.txt"))
  true)

(fn parse-stop-options []
  (local spec {:name "tool"
               :options [{:key "flag" :short "f"}]
               :positionals [{:key "file" :required? true}]})
  (local result (CliArgs.parse spec ["-f" "--" "--not-a-flag"]))
  (assert result.ok)
  (assert (= (. result.values "flag") true))
  (assert (= (. result.values "file") "--not-a-flag"))
  true)

(fn parse-unknown-allowed []
  (local spec {:name "tool"
               :allow-unknown? true
               :options [{:key "flag" :short "f"}]
               :positionals [{:key "file"}]})
  (local result (CliArgs.parse spec ["--mystery" "-f" "asset.txt"]))
  (assert result.ok)
  (assert (= (. result.values "flag") true))
  (assert (= (. result.values "file") "asset.txt"))
  (assert (= (length result.unknown) 1))
  (assert (= (. result.unknown 1) "--mystery"))
  true)

(fn parse-missing-required []
  (local spec {:name "tool"
               :positionals [{:key "file" :required? true}]})
  (local result (CliArgs.parse spec []))
  (assert (not result.ok))
  (assert (string.find result.error "missing required argument" 1 true))
  true)

(fn parse-help []
  (local spec {:name "tool"
               :summary "Example parser"
               :options [{:key "flag" :short "f" :help "Enable flag"}]
               :positionals [{:key "file" :help "Input file"}]})
  (local result (CliArgs.parse spec ["--help"]))
  (assert (not result.ok))
  (assert result.help?)
  (assert (string.find result.usage "usage:" 1 true))
  (assert (string.find result.usage "Options:" 1 true))
  (assert (string.find result.usage "Arguments:" 1 true))
  true)

(table.insert tests {:name "CLI args parse flags and values" :fn parse-basic-flags})
(table.insert tests {:name "CLI args parse short attached value" :fn parse-short-value})
(table.insert tests {:name "CLI args parse boolean flag value" :fn parse-flag-with-value})
(table.insert tests {:name "CLI args parse repeatable args" :fn parse-repeatable})
(table.insert tests {:name "CLI args stop parsing on --" :fn parse-stop-options})
(table.insert tests {:name "CLI args allow unknown options" :fn parse-unknown-allowed})
(table.insert tests {:name "CLI args missing required argument" :fn parse-missing-required})
(table.insert tests {:name "CLI args help output" :fn parse-help})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "cli-args"
                       :tests tests})))

{:name "cli-args"
 :tests tests
 :main main}
