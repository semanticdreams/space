;; External Unit MCP Service tests — loader-neutral discovery, handles, inspect, resolve.
;; Run: FENNEL_PATH="..." FENNEL_MACRO_PATH="..." SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tests.test-external-unit-mcp:main

(local tests [])
(local fs (require :fs))
(local fennel (require :fennel))
(local Units (require :units))
(local UnitManager (require :unit-manager))
(local tempfile (require :tempfile))

(local ExternalUnitService (require :llm/external-unit-mcp/service))

(fn with-temp-dir [f]
  (local handle (tempfile.TemporaryDirectory {:prefix "ext-unit-mcp-test-"}))
  (local path handle.path)
  (local (ok result) (pcall f path))
  (handle:drop)
  (if ok
      result
      (error result)))

(fn with-service [dir mgr-populate f]
  (local mgr (UnitManager {}))
  (mgr-populate mgr dir)
  (local service (ExternalUnitService.ExternalUnitService {:app {:unit-manager mgr}}))
  (f mgr service)
  (mgr:clear))

;; ── Helpers ──

(fn write-unit-file [dir name content]
  (local path (fs.join-path dir (.. name ".fnl")))
  (fs.write-file path content)
  path)

(fn write-bubble-unit [dir]
  (write-unit-file dir "bubble-overlay"
    (.. "(fn init [] (set app.__bubble-loaded true) true)\n"
        "(fn drop [] (set app.__bubble-loaded false) true)\n"
        "(fn snapshot [] app.__bubble-loaded)\n"
        "(fn restore [state] (set app.__restored state) true)\n"
        "{:init init :drop drop :snapshot snapshot :restore restore}")))

(fn write-simple-unit [dir name]
  (write-unit-file dir name
    (.. "(fn init [] true)\n"
        "(fn drop [] true)\n"
        "{:init init :drop drop}")))

;; ── Tests ──

