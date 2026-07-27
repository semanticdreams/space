;; Tests for Lifecycle and Test-Isolation constraint rules.
;; Follows TDD: these tests must FAIL before lifecycle.fnl and test-isolation.fnl are implemented.

(local tests [])

;; --- Helpers for constructing synthetic fact DBs ---

(fn make-file-fact [opts]
  "Create a synthetic file-fact record for testing rule functions."
  (local o (or opts {}))
  {:target (or o.target {:kind :repo :name :test})
   :path (or o.path "/test/module.fnl")
   :module (or o.module "test-module")
   :requires (or o.requires [])
   :definitions (or o.definitions [])
   :exports (or o.exports [])
   :calls (or o.calls [])
   :accesses (or o.accesses [])
   :mutations (or o.mutations [])
   :metrics (or o.metrics {:module-lines 0
                           :max-nesting-depth 0
                           :max-anonymous-callback-depth 0
                           :max-table-literal-size 0
                           :functions []})})

(fn make-fact-db [file-facts]
  "Create a synthetic fact-db from a list of file-fact records."
  (let [by-file {}]
    (each [_ ff (ipairs file-facts)]
      (tset by-file ff.path ff))
    {:files file-facts
     :by-file by-file}))

(fn make-ctx [file-facts]
  "Create a context table for rule execution."
  {:target {:kind :repo :name :test}
   :facts (make-fact-db file-facts)
   :files []})

(fn find-rule-by-id [rules id]
  "Find a rule in a rules list by its :id field."
  (var found nil)
  (each [_ r (ipairs rules)]
    (when (= r.id id)
      (set found r)))
  found)

;; Sensitive globals as defined by the lifecycle/test-isolation spec.
(local sensitive-globals
  ["app.renderers"
   "app.lights"
   "app.engine"
   "app.activity-registry"
   "app.physics-containment-config"
   "package.loaded"])

;; ======================================================================
;; lifecycle.event-registration-cleanup
;; ======================================================================

