;; Scenario helpers for Fennel constraints.
;; Provides with-test-app for scenario rules that need a real app environment.

(local M {})

(fn M.with-test-app [f]
  "Execute f inside a real test app environment, ensuring cleanup.
  Returns the result of f on success, rethrows failures after cleanup.
  When called inside an existing test runner environment, saves and restores
  the prior global app state so the outer runner teardown is not broken."
  (local TestRunner (require :tests/runner))
  ;; Save the prior global app reference (may be nil when there is no outer runner)
  (local prior-app _G.app)
  ;; Setup the test environment (initializes global app, engine, textures, etc.)
  (TestRunner.setup-test-env false)
  (local (ok result) (xpcall f
                                (fn [err]
                                  ;; Capture traceback before cleanup
                                  (local tb (if _G.debug
                                                (_G.debug.traceback err 3)
                                                (tostring err)))
                                  tb)))
  ;; Always shut down the inner test environment
  (TestRunner.shutdown-test-env)
  ;; Restore the prior global app so any outer runner teardown works correctly
  (global app prior-app)
  ;; Rethrow or return
  (if ok
      result
      (error (.. "scenario failed: " (tostring result)) 2)))

M
