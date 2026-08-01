;; Rule registry for Fennel constraints.
;; Aggregates all rule modules in deterministic order and exposes
;; a combined rule list for the runner to iterate over.

(local SceneSandbox (require :constraints.rules.scene-sandbox))
(local Lifecycle (require :constraints.rules.lifecycle))
(local TestIsolation (require :constraints.rules.test-isolation))
(local LayoutRules (require :constraints.rules.layout))
(local Structure (require :constraints.rules.structure))

(local M {})

(fn M.all-rules []
  "Return the complete rule list in deterministic order:
   1. Scene/Sandbox
   2. lifecycle
   3. test isolation
   4. layout/rendering
   5. structure/formatting"
  (let [rules []]
    ;; 1. Scene/Sandbox rules (scene-sandbox family)
    (each [_ r (ipairs (SceneSandbox.rules))]
      (table.insert rules r))
    ;; 2. Lifecycle rules (lifecycle family)
    (each [_ r (ipairs (Lifecycle.rules))]
      (table.insert rules r))
    ;; 3. Test Isolation rules (test-isolation family)
    (each [_ r (ipairs (TestIsolation.rules))]
      (table.insert rules r))
    ;; 4. Layout/Rendering rules (layout-rendering family)
    (each [_ r (ipairs (LayoutRules.rules))]
      (table.insert rules r))
    ;; 5. Structure/Formatting rules (structure-formatting family)
    (each [_ r (ipairs (Structure.rules))]
      (table.insert rules r))
    rules))

M