(fn registration-cleanup-allows-file-without-registrations []
  "A file with no registration calls (connect, register, event.updated:connect)
  should pass the cleanup rule."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule lifecycle.event-registration-cleanup should be in rules list")
  (local ff (make-file-fact {:path "/src/clean-module.fnl"
                             :module "clean-module"
                             :calls [{:callee "print"
                                      :receiver nil :method nil
                                      :line 1 :column 1
                                      :form "(print :hello)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file without registrations should pass"))

(fn registration-cleanup-allows-file-with-registration-and-cleanup []
  "A file that has both connect/register calls and disconnect/drop calls
  should pass."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :calls [{:callee "some-obj:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(some-obj:connect handler)"}
                                     {:callee "some-obj:disconnect"
                                      :receiver nil :method nil
                                      :line 20 :column 1
                                      :form "(some-obj:disconnect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with registration and cleanup should pass"))

(fn registration-cleanup-allows-register-with-unregister []
  "register and unregister pair should pass."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :calls [{:callee "register"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(register event-handler)"}
                                     {:callee "unregister"
                                      :receiver nil :method nil
                                      :line 20 :column 1
                                      :form "(unregister event-handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with register and unregister should pass"))

(fn registration-cleanup-allows-connect-with-drop-cleanup []
  "connect registration with a drop cleanup method should pass.
  drop is treated as a cleanup path by the spec."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :calls [{:callee "some-obj:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(some-obj:connect handler)"}
                                     {:callee "some-obj:drop"
                                      :receiver nil :method nil
                                      :line 25 :column 1
                                      :form "(some-obj:drop)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with connect and :drop cleanup should pass"))

(fn registration-cleanup-flags-file-with-connect-no-cleanup []
  "A file with connect (or :connect) calls but no disconnect/drop/unregister/clear
  calls should produce a diagnostic."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :calls [{:callee "event-system:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(event-system:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "lifecycle") "diagnostic should have family lifecycle")
  (assert (= d.file ff.path) "diagnostic should include file path")
  (assert d.evidence "diagnostic should include evidence")
  (assert (= d.evidence.registration-count 1) "evidence should report registration count")
  (assert (> (length d.evidence.registration-forms) 0) "evidence should include registration forms"))

(fn registration-cleanup-flags-file-with-app-engine-events-updated-connect []
  "app.engine.events.updated:connect is an explicit registration pattern
  that must have cleanup evidence."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :calls [{:callee "app.engine.events.updated:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(app.engine.events.updated:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for app.engine.events.updated:connect")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup")
          "diagnostic should have correct constraint-id")
  (assert d.evidence "diagnostic should include evidence")
  ;; Evidence should include registration forms
  (assert (> (length d.evidence.registration-forms) 0) "evidence should include registration forms")
  (assert (= d.evidence.registration-count 1) "evidence should report registration count"))

(fn registration-cleanup-flags-file-with-register-no-unregister []
  "register without unregister should produce a diagnostic."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :calls [{:callee "register"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(register event-handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for register without unregister")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup")
          "diagnostic should have correct constraint-id"))

(fn registration-cleanup-allows-connect-with-clear-cleanup []
  "connect registration with clear cleanup should pass (clear is a recognized cleanup path)."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :calls [{:callee "some-obj:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(some-obj:connect handler)"}
                                     {:callee "clear"
                                      :receiver nil :method nil
                                      :line 25 :column 1
                                      :form "(clear handlers)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with connect and clear cleanup should pass"))

(fn registration-cleanup-allows-function-named-cleanup []
  "A file with connect registration and a function named cleanup should pass.
  Functions named drop, cleanup, teardown, shutdown, and unload are cleanup paths."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :definitions [{:kind :fn
                                            :name "cleanup"
                                            :top-level? true
                                            :line 30 :column 1
                                            :length 10
                                            :form "(fn cleanup [] (some-obj:disconnect handler))"}]
                             :calls [{:callee "some-obj:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(some-obj:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with function named cleanup should pass"))

(fn registration-cleanup-allows-function-named-teardown []
  "A file with connect registration and a function named teardown should pass."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :definitions [{:kind :fn
                                            :name "teardown"
                                            :top-level? true
                                            :line 30 :column 1
                                            :length 10
                                            :form "(fn teardown [] (disconnect handler))"}]
                             :calls [{:callee "some-obj:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(some-obj:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with function named teardown should pass"))

(fn registration-cleanup-allows-function-named-shutdown []
  "A file with connect registration and a function named shutdown should pass."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :definitions [{:kind :fn
                                            :name "shutdown"
                                            :top-level? true
                                            :line 30 :column 1
                                            :length 10
                                            :form "(fn shutdown [] (some-obj:disconnect handler))"}]
                             :calls [{:callee "some-obj:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(some-obj:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with function named shutdown should pass"))

(fn registration-cleanup-allows-connect-with-clear-method []
  "A file with connect registration and a :clear method call should pass.
  clear and unregister should be recognized in method-call form too."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :calls [{:callee "some-signal:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(some-signal:connect handler)"}
                                     {:callee "some-signal:clear"
                                      :receiver nil :method nil
                                      :line 25 :column 1
                                      :form "(some-signal:clear)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with connect and :clear method should pass"))

(fn registration-cleanup-allows-connect-with-unregister-method []
  "A file with connect registration and a :unregister method call should pass."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :calls [{:callee "registry:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(registry:connect handler)"}
                                     {:callee "registry:unregister"
                                      :receiver nil :method nil
                                      :line 25 :column 1
                                      :form "(registry:unregister handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with connect and :unregister method should pass"))

(fn registration-cleanup-allows-function-named-unload []
  "A file with connect registration and a function named unload should pass."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :definitions [{:kind :fn
                                            :name "unload"
                                            :top-level? true
                                            :line 30 :column 1
                                            :length 10
                                            :form "(fn unload [] (some-obj:disconnect handler))"}]
                             :calls [{:callee "some-obj:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(some-obj:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with function named unload should pass"))

;; --- Precision: disconnect-* helper calls and functions ---

(fn registration-cleanup-allows-disconnect-dash-helper-call []
  "A file with connect registrations and a call to disconnect-input (or any
  disconnect-* helper) should pass — these are recognized cleanup calls."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :calls [{:callee "some-obj:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(some-obj:connect handler)"}
                                     {:callee "disconnect-input"
                                      :receiver nil :method nil
                                      :line 25 :column 1
                                      :form "(disconnect-input)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with disconnect-* helper call should pass"))

(fn registration-cleanup-allows-disconnect-dash-function-name []
  "A file with connect registrations and a function named disconnect-update
  should pass — disconnect-* function names are recognized as cleanup evidence."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :definitions [{:kind :fn
                                            :name "disconnect-update"
                                            :top-level? true
                                            :line 30 :column 1
                                            :length 10
                                            :form "(fn disconnect-update [] (some-obj:disconnect handler))"}]
                             :calls [{:callee "some-obj:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(some-obj:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with function named disconnect-* should pass"))

;; --- R1-3: handler-record cleanup loops ---

(fn registration-cleanup-allows-loop-cleanup-over-handler-records []
  "A file with multiple :connect registrations and a single disconnect call
  inside a loop that iterates over handler records should pass — one loop
  disconnect covers all stored registrations."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :definitions [{:kind :fn
                                            :name "cleanup-handlers"
                                            :top-level? true
                                            :line 30 :column 1
                                            :length 20
                                            :form "(fn cleanup-handlers []
  (each [_ record (ipairs handlers)]
    (record.signal:disconnect record.handler true)))"}]
                             :calls [{:callee "signal-a:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(signal-a:connect handler1)"}
                                     {:callee "signal-b:connect"
                                      :receiver nil :method nil
                                      :line 12 :column 1
                                      :form "(signal-b:connect handler2)"}
                                     {:callee "signal-c:connect"
                                      :receiver nil :method nil
                                      :line 14 :column 1
                                      :form "(signal-c:connect handler3)"}
                                     {:callee "record.signal:disconnect"
                                      :receiver nil :method nil
                                      :line 32 :column 1
                                      :form "(record.signal:disconnect record.handler true)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "loop cleanup over handler records should pass"))

(fn registration-cleanup-allows-loop-cleanup-in-drop-function []
  "A file with multiple :connect registrations where a function named 'drop'
  contains an each-loop calling :disconnect should pass — the drop function
  plus loop cleanup covers all registrations."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :definitions [{:kind :fn
                                            :name "drop"
                                            :top-level? true
                                            :line 30 :column 1
                                            :length 20
                                            :form "(fn drop []
  (each [_ record (ipairs view.handlers)]
    (record.signal:disconnect record.handler true)))"}]
                             :calls [{:callee "signal-a:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(signal-a:connect handler1)"}
                                     {:callee "signal-b:connect"
                                      :receiver nil :method nil
                                      :line 12 :column 1
                                      :form "(signal-b:connect handler2)"}
                                     {:callee "record.signal:disconnect"
                                      :receiver nil :method nil
                                      :line 32 :column 1
                                      :form "(record.signal:disconnect record.handler true)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "drop function with loop cleanup should pass"))

(fn registration-cleanup-still-flags-no-cleanup-at-all []
  "A file with :connect registrations and ZERO cleanup calls (even with a
  function that has an 'each' loop — but no disconnect inside) should still
  be flagged."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :definitions [{:kind :fn
                                            :name "do-stuff"
                                            :top-level? true
                                            :line 30 :column 1
                                            :length 10
                                            :form "(fn do-stuff []
  (each [_ x (ipairs items)]
    (print x)))"}]
                             :calls [{:callee "signal-a:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(signal-a:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should still flag registrations with no cleanup calls at all")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup")
          "diagnostic should have correct constraint-id"))

(fn registration-cleanup-still-flags-connect-without-any-cleanup []
  "A bare :connect with no cleanup calls and no loop function should still
  be flagged — the original positive test must be preserved."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :calls [{:callee "event-system:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(event-system:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for connect without cleanup")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup")
          "diagnostic should have correct constraint-id"))

;; --- R2-2: helper loops should be recognized; cleanup-like text without calls should not ---

(fn registration-cleanup-allows-loop-with-disconnect-dash-helper []
  "A file with multiple :connect registrations and a loop calling a
  disconnect-input helper (extracted as a call fact) should pass —
  the loop plus cleanup call covers all registrations."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :definitions [{:kind :fn
                                            :name "cleanup-handlers"
                                            :top-level? true
                                            :line 30 :column 1
                                            :length 20
                                            :form "(fn cleanup-handlers []
  (each [_ record (ipairs handlers)]
    (disconnect-input record)))"}]
                             :calls [{:callee "signal-a:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(signal-a:connect handler1)"}
                                     {:callee "signal-b:connect"
                                      :receiver nil :method nil
                                      :line 12 :column 1
                                      :form "(signal-b:connect handler2)"}
                                     {:callee "disconnect-input"
                                      :receiver nil :method nil
                                      :line 32 :column 1
                                      :form "(disconnect-input record)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "loop with disconnect-* helper call should pass"))

(fn registration-cleanup-flags-file-with-loop-but-no-cleanup-calls []
  "A file with :connect registrations where a function has an 'each' loop
  and cleanup-like TEXT (:disconnect in a comment or similar) but ZERO
  actual extracted cleanup CALLS should still be flagged — has-loop-cleanup?
  must not suppress the no-cleanup diagnostic when cl-count is zero."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  ;; A loop with the text ':disconnect' inside a string, no actual disconnect call fact
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :definitions [{:kind :fn
                                            :name "log-loop"
                                            :top-level? true
                                            :line 30 :column 1
                                            :length 10
                                            :form "(fn log-loop []
  (each [_ x (ipairs items)]
    (print \"use :disconnect to clean up\")))"}]
                             :calls [{:callee "signal-a:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(signal-a:connect handler)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag no-cleanup when loop has :disconnect text but no cleanup calls")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup")
          "diagnostic should have correct constraint-id"))

;; --- R3-1: partial cleanup + cleanup-like loop text must still flag ---

(fn registration-cleanup-flags-partial-cleanup-with-fake-loop-text []
  "A file with 2 registrations, 1 real cleanup call outside a loop, and a
  separate function with a loop whose text merely mentions ':disconnect' in a
  string (NOT an actual cleanup call in that loop) should still flag
  insufficient cleanup. has-loop-cleanup? must require actual cleanup call
  evidence, not raw text tokens."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  ;; ARP: string contains the EXACT text of the cleanup call form,
  ;; so old substring matching in has-loop-cleanup? would incorrectly
  ;; match it.  New line-range matching correctly ignores it because
  ;; the real cleanup call at line 20 falls outside the loop function
  ;; range [line 30, end].
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :definitions [{:kind :fn
                                            :name "log-reminder"
                                            :top-level? true
                                            :line 30 :column 1
                                            :length 20
                                            :form "(fn log-reminder []
  (each [_ x (ipairs items)]
    (print \"(some-obj:disconnect handler1)\")))"}]
                             :calls [{:callee "signal-a:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(signal-a:connect handler1)"}
                                     {:callee "signal-b:connect"
                                      :receiver nil :method nil
                                      :line 12 :column 1
                                      :form "(signal-b:connect handler2)"}
                                     ;; One real cleanup call — but it's NOT inside the loop
                                     {:callee "some-obj:disconnect"
                                      :receiver nil :method nil
                                      :line 20 :column 1
                                      :form "(some-obj:disconnect handler1)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should flag insufficient cleanup — loop has no real cleanup call")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup")
          "diagnostic should have correct constraint-id"))

(fn registration-cleanup-flags-file-with-partial-cleanup []
  "A file with two registrations but only one cleanup should produce diagnostics
  for the unmatched registration."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.event-registration-cleanup"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :calls [{:callee "some-obj:connect"
                                      :receiver nil :method nil
                                      :line 10 :column 1
                                      :form "(some-obj:connect handler1)"}
                                     {:callee "other-obj:connect"
                                      :receiver nil :method nil
                                      :line 12 :column 1
                                      :form "(other-obj:connect handler2)"}
                                     {:callee "some-obj:disconnect"
                                      :receiver nil :method nil
                                      :line 20 :column 1
                                      :form "(some-obj:disconnect handler1)"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for unmatched registration")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.event-registration-cleanup")
          "diagnostic should have correct constraint-id"))


;; ======================================================================
;; lifecycle.required-runtime-fails-loudly
;; ======================================================================

(fn required-runtime-allows-file-with-no-sensitive-accesses []
  "A file that does not access any sensitive globals should pass."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule lifecycle.required-runtime-fails-loudly should be in rules list")
  (local ff (make-file-fact {:path "/src/clean-module.fnl"
                             :module "clean-module"
                             :accesses []
                             :definitions []}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file without sensitive accesses should pass"))

(fn required-runtime-allows-file-with-assert-and-sensitive-access []
  "A file that accesses a sensitive global but uses assert in the same
  function should pass."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :accesses [{:path ["app" "engine"]
                                         :text "app.engine"
                                         :line 5 :column 1
                                         :form "app.engine"}]
                             :definitions [{:kind :fn
                                            :name "do-work"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn do-work []
  (assert app.engine \"requires engine\"))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with assert and sensitive access should pass"))

(fn required-runtime-allows-file-with-error-and-sensitive-access []
  "A file that accesses a sensitive global but uses error in the same
  function should pass."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :accesses [{:path ["app" "renderers"]
                                         :text "app.renderers"
                                         :line 8 :column 1
                                         :form "app.renderers"}]
                             :definitions [{:kind :fn
                                            :name "get-renderer"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 120
                                            :form "(fn get-renderer []
  (when (not app.renderers)
    (error \"app.renderers is nil, required runtime not loaded\")))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with error in same function should pass"))

(fn required-runtime-flags-file-with-or-synthesizing-sensitive-global []
  "A file that accesses a sensitive global and uses or to synthesize
  a default value without assert/error should produce a diagnostic."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :accesses [{:path ["app" "renderers"]
                                         :text "app.renderers"
                                         :line 5 :column 1
                                         :form "app.renderers"}]
                             :definitions [{:kind :fn
                                            :name "get-renderer"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn get-renderer []
  (or app.renderers {}))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for or-pattern without assert")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.required-runtime-fails-loudly")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "lifecycle") "diagnostic should have family lifecycle")
  (assert (= d.file ff.path) "diagnostic should include file path")
  (assert d.evidence "diagnostic should include evidence")
  (assert d.hint "diagnostic should include hint"))

(fn required-runtime-allows-when-conditional-execution []
  "A file that accesses a sensitive global and uses when for conditional
  execution should NOT be flagged — when is guard logic, not silent fallback."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :accesses [{:path ["app" "lights"]
                                         :text "app.lights"
                                         :line 5 :column 1
                                         :form "app.lights"}]
                             :definitions [{:kind :fn
                                            :name "add-light"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn add-light [l]
  (when app.lights
    (tset app.lights :extra l)))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "file with when-pattern should pass — when is guard, not synthesis"))

;; --- R1-1: if-based synthesis should still be caught (but benign if branches should not) ---

(fn required-runtime-flags-if-synthesizing-engine []
  "A function using (if app.engine app.engine (make-debug-engine)) with an else
  fallback that synthesizes a substitute should still be flagged — this is true
  top-level sensitive-global fallback synthesis."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :accesses [{:path ["app" "engine"]
                                         :text "app.engine"
                                         :line 5 :column 1
                                         :form "app.engine"}]
                             :definitions [{:kind :fn
                                            :name "get-engine"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn get-engine []
  (if app.engine
    app.engine
    (make-debug-engine)))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for if-synthesis pattern")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.required-runtime-fails-loudly")
          "diagnostic should have correct constraint-id"))

(fn required-runtime-flags-if-synthesizing-renderers []
  "A function using (if app.renderers app.renderers {}) with an else fallback
  that synthesizes a default empty table should be flagged."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :accesses [{:path ["app" "renderers"]
                                         :text "app.renderers"
                                         :line 5 :column 1
                                         :form "app.renderers"}]
                             :definitions [{:kind :fn
                                            :name "get-renderers"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn get-renderers []
  (if app.renderers
    app.renderers
    {}))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for if-synthesis of renderers")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.required-runtime-fails-loudly")
          "diagnostic should have correct constraint-id"))

(fn required-runtime-allows-if-benign-branch []
  "A function using (if app.engine (process app.engine) (log-missing)) with
  branching logic but NO synthesis of the global itself should NOT be flagged."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :accesses [{:path ["app" "engine"]
                                         :text "app.engine"
                                         :line 5 :column 1
                                         :form "app.engine"}]
                             :definitions [{:kind :fn
                                            :name "maybe-process"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn maybe-process []
  (if app.engine
    (process app.engine)
    (log-missing)))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "benign if branch should not be flagged as synthesis"))

;; --- Precision: guard patterns should NOT be flagged ---

(fn required-runtime-allows-and-guard-pattern []
  "A function using (and app.engine app.engine.frame-id) as a guard check
  does not synthesize app.engine — it guards against nil before accessing subfields."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :accesses [{:path ["app" "engine"]
                                         :text "app.engine"
                                         :line 5 :column 1
                                         :form "app.engine"}]
                             :definitions [{:kind :fn
                                            :name "get-frame-id"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn get-frame-id []
  (and app.engine app.engine.frame-id))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "and guard pattern should not be flagged as synthesis"))

(fn required-runtime-allows-or-with-and-guard []
  "A function using (or (and app.engine app.engine.frame-id) 0) should not be
  flagged — the and-guarded or is not synthesizing app.engine itself."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :accesses [{:path ["app" "engine"]
                                         :text "app.engine"
                                         :line 5 :column 1
                                         :form "app.engine"}]
                             :definitions [{:kind :fn
                                            :name "get-frame-id"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn get-frame-id []
  (or (and app.engine app.engine.frame-id) 0))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "or with and-guard should not be flagged as synthesis"))

