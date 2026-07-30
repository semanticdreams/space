(local logging (require :logging))
(local tests [])

(fn logging-module-exports []
  (assert (= (type logging.info) :function) "logging.info should be a function")
  (assert (= (type logging.warn) :function) "logging.warn should be a function")
  (assert (= (type logging.error) :function) "logging.error should be a function")
  (assert (= (type logging.debug) :function) "logging.debug should be a function")
  (assert (= (type logging.set-level) :function) "logging.set-level should be a function")
  (assert (= (type logging.get-level) :function) "logging.get-level should be a function")
  (assert (= (type logging.flush) :function) "logging.flush should be a function"))

(fn logging-accepts-varargs []
  (logging.info "hello" "world" 123)
  (logging.warn "warn" {:value 42})
  (logging.error "error" nil)
  (logging.debug "debug")
  (logging.flush))

(fn logging-set-level []
  (assert (logging.set-level "info") "logging.set-level should accept info")
  (assert (logging.set-level "warn") "logging.set-level should accept warn")
  (assert (logging.set-level "debug") "logging.set-level should accept debug")
  (assert (logging.set-level "error") "logging.set-level should accept error")
  (assert (not (logging.set-level "bogus")) "logging.set-level should reject unknown levels")
  (assert (logging.set-level "graph" "debug") "logging.set-level should accept named logger")
  (assert (not (logging.set-level "graph" "bogus")) "logging.set-level should reject unknown levels for named logger"))

(fn logging-get-level-round-trips-named-levels []
  (local original-space-level (logging.get-level "space"))
  (local original-mcp-level (logging.get-level "mcp"))
  (logging.set-level "space" "error")
  (logging.set-level "mcp" "warn")
  (assert (= (logging.get-level "space") "error") "space logger level should round-trip")
  (assert (= (logging.get-level "mcp") "warn") "mcp logger level should round-trip")
  (logging.set-level "space" original-space-level)
  (logging.set-level "mcp" original-mcp-level))

(fn logging-get-level-reads-existing-named-logger-after-default-change []
  (local logger (logging.get "untracked-test-logger"))
  (local original-space-level (logging.get-level "space"))
  (logger.set-level "warn")
  (logging.set-level "space" "error")
  (assert (= (logging.get-level "untracked-test-logger") "warn")
          "get-level should report existing named logger threshold, not current default")
  (logging.set-level "untracked-test-logger" "info")
  (logging.set-level "space" original-space-level))

(fn logging-get-named-logger []
  (local logger (logging.get "graph"))
  (assert logger "logging.get should return a logger table")
  (assert (= logger.name "graph") "logger should preserve name")
  (logger.set-level "info")
  (logger.info "graph log")
  (logger.warn "graph warning")
  (logger.flush))

(table.insert tests {:name "logging exports basic methods" :fn logging-module-exports})
(table.insert tests {:name "logging accepts varargs" :fn logging-accepts-varargs})
(table.insert tests {:name "logging set-level validates strings" :fn logging-set-level})
(table.insert tests {:name "logging get-level round-trips named levels" :fn logging-get-level-round-trips-named-levels})
(table.insert tests {:name "logging get-level reads existing named logger after default change"
                     :fn logging-get-level-reads-existing-named-logger-after-default-change})
(table.insert tests {:name "logging get returns named logger" :fn logging-get-named-logger})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "logging"
                       :tests tests})))

{:name "logging"
 :tests tests
 :main main}