(fn test-list-returns-loader-neutral-handles []
  (with-temp-dir
    (fn [dir]
      (local bubble-path (write-bubble-unit dir))
      (write-simple-unit dir "util-module")
      (with-service dir
        (fn [mgr _dir]
          (local fennel-paths (.. dir "/?.fnl;" dir "/?/init.fnl"))
          ;; Register a filesystem-backed user unit (bubble-overlay)
          (local bubble-unit (Units.ModuleUnit
                               {:id "user-bubble-overlay"
                                :module-name "bubble-overlay"
                                :module-paths fennel-paths
                                :source :user
                                :suppress-run-main? true
                                :owned-paths [bubble-path]}))
          (mgr:register bubble-unit)
          ;; Register a builtin/non-filesystem unit
          (local builtin-unit (Units.Unit {:id "builtin-hud"
                                           :source :builtin
                                           :load (fn [_] true)
                                           :unload (fn [_] true)}))
          (mgr:register builtin-unit))
        (fn [mgr service]
          (local results (service:list {}))
          ;; Should return two handles
          (assert (= (length results) 2) (.. "expected 2 handles, got " (length results)))
          ;; Find handles by unit-id since results are sorted by unit-id
          (var bubble-handle nil)
          (var builtin-handle nil)
          (each [_ h (ipairs results)]
            (if (= h.unit-id "user-bubble-overlay") (set bubble-handle h)
                (= h.unit-id "builtin-hud") (set builtin-handle h)))
          (assert bubble-handle "should find bubble-overlay handle")
          (assert builtin-handle "should find builtin-hud handle")
          ;; Both handles have the required shape
          (each [_ handle (ipairs results)]
            (assert handle.unit-id "handle missing unit-id")
            (assert handle.loader "handle missing loader")
            ;; source-handle key must exist, but may be nil for unknown loaders
            (assert (= (type handle.source-handle) (if (= handle.loader "filesystem") "table" "nil"))
                    (.. "handle has incorrect source-handle type for " handle.loader))
            (assert handle.edit-capabilities "handle missing edit-capabilities")
            (assert handle.test-capabilities "handle missing test-capabilities")
            (assert handle.commit-capability "handle missing commit-capability"))
          ;; Filesystem unit
          (assert (= bubble-handle.loader "filesystem")
                  (.. "expected filesystem loader, got " bubble-handle.loader))
          (assert bubble-handle.source-handle.source-id "source-handle missing source-id")
          (assert (= bubble-handle.source-handle.kind "file") "source-handle kind should be file")
          (assert bubble-handle.source-handle.primary "source-handle should be primary")
          (assert (> bubble-handle.source-handle.size 0) "source-handle size should be > 0")
          (assert (= (type bubble-handle.source-handle.hash) "string") "source-handle hash should be string")
          (assert (> (# bubble-handle.source-handle.hash) 0) "source-handle hash should not be empty")
          ;; Unknown unit (builtin has no owned paths)
          (assert (= builtin-handle.loader "unknown")
                  (.. "expected unknown loader, got " builtin-handle.loader))
          (assert (= builtin-handle.source-handle nil) "unknown unit should have nil source-handle")
          ;; Unknown unit has no edit capabilities
          (assert (= (length builtin-handle.edit-capabilities) 0)
                  "unknown unit should have no edit capabilities"))))))

(table.insert tests {:name "external-unit-mcp: list returns loader-neutral handles"
                     :fn test-list-returns-loader-neutral-handles})

(fn test-inspect-reports-source-artifacts-and-lifecycle-exports []
  (with-temp-dir
    (fn [dir]
      (local bubble-path (write-bubble-unit dir))
      (with-service dir
        (fn [mgr _dir]
          (local fennel-paths (.. dir "/?.fnl;" dir "/?/init.fnl"))
          (local bubble-unit (Units.ModuleUnit
                               {:id "user-bubble-overlay"
                                :module-name "bubble-overlay"
                                :module-paths fennel-paths
                                :source :user
                                :suppress-run-main? true
                                :owned-paths [bubble-path]}))
          (mgr:register bubble-unit))
        (fn [mgr service]
          (local result (service:inspect {:unit_id "user-bubble-overlay"}))
          (assert result.unit-id "inspect missing unit-id")
          (assert (= result.unit-id "user-bubble-overlay") "unit-id mismatch")
          (assert (= result.loader "filesystem") "inspect loader mismatch")
          (assert result.source-handle "inspect missing source-handle")
          ;; Lifecycle exports
          (assert result.lifecycle "inspect missing lifecycle")
          (assert (= result.lifecycle.init "init") "lifecycle init should default to 'init'")
          (assert (= result.lifecycle.drop "drop") "lifecycle drop should default to 'drop'")
          (assert (= result.lifecycle.snapshot "snapshot")
                  "lifecycle snapshot should default to 'snapshot'")
          (assert (= result.lifecycle.restore "restore")
                  "lifecycle restore should default to 'restore'")
          ;; Source artifacts
          (assert result.source-artifacts "inspect missing source-artifacts")
          (assert (= (type result.source-artifacts) "table")
                  "source-artifacts should be a table")
          (assert (> (length result.source-artifacts) 0)
                  "source-artifacts should not be empty"))))))

(table.insert tests {:name "external-unit-mcp: inspect reports source artifacts and lifecycle exports"
                     :fn test-inspect-reports-source-artifacts-and-lifecycle-exports})

(fn test-resolve-ranks-vague-description-candidates []
  (with-temp-dir
    (fn [dir]
      (local bubble-path (write-bubble-unit dir))
      (write-simple-unit dir "util-module")
      (with-service dir
        (fn [mgr _dir]
          (local fennel-paths (.. dir "/?.fnl;" dir "/?/init.fnl"))
          (local bubble-unit (Units.ModuleUnit
                               {:id "user-bubble-overlay"
                                :module-name "bubble-overlay"
                                :module-paths fennel-paths
                                :source :user
                                :suppress-run-main? true
                                :owned-paths [bubble-path]}))
          (mgr:register bubble-unit)
          (local util-unit (Units.ModuleUnit
                              {:id "user-util-module"
                               :module-name "util-module"
                               :module-paths fennel-paths
                               :source :user
                               :suppress-run-main? true
                               :owned-paths [(fs.join-path dir "util-module.fnl")]}))
          (mgr:register util-unit))
        (fn [_mgr service]
          ;; Resolve with vague description matching bubble unit
          (local result (service:resolve {:description "bubble overlay unit"}))
          (assert result.candidates "resolve missing candidates")
          (assert (= (type result.candidates) "table") "candidates should be a table")
          (assert (> (length result.candidates) 0)
                  "should return at least one candidate for matching description")
          ;; The top candidate should be bubble-overlay
          (local top (. result.candidates 1))
          (assert top.unit-id "candidate missing unit-id")
          (assert (= top.unit-id "user-bubble-overlay")
                  (.. "top candidate should be bubble-overlay, got " top.unit-id))
          (assert top.confidence "candidate missing confidence")
          (assert (>= top.confidence 0) "confidence should be non-negative")
          (assert (<= top.confidence 1) "confidence should be <= 1")
          (assert top.evidence "candidate missing evidence")
          (assert (= (type top.evidence) "string") "evidence should be a string")
          ;; Verify confidence of bubble is higher than util
          (when (> (length result.candidates) 1)
            (local second (. result.candidates 2))
            (assert (>= top.confidence second.confidence)
                    "bubble overlay should have higher confidence than util")))))))

(table.insert tests {:name "external-unit-mcp: resolve ranks vague description candidates"
                     :fn test-resolve-ranks-vague-description-candidates})

(fn test-unit-handle-produces-loader-neutral-shape []
  (with-temp-dir
    (fn [dir]
      (local bubble-path (write-bubble-unit dir))
      (with-service dir
        (fn [mgr _dir]
          (local fennel-paths (.. dir "/?.fnl;" dir "/?/init.fnl"))
          (local bubble-unit (Units.ModuleUnit
                               {:id "user-bubble-overlay"
                                :module-name "bubble-overlay"
                                :module-paths fennel-paths
                                :source :user
                                :suppress-run-main? true
                                :owned-paths [bubble-path]}))
          (mgr:register bubble-unit)
          ;; Also register a unit with missing owned paths (unknown loader)
          (local orphan-unit (Units.Unit {:id "orphan"
                                           :source :user
                                           :load (fn [_] true)
                                           :unload (fn [_] true)}))
          (mgr:register orphan-unit))
        (fn [mgr service]
          (local user-unit (mgr:get "user-bubble-overlay"))
          (local orphan-unit (mgr:get "orphan"))
          ;; Filesystem handle
          (local handle (service:unit-handle user-unit))
          (assert (= handle.loader "filesystem") "filesystem unit should have filesystem loader")
          (assert handle.source-handle "filesystem unit should have source-handle")
          (assert (> (length handle.edit-capabilities) 0)
                  "filesystem unit should have edit capabilities")
          ;; Orphan handle (user source but no owned paths => unknown loader)
          (local orphan-handle (service:unit-handle orphan-unit))
          (assert (= orphan-handle.loader "unknown")
                  (.. "orphan unit should have unknown loader, got " orphan-handle.loader))
          (assert (= orphan-handle.source-handle nil) "orphan unit should have nil source-handle"))))))

(table.insert tests {:name "external-unit-mcp: unit-handle produces loader-neutral shape"
                     :fn test-unit-handle-produces-loader-neutral-shape})

(fn test-service-asserts-missing-unit-manager []
  (local (ok err) (pcall #(ExternalUnitService.ExternalUnitService {:app {}})))
  (assert (not ok) "should reject missing unit-manager")
  (assert (string.find err "unit-manager" 1 true)
          "error should mention unit-manager"))

(table.insert tests {:name "external-unit-mcp: asserts missing unit-manager"
                     :fn test-service-asserts-missing-unit-manager})

(fn test-list-returns-deterministic-ordering []
  (with-temp-dir
    (fn [dir]
      (local z-path (write-unit-file dir "z-unit"
                     (.. "(fn init [] true)\n(fn drop [] true)\n{:init init :drop drop}")))
      (local a-path (write-unit-file dir "a-unit"
                     (.. "(fn init [] true)\n(fn drop [] true)\n{:init init :drop drop}")))
      (with-service dir
        (fn [mgr _dir]
          (local fennel-paths (.. dir "/?.fnl;" dir "/?/init.fnl"))
          (mgr:register (Units.ModuleUnit
                          {:id "user-a-unit"
                           :module-name "a-unit"
                           :module-paths fennel-paths
                           :source :user
                           :suppress-run-main? true
                           :owned-paths [a-path]}))
          (mgr:register (Units.ModuleUnit
                          {:id "user-z-unit"
                           :module-name "z-unit"
                           :module-paths fennel-paths
                           :source :user
                           :suppress-run-main? true
                           :owned-paths [z-path]})))
        (fn [_mgr service]
          (local results (service:list {}))
          (assert (= (length results) 2))
          ;; Deterministic ordering: by unit-id for test stability
          (assert (= (. results 1 :unit-id) "user-a-unit") "should be sorted by unit-id")
          (assert (= (. results 2 :unit-id) "user-z-unit") "should be sorted by unit-id"))))))

(table.insert tests {:name "external-unit-mcp: list returns deterministic ordering"
                     :fn test-list-returns-deterministic-ordering})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "external-unit-mcp"
                       :tests tests})))

{:name "external-unit-mcp"
 :tests tests
 :main main}