;; --- Precision: subfield defaults should NOT be flagged ---

(fn required-runtime-allows-subfield-default []
  "A function using (or app.engine.input.mouse.x 0) defaults a deep subfield,
  not the top-level app.engine global. This should not be flagged."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :accesses [{:path ["app" "engine"]
                                         :text "app.engine"
                                         :line 5 :column 1
                                         :form "app.engine"}]
                             :definitions [{:kind :fn
                                            :name "get-mouse-x"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn get-mouse-x []
  (or app.engine.input.mouse.x 0))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "subfield default should not be flagged as synthesis"))

(fn required-runtime-allows-renderers-subfield-default []
  "Defaults for subfields of app.renderers should not be flagged as
  synthesizing app.renderers itself."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :accesses [{:path ["app" "renderers"]
                                         :text "app.renderers"
                                         :line 5 :column 1
                                         :form "app.renderers"}]
                             :definitions [{:kind :fn
                                            :name "get-layer"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn get-layer []
  (or app.renderers.render-layer 0))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "renderers subfield default should not be flagged"))

;; --- R1-2: hyphenated sensitive globals must still be matched ---

(fn required-runtime-flags-activity-registry-synthesis []
  "A function using (or app.activity-registry {}) should be flagged —
  hyphenated sensitive globals must not evade pattern matching."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :accesses [{:path ["app" "activity-registry"]
                                         :text "app.activity-registry"
                                         :line 5 :column 1
                                         :form "app.activity-registry"}]
                             :definitions [{:kind :fn
                                            :name "get-registry"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn get-registry []
  (or app.activity-registry {}))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for hyphenated global synthesis")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.required-runtime-fails-loudly")
          "diagnostic should have correct constraint-id"))

