;; Minimal Fennel fixture for constraint target tests.
;; Contains just enough structure to exercise the pipeline
;; without triggering production rule violations.

(local M {})

(fn M.hello []
  "return a greeting"
  "hello from constraint fixture")

(local x 1)
(tset M :x x)

M
