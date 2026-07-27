;; Scenario helpers for experimental Fennel constraints.
;; Provides with-test-app for scenario rules that need a real app environment.

(local M {})

(fn M.with-test-app [f]
  "Execute f inside a real test app environment, ensuring cleanup.
  Returns the result of f on success, rethrows failures after cleanup."
  (local TestRunner (require :tests/runner))
  ;; Setup the test environment (initializes global app, engine, textures, etc.)
  (TestRunner.setup-test-env false)
  (local (ok result) (xpcall f
                               (fn [err]
                                 ;; Capture traceback before cleanup
                                 (local tb (if _G.debug
                                               (_G.debug.traceback err 3)
                                               (tostring err)))
                                 tb)))
  ;; Always shut down the test environment
  (TestRunner.shutdown-test-env)
  ;; Rethrow or return
  (if ok
      result
      (error (.. "scenario failed: " (tostring result)) 2)))

M