(fn required-runtime-flags-physics-containment-config-synthesis []
  "A function using (or app.physics-containment-config {}) should be flagged —
  multiple hyphens in sensitive globals must not break pattern matching."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :accesses [{:path ["app" "physics-containment-config"]
                                         :text "app.physics-containment-config"
                                         :line 5 :column 1
                                         :form "app.physics-containment-config"}]
                             :definitions [{:kind :fn
                                            :name "get-config"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn get-config []
  (or app.physics-containment-config {}))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for multi-hyphen global synthesis")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.required-runtime-fails-loudly")
          "diagnostic should have correct constraint-id"))

(fn required-runtime-allows-hyphenated-subfield-default []
  "Subfield defaults for hyphenated globals should NOT be flagged."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/good-module.fnl"
                             :module "good-module"
                             :accesses [{:path ["app" "activity-registry"]
                                         :text "app.activity-registry"
                                         :line 5 :column 1
                                         :form "app.activity-registry"}]
                             :definitions [{:kind :fn
                                            :name "get-entry"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn get-entry []
  (or app.activity-registry.default-entry {}))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "hyphenated subfield default should not be flagged"))

;; --- Precision: genuine or-synthesis should still be flagged ---

(fn required-runtime-flags-file-with-set-or-synthesizing-global []
  "A function that uses (set app.engine (or app.engine {})) to synthesize
  a default global without assert/error should still be flagged."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :accesses [{:path ["app" "engine"]
                                         :text "app.engine"
                                         :line 5 :column 1
                                         :form "app.engine"}]
                             :definitions [{:kind :fn
                                            :name "ensure-engine"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn ensure-engine []
  (set app.engine (or app.engine {})))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for set+or synthesis pattern")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.required-runtime-fails-loudly")
          "diagnostic should have correct constraint-id"))

(fn required-runtime-flags-file-with-or-synthesizing-engine []
  "A function that uses (or app.engine {}) should still be flagged —
  this is top-level sensitive global synthesis without assert/error."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/bad-module.fnl"
                             :module "bad-module"
                             :accesses [{:path ["app" "engine"]
                                         :text "app.engine"
                                         :line 5 :column 1
                                         :form "app.engine"}]
                             :definitions [{:kind :fn
                                            :name "get-engine"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn get-engine []
  (or app.engine {}))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for or-synthesis of app.engine")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.required-runtime-fails-loudly")
          "diagnostic should have correct constraint-id"))

(fn required-runtime-allows-file-with-assert-in-outer-fn []
  "A file where the function with assertion is separate from the
  function using or-pattern should still flag the or-pattern function."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (local rule (find-rule-by-id rules "lifecycle.required-runtime-fails-loudly"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/src/mixed-module.fnl"
                             :module "mixed-module"
                             :accesses [{:path ["app" "renderers"]
                                         :text "app.renderers"
                                         :line 5 :column 1
                                         :form "app.renderers"}]
                             :definitions [{:kind :fn
                                            :name "get-renderers"
                                            :top-level? true
                                            :line 3 :column 1
                                            :length 100
                                            :form "(fn get-renderers []
  (or app.renderers {}))"}
                                           {:kind :fn
                                            :name "assert-renderers"
                                            :top-level? true
                                            :line 10 :column 1
                                            :length 80
                                            :form "(fn assert-renderers []
  (assert app.renderers \"no renderers\"))"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for or-pattern function")
  (assert (> (length result) 0) "should have at least one diagnostic")
  ;; The diagnostic should be about the get-renderers function, not assert-renderers
  (var found-or-diag false)
  (each [_ d (ipairs result)]
    (when (and (= d.constraint-id "lifecycle.required-runtime-fails-loudly")
               (. d.evidence :function-name)
               (= d.evidence.function-name "get-renderers"))
      (set found-or-diag true)))
  (assert found-or-diag "should flag the function with or-pattern"))


;; ======================================================================
;; lifecycle.global-mutation-restoration (test-isolation)
;; ======================================================================

(fn mutation-restoration-allows-non-test-file []
  "Files whose path does not contain /tests/ should skip the test-isolation rule."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule lifecycle.global-mutation-restoration should be in rules list")
  (local ff (make-file-fact {:path "/src/production.fnl"
                             :module "production"
                             :mutations [{:op :set
                                          :path ["app" "renderers"]
                                          :line 10 :column 1
                                          :form "(set app.renderers custom)"
                                          :enclosing-fn nil}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "non-test file should skip global mutation check"))

(fn mutation-restoration-allows-test-file-with-restoration []
  "A test file that mutates a sensitive global but has restoration evidence
  should pass. The fact extractor records ALL set/tset forms as mutations,
  including the restore write, so facts.mutations includes both."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                             :module "tests.test-module"
                             :definitions [{:kind :fn
                                            :name "test-with-restore"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 200
                                            :form "(fn test-with-restore []
  (let [orig app.renderers]
    (set app.renderers custom)
    (do-test)
    (set app.renderers orig)))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 7 :column 1
                                           :form "(set app.renderers custom)"
                                           :enclosing-fn "test-with-restore"}
                                          {:op :set
                                           :path ["app" "renderers"]
                                           :line 9 :column 1
                                           :form "(set app.renderers orig)"
                                           :enclosing-fn "test-with-restore"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "test file with restoration should pass"))

(fn mutation-restoration-allows-with-restored-app-fields []
  "A test file using with-restored-app-fields should pass."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                             :module "tests.test-module"
                             :definitions [{:kind :fn
                                            :name "test-mutate"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 150
                                            :form "(fn test-mutate []
  (with-restored-app-fields [app.renderers]
    (set app.renderers custom)
    (do-test)))"}]
                             :mutations [{:op :set
                                          :path ["app" "renderers"]
                                          :line 8 :column 1
                                          :form "(set app.renderers custom)"
                                          :enclosing-fn "test-mutate"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "test file with with-restored-app-fields should pass"))

(fn mutation-restoration-allows-pcall-cleanup-restore []
  "A test file using pcall for cleanup restoration should pass.
  The fact extractor records ALL set/tset forms as mutations,
  including the restore write, so facts.mutations includes both."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/tests/test-module.fnl"
                             :module "tests.test-module"
                             :definitions [{:kind :fn
                                            :name "test-pcall-restore"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 200
                                            :form "(fn test-pcall-restore []
  (let [orig app.renderers]
    (pcall (fn []
             (set app.renderers custom)
             (do-test))
           (set app.renderers orig))))"}]
                              :mutations [{:op :set
                                           :path ["app" "renderers"]
                                           :line 8 :column 1
                                           :form "(set app.renderers custom)"
                                           :enclosing-fn "test-pcall-restore"}
                                          {:op :set
                                           :path ["app" "renderers"]
                                           :line 10 :column 1
                                           :form "(set app.renderers orig)"
                                           :enclosing-fn "test-pcall-restore"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert (= result nil) "test file with pcall cleanup restore should pass"))

(fn mutation-restoration-flags-test-file-without-restoration []
  "A test file that mutates a sensitive global without any restoration
  evidence should produce a diagnostic."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                             :module "tests.test-bad"
                             :definitions [{:kind :fn
                                            :name "test-bad-mutate"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 100
                                            :form "(fn test-bad-mutate []
  (set app.renderers custom)
  (do-test))"}]
                             :mutations [{:op :set
                                          :path ["app" "renderers"]
                                          :line 8 :column 1
                                          :form "(set app.renderers custom)"
                                          :enclosing-fn "test-bad-mutate"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for mutation without restoration")
  (assert (= (type result) :table) "diagnostics should be a table")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should have correct constraint-id")
  (assert (= d.family "test-isolation") "diagnostic should have family test-isolation")
  (assert (= d.file ff.path) "diagnostic should include file path")
  (assert d.evidence "diagnostic should include evidence"))

(fn mutation-restoration-flags-test-file-with-package-loaded-mutation []
  "Mutating package.loaded in a test file without restoration should be flagged."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                             :module "tests.test-bad"
                             :definitions [{:kind :fn
                                            :name "test-mutate-package"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 80
                                            :form "(fn test-mutate-package []
  (tset package.loaded :some-module nil))"}]
                             :mutations [{:op :tset
                                          :path ["package" "loaded" "some-module"]
                                          :line 8 :column 1
                                          :form "(tset package.loaded :some-module nil)"
                                          :enclosing-fn "test-mutate-package"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for package.loaded mutation")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should have correct constraint-id"))

(fn mutation-restoration-flags-test-file-with-app-engine-mutation []
  "Mutating app.engine in a test file without restoration should be flagged."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                             :module "tests.test-bad"
                             :definitions [{:kind :fn
                                            :name "test-engine"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 80
                                            :form "(fn test-engine []
  (set app.engine my-engine))"}]
                             :mutations [{:op :set
                                          :path ["app" "engine"]
                                          :line 8 :column 1
                                          :form "(set app.engine my-engine)"
                                          :enclosing-fn "test-engine"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for app.engine mutation")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should have correct constraint-id"))

(fn mutation-restoration-flags-pcall-without-restore []
  "A test file that uses pcall to mutate a sensitive global but does not
  restore it should be flagged. Mere presence of pcall is not restoration."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                             :module "tests.test-bad"
                             :definitions [{:kind :fn
                                            :name "test-pcall-no-restore"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 120
                                            :form "(fn test-pcall-no-restore []
  (pcall (fn []
    (set app.renderers custom-fn))
  (do-test))"}]
                             :mutations [{:op :set
                                          :path ["app" "renderers"]
                                          :line 8 :column 1
                                          :form "(set app.renderers custom-fn)"
                                          :enclosing-fn "test-pcall-no-restore"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for pcall without restore")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag pcall-without-restore"))

(fn mutation-restoration-flags-repeated-mutation-without-restore []
  "A test file that mutates a sensitive global twice without restoring it
  should be flagged. A second occurrence of the path is not restoration."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                             :module "tests.test-bad"
                             :definitions [{:kind :fn
                                            :name "test-double-mutate"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 120
                                            :form "(fn test-double-mutate []
  (set app.renderers custom1)
  (do-something)
  (set app.renderers custom2))"}]
                             :mutations [{:op :set
                                          :path ["app" "renderers"]
                                          :line 6 :column 1
                                          :form "(set app.renderers custom1)"
                                          :enclosing-fn "test-double-mutate"}
                                         {:op :set
                                          :path ["app" "renderers"]
                                          :line 8 :column 1
                                          :form "(set app.renderers custom2)"
                                          :enclosing-fn "test-double-mutate"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for repeated mutation without restore")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag repeated-mutation-without-restore"))

(fn mutation-restoration-flags-pcall-double-mutate-no-restore []
  "A test file that uses pcall to wrap two mutations of a sensitive global
  without any cleanup restore should be flagged. Two occurrences inside a
  pcall block are not restoration evidence."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                             :module "tests.test-bad"
                             :definitions [{:kind :fn
                                            :name "test-pcall-double-mutate"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 150
                                            :form "(fn test-pcall-double-mutate []
  (pcall (fn []
    (set app.renderers custom1)
    (set app.renderers custom2))))"}]
                             :mutations [{:op :set
                                          :path ["app" "renderers"]
                                          :line 7 :column 1
                                          :form "(set app.renderers custom1)"
                                          :enclosing-fn "test-pcall-double-mutate"}
                                         {:op :set
                                          :path ["app" "renderers"]
                                          :line 8 :column 1
                                          :form "(set app.renderers custom2)"
                                          :enclosing-fn "test-pcall-double-mutate"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for pcall double-mutate without restore")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag pcall-double-mutate-no-restore"))

(fn mutation-restoration-flags-pcall-triple-mutate-no-restore []
  "A test file that uses pcall to wrap three mutations of a sensitive global
  without any cleanup restore should still be flagged. Three occurrences
  inside a pcall are not restoration evidence."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                             :module "tests.test-bad"
                             :definitions [{:kind :fn
                                            :name "test-pcall-triple-mutate"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 150
                                            :form "(fn test-pcall-triple-mutate []
  (pcall (fn []
    (set app.renderers custom1)
    (set app.renderers custom2)
    (set app.renderers custom3))))"}]
                             :mutations [{:op :set
                                          :path ["app" "renderers"]
                                          :line 7 :column 1
                                          :form "(set app.renderers custom1)"
                                          :enclosing-fn "test-pcall-triple-mutate"}
                                         {:op :set
                                          :path ["app" "renderers"]
                                          :line 8 :column 1
                                          :form "(set app.renderers custom2)"
                                          :enclosing-fn "test-pcall-triple-mutate"}
                                         {:op :set
                                          :path ["app" "renderers"]
                                          :line 9 :column 1
                                          :form "(set app.renderers custom3)"
                                          :enclosing-fn "test-pcall-triple-mutate"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for pcall triple-mutate without restore")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag pcall-triple-mutate-no-restore"))

(fn mutation-restoration-flags-snapshot-two-mutations-without-restore []
  "A function that snapshots a sensitive global then mutates it twice
  without a restore write back to the snapshot var should be flagged.
  Snapshot evidence + 2 mutations does not imply restoration."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  ;; form: (fn test-fn [] (let [orig app.renderers] (set app.renderers c1) (set app.renderers c2)))
  ;; Both sets are mutations to app.renderers, neither restores to orig.
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                             :module "tests.test-bad"
                             :definitions [{:kind :fn
                                            :name "test-snapshot-two-mutates"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 150
                                            :form "(fn test-snapshot-two-mutates []
  (let [orig app.renderers]
    (set app.renderers custom1)
    (set app.renderers custom2)))"}]
                             :mutations [{:op :set
                                          :path ["app" "renderers"]
                                          :line 7 :column 1
                                          :form "(set app.renderers custom1)"
                                          :enclosing-fn "test-snapshot-two-mutates"}
                                         {:op :set
                                          :path ["app" "renderers"]
                                          :line 8 :column 1
                                          :form "(set app.renderers custom2)"
                                          :enclosing-fn "test-snapshot-two-mutates"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for snapshot+two-mutations without restore")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag snapshot+two-mutations-without-restore"))

(fn mutation-restoration-flags-snapshot-pcall-two-mutations-without-restore []
  "A function that snapshots a sensitive global then wraps two mutations
  in pcall without restoring back to the snapshot var should be flagged.
  pcall + snapshot + 2 mutations does not imply restoration."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  ;; form: (fn test-fn [] (let [orig app.renderers] (pcall (fn [] (set app.renderers c1) (set app.renderers c2)))))
  ;; Both sets are mutations, neither restores to orig.
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                             :module "tests.test-bad"
                             :definitions [{:kind :fn
                                            :name "test-pcall-snapshot-two-mutates"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 150
                                            :form "(fn test-pcall-snapshot-two-mutates []
  (let [orig app.renderers]
    (pcall (fn []
      (set app.renderers custom1)
      (set app.renderers custom2)))))"}]
                             :mutations [{:op :set
                                          :path ["app" "renderers"]
                                          :line 8 :column 1
                                          :form "(set app.renderers custom1)"
                                          :enclosing-fn "test-pcall-snapshot-two-mutates"}
                                         {:op :set
                                          :path ["app" "renderers"]
                                          :line 9 :column 1
                                          :form "(set app.renderers custom2)"
                                          :enclosing-fn "test-pcall-snapshot-two-mutates"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for snapshot+pcall+two-mutations without restore")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag snapshot+pcall+two-mutations-without-restore"))

(fn mutation-restoration-flags-pre-restore-then-mutate []
  "A function that snapshots, restores BEFORE the mutation, then mutates,
  should be flagged. Order matters: the restore write must occur AFTER the
  mutation, not before. A pre-restore followed by a later mutation leaves
  the global in a mutated state."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  ;; form: (fn test-fn [] (let [orig app.renderers] (set app.renderers orig) (set app.renderers custom)))
  ;; The restore is at line 6 (before mutation at line 7), so the final state is mutated.
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                             :module "tests.test-bad"
                             :definitions [{:kind :fn
                                            :name "test-pre-restore-leak"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 150
                                            :form "(fn test-pre-restore-leak []
  (let [orig app.renderers]
    (set app.renderers orig)
    (do-something)
    (set app.renderers custom)))"}]
                             :mutations [{:op :set
                                          :path ["app" "renderers"]
                                          :line 6 :column 1
                                          :form "(set app.renderers orig)"
                                          :enclosing-fn "test-pre-restore-leak"}
                                         {:op :set
                                          :path ["app" "renderers"]
                                          :line 8 :column 1
                                          :form "(set app.renderers custom)"
                                          :enclosing-fn "test-pre-restore-leak"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for pre-restore then later mutation")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag pre-restore-then-mutate"))

(fn mutation-restoration-flags-pcall-pre-restore-then-mutate []
  "A function that restores BEFORE a pcall that mutates should be flagged.
  The restore must be outside/after the pcall body, not before it."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  ;; form: (fn test-fn [] (let [orig app.renderers] (set app.renderers orig) (pcall (fn [] (set app.renderers custom)))))
  ;; Restore at line 6, pcall mutation at line 8 — final state is mutated.
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                             :module "tests.test-bad"
                             :definitions [{:kind :fn
                                            :name "test-pcall-pre-restore-leak"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 150
                                            :form "(fn test-pcall-pre-restore-leak []
  (let [orig app.renderers]
    (set app.renderers orig)
    (pcall (fn []
      (set app.renderers custom)))))"}]
                             :mutations [{:op :set
                                          :path ["app" "renderers"]
                                          :line 6 :column 1
                                          :form "(set app.renderers orig)"
                                          :enclosing-fn "test-pcall-pre-restore-leak"}
                                         {:op :set
                                          :path ["app" "renderers"]
                                          :line 8 :column 1
                                          :form "(set app.renderers custom)"
                                          :enclosing-fn "test-pcall-pre-restore-leak"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for pcall pre-restore then mutate")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag pcall-pre-restore-then-mutate"))

(fn mutation-restoration-flags-pcall-restore-inside-pcall-body []
  "A function that uses pcall to mutate a sensitive global and places the
  restore write INSIDE the pcall body should be flagged. A restore inside
  the pcall-protected mutation body is not cleanup — it runs only when
  the protected call succeeds, not when it fails."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  ;; form: (fn test-fn [] (let [orig app.renderers] (pcall (fn [] (set app.renderers custom) (set app.renderers orig)))))
  ;; The restore (set app.renderers orig) is inside the pcall body — NOT cleanup.
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                             :module "tests.test-bad"
                             :definitions [{:kind :fn
                                            :name "test-pcall-restore-inside-body"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 150
                                            :form "(fn test-pcall-restore-inside-body []
  (let [orig app.renderers]
    (pcall (fn []
      (set app.renderers custom)
      (set app.renderers orig)))))"}]
                             :mutations [{:op :set
                                          :path ["app" "renderers"]
                                          :line 7 :column 1
                                          :form "(set app.renderers custom)"
                                          :enclosing-fn "test-pcall-restore-inside-body"}
                                         {:op :set
                                          :path ["app" "renderers"]
                                          :line 8 :column 1
                                          :form "(set app.renderers orig)"
                                          :enclosing-fn "test-pcall-restore-inside-body"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for restore inside pcall body")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag restore-inside-pcall-body"))

(fn mutation-restoration-flags-two-pcalls-second-mutates-in-body-restore []
  "A function with two pcalls both using (fn [] ...) — the first is unrelated
   and the second mutates app.renderers then restores inside its own pcall body.
   The restore inside the second pcall body is NOT cleanup, because it runs
   only when the protected call succeeds. The first unrelated pcall should not
   cause the rule to miss the violation in the second pcall."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (local rule (find-rule-by-id rules "lifecycle.global-mutation-restoration"))
  (assert rule "rule should be in rules list")
  ;; form:
  ;; (fn test-two-pcalls-in-body-restore []
  ;;   (let [orig app.renderers]
  ;;     (pcall (fn [] (do-unrelated)))               ; first pcall — unrelated
  ;;     (pcall (fn []                                 ; second pcall — mutates + in-body restore
  ;;       (set app.renderers custom)
  ;;       (set app.renderers orig)))))
  ;; The restore is inside the second pcall body — NOT cleanup — should be flagged.
  (local ff (make-file-fact {:path "/tests/test-bad.fnl"
                             :module "tests.test-bad"
                             :definitions [{:kind :fn
                                            :name "test-two-pcalls-in-body-restore"
                                            :top-level? true
                                            :line 5 :column 1
                                            :length 250
                                            :form "(fn test-two-pcalls-in-body-restore []
  (let [orig app.renderers]
    (pcall (fn [] (do-unrelated)))
    (pcall (fn []
      (set app.renderers custom)
      (set app.renderers orig)))))"}]
                             :mutations [{:op :set
                                          :path ["app" "renderers"]
                                          :line 9 :column 1
                                          :form "(set app.renderers custom)"
                                          :enclosing-fn "test-two-pcalls-in-body-restore"}
                                         {:op :set
                                          :path ["app" "renderers"]
                                          :line 10 :column 1
                                          :form "(set app.renderers orig)"
                                          :enclosing-fn "test-two-pcalls-in-body-restore"}]}))
  (local result (rule.run (make-ctx [ff])))
  (assert result "should produce diagnostics for two pcalls with in-body restore in second")
  (assert (> (length result) 0) "should have at least one diagnostic")
  (local d (. result 1))
  (assert (= d.constraint-id "lifecycle.global-mutation-restoration")
          "diagnostic should flag two-pcalls-second-in-body-restore"))


;; ======================================================================
;; Rules list structure tests
;; ======================================================================

(fn lifecycle-rules-returns-table-with-two-rules []
  "Lifecycle.rules() should return a table with exactly 2 rules."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (assert (= (type rules) :table) "rules should be a table")
  (assert (= (length rules) 2) (.. "expected 2 rules, got " (length rules))))

(fn lifecycle-rules-have-required-structure []
  "Each lifecycle rule should have :id, :family, :targets, :kind, :run, and :fn."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local rules (Lifecycle.rules))
  (each [_ rule (ipairs rules)]
    (assert (= (type rule.id) :string) (.. "rule should have string :id, got " (tostring rule.id)))
    (assert (= rule.family "lifecycle") "rule should have family lifecycle")
    (assert (= (type rule.targets) :table) "rule should have :targets table")
    (assert (= rule.kind :static) (.. "rule should be kind static, got " (tostring rule.kind)))
    (assert (= (type rule.run) :function) (.. "rule should have :run function for id " (tostring rule.id)))
    (assert (= (type rule.fn) :function) (.. "rule should have :fn function for id " (tostring rule.id)))
    (assert (= rule.fn rule.run) (.. ":fn should alias :run for id " (tostring rule.id)))))

(fn test-isolation-rules-returns-table-with-one-rule []
  "TestIsolation.rules() should return a table with exactly 1 rule."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (assert (= (type rules) :table) "rules should be a table")
  (assert (= (length rules) 1) (.. "expected 1 rule, got " (length rules))))

(fn test-isolation-rules-have-required-structure []
  "Each test-isolation rule should have :id, :family, :targets, :kind, :run, and :fn."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local rules (TestIsolation.rules))
  (each [_ rule (ipairs rules)]
    (assert (= (type rule.id) :string) (.. "rule should have string :id, got " (tostring rule.id)))
    (assert (= rule.family "test-isolation") "rule should have family test-isolation")
    (assert (= (type rule.targets) :table) "rule should have :targets table")
    (assert (= rule.kind :static) (.. "rule should be kind static, got " (tostring rule.kind)))
    (assert (= (type rule.run) :function) (.. "rule should have :run function for id " (tostring rule.id)))
    (assert (= (type rule.fn) :function) (.. "rule should have :fn function for id " (tostring rule.id)))
    (assert (= rule.fn rule.run) (.. ":fn should alias :run for id " (tostring rule.id)))))


;; ======================================================================
;; Runner integration tests
;; ======================================================================

(fn lifecycle-runner-executable []
  "Lifecycle.rules() entries must be executable by constraints.runner.run."
  (local Lifecycle (require :constraints.rules.lifecycle))
  (local ConstraintRunner (require :constraints.runner))
  (local rules (Lifecycle.rules))
  (local target {:kind :repo :name :test
                 :facts (make-fact-db [(make-file-fact {:path "/test/clean.fnl"
                                                        :module "test-clean"
                                                        :accesses []
                                                        :calls []
                                                        :definitions []})])
                 :files []})
  (local result (ConstraintRunner.run {:rules rules :target target
                                        :baseline-data false}))
  (assert result "runner should return a result table")
  (assert (= (type result.status) :string) "result should have a status")
  (assert (= result.status :pass) (.. "expected :pass status, got " result.status))
  (assert (= (length result.diagnostics) 0)
          (.. "expected 0 diagnostics, got " (length result.diagnostics))))

(fn test-isolation-runner-executable []
  "TestIsolation.rules() entries must be executable by constraints.runner.run."
  (local TestIsolation (require :constraints.rules.test-isolation))
  (local ConstraintRunner (require :constraints.runner))
  (local rules (TestIsolation.rules))
  (local target {:kind :repo :name :test
                 :facts (make-fact-db [(make-file-fact {:path "/test/clean.fnl"
                                                        :module "test-clean"
                                                        :accesses []
                                                        :mutations []})])
                 :files []})
  (local result (ConstraintRunner.run {:rules rules :target target
                                        :baseline-data false}))
  (assert result "runner should return a result table")
  (assert (= (type result.status) :string) "result should have a status")
  (assert (= result.status :pass) (.. "expected :pass status, got " result.status))
  (assert (= (length result.diagnostics) 0)
          (.. "expected 0 diagnostics, got " (length result.diagnostics))))


;; ======================================================================
;; Register all tests
;; ======================================================================

;; lifecycle.event-registration-cleanup
(table.insert tests {:name "registration-cleanup allows file without registrations"
                     :fn registration-cleanup-allows-file-without-registrations})
(table.insert tests {:name "registration-cleanup allows file with registration and cleanup"
                     :fn registration-cleanup-allows-file-with-registration-and-cleanup})
(table.insert tests {:name "registration-cleanup allows register with unregister"
                     :fn registration-cleanup-allows-register-with-unregister})
(table.insert tests {:name "registration-cleanup allows connect with drop cleanup"
                     :fn registration-cleanup-allows-connect-with-drop-cleanup})
(table.insert tests {:name "registration-cleanup flags file with connect no cleanup"
                     :fn registration-cleanup-flags-file-with-connect-no-cleanup})
(table.insert tests {:name "registration-cleanup flags app.engine.events.updated:connect"
                     :fn registration-cleanup-flags-file-with-app-engine-events-updated-connect})
(table.insert tests {:name "registration-cleanup flags register without unregister"
                     :fn registration-cleanup-flags-file-with-register-no-unregister})
(table.insert tests {:name "registration-cleanup allows connect with clear cleanup"
                     :fn registration-cleanup-allows-connect-with-clear-cleanup})
(table.insert tests {:name "registration-cleanup allows function named cleanup"
                     :fn registration-cleanup-allows-function-named-cleanup})
(table.insert tests {:name "registration-cleanup allows function named teardown"
                     :fn registration-cleanup-allows-function-named-teardown})
(table.insert tests {:name "registration-cleanup allows function named shutdown"
                     :fn registration-cleanup-allows-function-named-shutdown})
(table.insert tests {:name "registration-cleanup allows connect with clear method"
                     :fn registration-cleanup-allows-connect-with-clear-method})
(table.insert tests {:name "registration-cleanup allows connect with unregister method"
                     :fn registration-cleanup-allows-connect-with-unregister-method})
(table.insert tests {:name "registration-cleanup allows function named unload"
                     :fn registration-cleanup-allows-function-named-unload})
(table.insert tests {:name "registration-cleanup allows disconnect-dash helper call"
                     :fn registration-cleanup-allows-disconnect-dash-helper-call})
(table.insert tests {:name "registration-cleanup allows disconnect-dash function name"
                     :fn registration-cleanup-allows-disconnect-dash-function-name})
(table.insert tests {:name "registration-cleanup allows loop cleanup over handler records"
                     :fn registration-cleanup-allows-loop-cleanup-over-handler-records})
(table.insert tests {:name "registration-cleanup allows loop cleanup in drop function"
                     :fn registration-cleanup-allows-loop-cleanup-in-drop-function})
(table.insert tests {:name "registration-cleanup still flags no cleanup at all"
                     :fn registration-cleanup-still-flags-no-cleanup-at-all})
(table.insert tests {:name "registration-cleanup still flags connect without any cleanup"
                     :fn registration-cleanup-still-flags-connect-without-any-cleanup})
(table.insert tests {:name "registration-cleanup allows loop with disconnect-dash helper"
                     :fn registration-cleanup-allows-loop-with-disconnect-dash-helper})
(table.insert tests {:name "registration-cleanup flags loop but no cleanup calls"
                     :fn registration-cleanup-flags-file-with-loop-but-no-cleanup-calls})
(table.insert tests {:name "registration-cleanup flags partial cleanup with fake loop text"
                     :fn registration-cleanup-flags-partial-cleanup-with-fake-loop-text})
(table.insert tests {:name "registration-cleanup flags file with partial cleanup"
                     :fn registration-cleanup-flags-file-with-partial-cleanup})

;; lifecycle.required-runtime-fails-loudly
(table.insert tests {:name "required-runtime allows file with no sensitive accesses"
                     :fn required-runtime-allows-file-with-no-sensitive-accesses})
(table.insert tests {:name "required-runtime allows file with assert and sensitive access"
                     :fn required-runtime-allows-file-with-assert-and-sensitive-access})
(table.insert tests {:name "required-runtime allows file with error and sensitive access"
                     :fn required-runtime-allows-file-with-error-and-sensitive-access})
(table.insert tests {:name "required-runtime flags file with or synthesizing sensitive global"
                     :fn required-runtime-flags-file-with-or-synthesizing-sensitive-global})
(table.insert tests {:name "required-runtime allows when conditional execution"
                     :fn required-runtime-allows-when-conditional-execution})
(table.insert tests {:name "required-runtime flags if synthesizing engine"
                     :fn required-runtime-flags-if-synthesizing-engine})
(table.insert tests {:name "required-runtime flags if synthesizing renderers"
                     :fn required-runtime-flags-if-synthesizing-renderers})
(table.insert tests {:name "required-runtime allows if benign branch"
                     :fn required-runtime-allows-if-benign-branch})
(table.insert tests {:name "required-runtime allows and guard pattern"
                     :fn required-runtime-allows-and-guard-pattern})
(table.insert tests {:name "required-runtime allows or with and guard"
                     :fn required-runtime-allows-or-with-and-guard})
(table.insert tests {:name "required-runtime allows subfield default"
                     :fn required-runtime-allows-subfield-default})
(table.insert tests {:name "required-runtime allows renderers subfield default"
                     :fn required-runtime-allows-renderers-subfield-default})
(table.insert tests {:name "required-runtime flags activity-registry synthesis"
                     :fn required-runtime-flags-activity-registry-synthesis})
(table.insert tests {:name "required-runtime flags physics-containment-config synthesis"
                     :fn required-runtime-flags-physics-containment-config-synthesis})
(table.insert tests {:name "required-runtime allows hyphenated subfield default"
                     :fn required-runtime-allows-hyphenated-subfield-default})
(table.insert tests {:name "required-runtime flags set+or synthesizing global"
                     :fn required-runtime-flags-file-with-set-or-synthesizing-global})
(table.insert tests {:name "required-runtime flags or synthesizing engine"
                     :fn required-runtime-flags-file-with-or-synthesizing-engine})
(table.insert tests {:name "required-runtime only checks per-function, not file-level"
                     :fn required-runtime-allows-file-with-assert-in-outer-fn})

;; lifecycle.global-mutation-restoration (test-isolation)
(table.insert tests {:name "mutation-restoration allows non-test file"
                     :fn mutation-restoration-allows-non-test-file})
(table.insert tests {:name "mutation-restoration allows test file with restoration"
                     :fn mutation-restoration-allows-test-file-with-restoration})
(table.insert tests {:name "mutation-restoration allows with-restored-app-fields"
                     :fn mutation-restoration-allows-with-restored-app-fields})
(table.insert tests {:name "mutation-restoration allows pcall cleanup restore"
                     :fn mutation-restoration-allows-pcall-cleanup-restore})
(table.insert tests {:name "mutation-restoration flags test file without restoration"
                     :fn mutation-restoration-flags-test-file-without-restoration})
(table.insert tests {:name "mutation-restoration flags package.loaded mutation"
                     :fn mutation-restoration-flags-test-file-with-package-loaded-mutation})
(table.insert tests {:name "mutation-restoration flags app.engine mutation"
                     :fn mutation-restoration-flags-test-file-with-app-engine-mutation})
(table.insert tests {:name "mutation-restoration flags pcall without restore"
                     :fn mutation-restoration-flags-pcall-without-restore})
(table.insert tests {:name "mutation-restoration flags repeated mutation without restore"
                     :fn mutation-restoration-flags-repeated-mutation-without-restore})
(table.insert tests {:name "mutation-restoration flags pcall double-mutate without restore"
                     :fn mutation-restoration-flags-pcall-double-mutate-no-restore})
(table.insert tests {:name "mutation-restoration flags pcall triple-mutate without restore"
                     :fn mutation-restoration-flags-pcall-triple-mutate-no-restore})
(table.insert tests {:name "mutation-restoration flags snapshot+two-mutations without restore"
                     :fn mutation-restoration-flags-snapshot-two-mutations-without-restore})
(table.insert tests {:name "mutation-restoration flags snapshot+pcall+two-mutations without restore"
                     :fn mutation-restoration-flags-snapshot-pcall-two-mutations-without-restore})
(table.insert tests {:name "mutation-restoration flags pre-restore then mutate"
                     :fn mutation-restoration-flags-pre-restore-then-mutate})
(table.insert tests {:name "mutation-restoration flags pcall pre-restore then mutate"
                     :fn mutation-restoration-flags-pcall-pre-restore-then-mutate})
(table.insert tests {:name "mutation-restoration flags pcall restore inside pcall body"
                     :fn mutation-restoration-flags-pcall-restore-inside-pcall-body})
(table.insert tests {:name "mutation-restoration flags two pcalls second in-body restore"
                     :fn mutation-restoration-flags-two-pcalls-second-mutates-in-body-restore})

;; Structure tests
(table.insert tests {:name "lifecycle rules returns table with two rules"
                     :fn lifecycle-rules-returns-table-with-two-rules})
(table.insert tests {:name "lifecycle rules have required structure"
                     :fn lifecycle-rules-have-required-structure})
(table.insert tests {:name "test-isolation rules returns table with one rule"
                     :fn test-isolation-rules-returns-table-with-one-rule})
(table.insert tests {:name "test-isolation rules have required structure"
                     :fn test-isolation-rules-have-required-structure})

;; Runner integration
(table.insert tests {:name "lifecycle rules executable by runner"
                     :fn lifecycle-runner-executable})
(table.insert tests {:name "test-isolation rules executable by runner"
                     :fn test-isolation-runner-executable})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-rules-lifecycle"
                        :tests tests})))

{:name "constraints-rules-lifecycle"
 :tests tests
 :main main}
