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

(fn with-service* [dir mgr-populate service-opts f]
  (local mgr (UnitManager {}))
  (mgr-populate mgr dir)
  (local full-opts {:app {:unit-manager mgr}})
  (each [k v (pairs (or service-opts {}))]
    (tset full-opts k v))
  (local service (ExternalUnitService.ExternalUnitService full-opts))
  (f mgr service)
  (mgr:clear))

(fn with-service [dir mgr-populate f]
  (with-service* dir mgr-populate {} f))

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
          (assert (= (string.sub bubble-handle.source-handle.hash 1 7) "sha256:")
                  "source-handle hash should be sha256: prefixed")
          (assert (> (# bubble-handle.source-handle.hash) 7) "source-handle hash should contain digest")
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
          ;; Flat filesystem handle: should have read/write/delete but NOT create
          (local handle (service:unit-handle user-unit))
          (assert (= handle.loader "filesystem") "filesystem unit should have filesystem loader")
          (assert handle.source-handle "filesystem unit should have source-handle")
          (assert (> (length handle.edit-capabilities) 0)
                  "flat filesystem unit should have edit capabilities")
          ;; Flat unit must not advertise create
          (var has-create false)
          (each [_ cap (ipairs handle.edit-capabilities)]
            (when (= cap "create")
              (set has-create true)))
          (assert (not has-create) "flat unit should not advertise create capability")
          ;; Flat unit must have read and write
          (var has-read false)
          (var has-write false)
          (each [_ cap (ipairs handle.edit-capabilities)]
            (when (= cap "read") (set has-read true))
            (when (= cap "write") (set has-write true)))
          (assert has-read "flat unit should have read capability")
          (assert has-write "flat unit should have write capability")
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

(fn test-resolve-rejects-negative-limit []
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
        (fn [_mgr service]
          (local (ok err) (pcall #(service:resolve {:description "unit" :limit -1})))
          (assert (not ok) "should reject negative limit")
          (assert (string.find err "limit" 1 true)
                  "error should mention limit"))))))

(table.insert tests {:name "external-unit-mcp: resolve rejects negative limit"
                     :fn test-resolve-rejects-negative-limit})

(fn test-resolve-rejects-non-integer-limit []
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
        (fn [_mgr service]
          (local (ok err) (pcall #(service:resolve {:description "unit" :limit 1.5})))
          (assert (not ok) "should reject non-integer limit")
          (assert (string.find err "integer" 1 true)
                  "error should mention integer"))))))

(table.insert tests {:name "external-unit-mcp: resolve rejects non-integer limit"
                     :fn test-resolve-rejects-non-integer-limit})

(fn test-resolve-accepts-nil-limit []
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
        (fn [_mgr service]
          ;; nil limit should default to 20 — this must complete without error
          (local result (service:resolve {:description "unit"}))
          (assert result.candidates "nil limit should default and return candidates"))))))

(table.insert tests {:name "external-unit-mcp: resolve accepts nil limit (defaults to 20)"
                     :fn test-resolve-accepts-nil-limit})

(fn test-source-artifacts-have-sha256-prefix []
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
        (fn [_mgr service]
          (local result (service:inspect {:unit_id "user-bubble-overlay"}))
          ;; Source handle hash must have sha256: prefix
          (assert (and result.source-handle result.source-handle.hash)
                  "source-handle should have a hash")
          (assert (= (string.sub result.source-handle.hash 1 7) "sha256:")
                  "source-handle hash must be sha256: prefixed")
          ;; Source artifacts must have sha256: prefix
          (each [_ art (ipairs result.source-artifacts)]
            (assert art.hash "artifact missing hash")
            (assert (= (string.sub art.hash 1 7) "sha256:")
                    (.. "artifact " art.source-id " hash must be sha256: prefixed, got "
                        (string.sub (or art.hash "") 1 20)))))))))

(table.insert tests {:name "external-unit-mcp: source artifacts have sha256: prefix"
                     :fn test-source-artifacts-have-sha256-prefix})

;; ── Task 2: Source Read, Patch, Create, and Reload ──

(fn test-read-source-returns-content-and-hash []
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
        (fn [_mgr service]
          (local result (service:read-source {:unit_id "user-bubble-overlay"
                                               :source_id "bubble-overlay.fnl"}))
          (assert result.unit-id "read-source missing unit_id")
          (assert (= result.unit-id "user-bubble-overlay") "unit_id mismatch")
          (assert result.source-id "read-source missing source_id")
          (assert (= result.source-id "bubble-overlay.fnl") "source_id mismatch")
          (assert result.content "read-source missing content")
          (assert (= (type result.content) "string") "content should be a string")
          (assert (> (# result.content) 0) "content should not be empty")
          (assert result.hash "read-source missing hash")
          (assert (= (string.sub result.hash 1 7) "sha256:")
                  "hash should be sha256: prefixed")
          (assert (> (# result.hash) 7) "hash should contain digest"))))))

(table.insert tests {:name "external-unit-mcp: read-source returns content and hash"
                     :fn test-read-source-returns-content-and-hash})

(fn test-apply-patch-exact-replacement-reloads-unit []
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
        (fn [_mgr service]
          (local original-content (fs.read-file bubble-path))
          ;; Perform an exact text replacement
          (local old-text "(fn init [] (set app.__bubble-loaded true) true)")
          (local new-text "(fn init [] (set app.__bubble-loaded true) 42)")
          (local result (service:apply-patch
                          {:unit_id "user-bubble-overlay"
                           :source_id "bubble-overlay.fnl"
                           :old old-text
                           :new new-text}))
          (assert result.unit-id "apply-patch missing unit_id")
          (assert result.source-id "apply-patch missing source_id")
          (assert result.reloaded "apply-patch should report reloaded")
          (assert (= result.reloaded true) "reloaded should be true")
          (assert result.hash "apply-patch missing hash")
          (assert (= (string.sub result.hash 1 7) "sha256:") "hash should be sha256: prefixed")
          ;; Verify the file was actually changed
          (local updated-content (fs.read-file bubble-path))
          (assert (not= updated-content original-content) "file should be changed")
          (assert (string.find updated-content "42" 1 true)
                  "file should contain the new text"))))))

(table.insert tests {:name "external-unit-mcp: apply-patch exact replacement reloads unit"
                     :fn test-apply-patch-exact-replacement-reloads-unit})

(fn test-apply-patch-rejects-stale-expected-hash []
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
        (fn [_mgr service]
          (local original-content (fs.read-file bubble-path))
          (local (ok err) (pcall #(service:apply-patch
                                    {:unit_id "user-bubble-overlay"
                                     :source_id "bubble-overlay.fnl"
                                     :old "(fn init [] (set app.__bubble-loaded true) true)"
                                     :new "(fn init [] (set app.__bubble-loaded true) 42)"
                                     :expected_hash "sha256:0000000000000000000000000000000000000000000000000000000000000000"})))
          (assert (not ok) "should reject stale expected hash")
          (assert (string.find err "hash" 1 true)
                  "error should mention hash")
          ;; Verify the file was NOT changed
          (local current-content (fs.read-file bubble-path))
          (assert (= current-content original-content) "file should remain unchanged"))))))

(table.insert tests {:name "external-unit-mcp: apply-patch rejects stale expected hash"
                     :fn test-apply-patch-rejects-stale-expected-hash})

(fn test-apply-patch-unified-diff-reloads-unit []
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
        (fn [_mgr service]
          (local original-content (fs.read-file bubble-path))
          ;; Construct a unified diff patch that appends :version 2 to the module table
          (local patch-text
            (.. "*** Begin Patch\n"
                "*** Update File: bubble-overlay.fnl\n"
                "@@ -4,2 +4,2 @@\n"
                " (fn restore [state] (set app.__restored state) true)\n"
                "-{:init init :drop drop :snapshot snapshot :restore restore}\n"
                "+{:init init :drop drop :snapshot snapshot :restore restore :version 2}\n"
                "*** End Patch\n"))
          (local result (service:apply-patch
                          {:unit_id "user-bubble-overlay"
                           :source_id "bubble-overlay.fnl"
                           :patch patch-text}))
          (assert result.unit-id "apply-patch missing unit_id")
          (assert result.source-id "apply-patch missing source_id")
          (assert result.reloaded "apply-patch should report reloaded")
          (assert (= result.reloaded true) "reloaded should be true")
          (assert result.hash "apply-patch missing hash")
          ;; Verify the file was actually changed
          (local updated-content (fs.read-file bubble-path))
          (assert (not= updated-content original-content) "file should be changed")
          (assert (string.find updated-content ":version 2" 1 true)
                  "file should contain :version 2"))))))

(table.insert tests {:name "external-unit-mcp: apply-patch unified diff reloads unit"
                     :fn test-apply-patch-unified-diff-reloads-unit})

(fn test-create-source-creates-directory-unit-artifact-and-reloads []
  (with-temp-dir
    (fn [dir]
      (local unit-dir (fs.join-path dir "dir-unit"))
      (fs.create-dirs unit-dir)
      (local init-path (fs.join-path unit-dir "init.fnl"))
      (fs.write-file init-path
        (.. "(fn init [] true)\n"
            "(fn drop [] true)\n"
            "{:init init :drop drop}"))
      (with-service dir
        (fn [mgr _dir]
          (local fennel-paths (.. unit-dir "/?.fnl;" unit-dir "/?/init.fnl;" dir "/?.fnl;" dir "/?/init.fnl"))
          (local unit (Units.ModuleUnit
                        {:id "user-dir-unit"
                         :module-name "dir-unit"
                         :module-paths fennel-paths
                         :source :user
                         :suppress-run-main? true
                         :owned-paths [unit-dir init-path]}))
          (mgr:register unit))
        (fn [_mgr service]
          (local new-source "(fn helper [] \"hello\")\n{:helper helper}")
          (local result (service:create-source
                          {:unit_id "user-dir-unit"
                           :source_id "helper.fnl"
                           :source new-source}))
          (assert result.unit-id "create-source missing unit_id")
          (assert (= result.unit-id "user-dir-unit") "unit_id mismatch")
          (assert result.source-id "create-source missing source_id")
          (assert (= result.source-id "helper.fnl") "source_id mismatch")
          (assert result.created "create-source should report created")
          (assert result.reloaded "create-source should report reloaded")
          (assert (= result.reloaded true) "reloaded should be true")
          (assert result.hash "create-source missing hash")
          (assert (= (string.sub result.hash 1 7) "sha256:") "hash should be sha256: prefixed")
          ;; Verify the file exists and has correct content
          (local new-path (fs.join-path unit-dir "helper.fnl"))
          (assert (fs.exists new-path) "new file should exist")
          (assert (= (fs.read-file new-path) new-source) "file content should match"))))))

(table.insert tests {:name "external-unit-mcp: create-source creates directory-unit artifact and reloads"
                     :fn test-create-source-creates-directory-unit-artifact-and-reloads})

(fn test-create-source-fails-for-flat-unit []
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
        (fn [_mgr service]
          (local (ok err) (pcall #(service:create-source
                                    {:unit_id "user-bubble-overlay"
                                     :source_id "new-file.fnl"
                                     :source "(fn init [] true)\n(fn drop [] true)\n{:init init :drop drop}"})))
          (assert (not ok) "should reject create for flat unit")
          (assert (string.find (or err "") "create" 1 true)
                  "error should mention create"))))))

(table.insert tests {:name "external-unit-mcp: create-source fails loudly for flat unit without create capability"
                     :fn test-create-source-fails-for-flat-unit})

;; ── Fix round 1: R1-1, R1-2, R1-3 ──

(fn test-directory-unit-has-create-capability []
  (with-temp-dir
    (fn [dir]
      (local unit-dir (fs.join-path dir "dir-unit"))
      (fs.create-dirs unit-dir)
      (local init-path (fs.join-path unit-dir "init.fnl"))
      (fs.write-file init-path
        (.. "(fn init [] true)\n"
            "(fn drop [] true)\n"
            "{:init init :drop drop}"))
      (with-service dir
        (fn [mgr _dir]
          (local fennel-paths (.. unit-dir "/?.fnl;" unit-dir "/?/init.fnl;" dir "/?.fnl;" dir "/?/init.fnl"))
          (local unit (Units.ModuleUnit
                        {:id "user-dir-unit"
                         :module-name "dir-unit"
                         :module-paths fennel-paths
                         :source :user
                         :suppress-run-main? true
                         :owned-paths [unit-dir init-path]}))
          (mgr:register unit))
        (fn [mgr service]
          (local handle (service:unit-handle (mgr:get "user-dir-unit")))
          ;; Directory unit must have create capability
          (var has-create false)
          (each [_ cap (ipairs handle.edit-capabilities)]
            (when (= cap "create")
              (set has-create true)))
          (assert has-create "directory unit should advertise create capability"))))))

(table.insert tests {:name "external-unit-mcp: directory unit has create capability"
                     :fn test-directory-unit-has-create-capability})

(fn test-create-source-rejects-existing-file []
  (with-temp-dir
    (fn [dir]
      (local unit-dir (fs.join-path dir "dir-unit"))
      (fs.create-dirs unit-dir)
      (local init-path (fs.join-path unit-dir "init.fnl"))
      (fs.write-file init-path
        (.. "(fn init [] true)\n"
            "(fn drop [] true)\n"
            "{:init init :drop drop}"))
      ;; Pre-create a file that create-source would try to create
      (local existing-path (fs.join-path unit-dir "existing.fnl"))
      (fs.write-file existing-path "(fn helper [] true)\n{:helper helper}")
      (with-service dir
        (fn [mgr _dir]
          (local fennel-paths (.. unit-dir "/?.fnl;" unit-dir "/?/init.fnl;" dir "/?.fnl;" dir "/?/init.fnl"))
          (local unit (Units.ModuleUnit
                        {:id "user-dir-unit"
                         :module-name "dir-unit"
                         :module-paths fennel-paths
                         :source :user
                         :suppress-run-main? true
                         :owned-paths [unit-dir init-path]}))
          (mgr:register unit))
        (fn [_mgr service]
          (local original-content (fs.read-file existing-path))
          (local (ok err) (pcall #(service:create-source
                                    {:unit_id "user-dir-unit"
                                     :source_id "existing.fnl"
                                     :source "(fn helper [] true)\n{:helper helper}"})))
          (assert (not ok) "should reject create for existing file")
          (assert (string.find (or err "") "already exists" 1 true)
                  "error should mention already exists")
          ;; Verify the existing file was NOT overwritten
          (assert (= (fs.read-file existing-path) original-content)
                  "existing file should remain unchanged"))))))

(table.insert tests {:name "external-unit-mcp: create-source rejects existing file"
                     :fn test-create-source-rejects-existing-file})

(fn test-read-source-rejects-path-escape []
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
        (fn [_mgr service]
          ;; Attempt to read via path with .. segment
          (local (ok err) (pcall #(service:read-source
                                    {:unit_id "user-bubble-overlay"
                                     :source_id "../etc/passwd"})))
          (assert (not ok) "should reject .. path segment")
          (assert (string.find (or err "") ".." 1 true)
                  "error should mention .."))))))

(table.insert tests {:name "external-unit-mcp: read-source rejects path escape via .."
                     :fn test-read-source-rejects-path-escape})

(fn test-create-source-rejects-symlinked-ancestor []
  ;; Create a directory unit, place a symlinked directory inside it pointing
  ;; outside the unit root, then attempt create-source through the symlink.
  ;; This verifies the safe resolver is used for create-source as well.
  (with-temp-dir
    (fn [dir]
      (local unit-dir (fs.join-path dir "dir-unit"))
      (fs.create-dirs unit-dir)
      (local init-path (fs.join-path unit-dir "init.fnl"))
      (fs.write-file init-path
        (.. "(fn init [] true)\n"
            "(fn drop [] true)\n"
            "{:init init :drop drop}"))
      ;; Create a directory outside the unit root
      (local outside-dir (fs.join-path dir "outside"))
      (fs.create-dirs outside-dir)
      ;; Create a symlink inside the unit dir pointing outside
      (local symlink-path (fs.join-path unit-dir "escape-hatch"))
      (local Process (require :process))
      (local symlink-result (Process.run {:args ["ln" "-s" outside-dir symlink-path]
                                         :merge-stderr true}))
      (assert (= symlink-result.exit-code 0)
              (.. "symlink creation failed: " (or symlink-result.stderr symlink-result.stdout)))
      ;; Verify the symlink was created
      (local symlink-stat (fs.stat symlink-path))
      (assert symlink-stat.is-symlink "expected symlink")
      (with-service dir
        (fn [mgr _dir]
          (local fennel-paths (.. unit-dir "/?.fnl;" unit-dir "/?/init.fnl;" dir "/?.fnl;" dir "/?/init.fnl"))
          (local unit (Units.ModuleUnit
                        {:id "user-dir-unit"
                         :module-name "dir-unit"
                         :module-paths fennel-paths
                         :source :user
                         :suppress-run-main? true
                         :owned-paths [unit-dir init-path]}))
          (mgr:register unit))
        (fn [_mgr service]
          ;; Attempt create-source through the symlinked directory
          (local (ok err) (pcall #(service:create-source
                                    {:unit_id "user-dir-unit"
                                     :source_id "escape-hatch/evil.fnl"
                                     :source "(fn init [] true)\n(fn drop [] true)\n{:init init :drop drop}"})))
          (assert (not ok) "should reject create through symlinked ancestor")
          (assert (or (string.find (or err "") "symlink" 1 true)
                      (string.find (or err "") "escape" 1 true))
                  (.. "error should mention symlink or path issue, got: " (or err "")))
          ;; Verify no file was created through the symlink
          (local escaped-path (fs.join-path outside-dir "evil.fnl"))
          (assert (not (fs.exists escaped-path))
                  "file must not be created outside unit root"))))))

(table.insert tests {:name "external-unit-mcp: create-source rejects symlinked ancestor directory"
                     :fn test-create-source-rejects-symlinked-ancestor})

;; ── Task 3: External Unit Test, Log, and Snapshot Operations ──

(fn test-snapshot-returns-unit-state-with-capability-metadata []
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
                                :owned-paths [bubble-path]
                                :snapshot-export "snapshot"}))
          (mgr:register bubble-unit))
        (fn [_mgr service]
          (local result (service:snapshot {:unit_id "user-bubble-overlay"}))
          (assert result.unit-id "snapshot missing unit-id")
          (assert (= result.unit-id "user-bubble-overlay") "unit-id mismatch")
          (assert (= result.supported true) "snapshot should be supported")
          (assert (not= result.state nil) "snapshot state should not be nil for unit with snapshot export")
          ;; The bubble unit's snapshot returns whether bubble was loaded
          (assert (= (type result.state) "boolean")
                  (.. "state should be boolean, got " (type result.state))))))))

(table.insert tests {:name "external-unit-mcp: snapshot returns unit state with capability metadata"
                     :fn test-snapshot-returns-unit-state-with-capability-metadata})

(fn test-snapshot-returns-unsupported-for-unknown-loader []
  ;; R1-3: Unknown loaders must return supported=false, not an error.
  (with-temp-dir
    (fn [dir]
      (with-service dir
        (fn [mgr _dir]
          ;; Register a unit with no owned paths (unknown loader)
          (local orphan-unit (Units.Unit {:id "orphan"
                                           :source :user
                                           :load (fn [_] true)
                                           :unload (fn [_] true)}))
          (mgr:register orphan-unit))
        (fn [_mgr service]
          (local result (service:snapshot {:unit_id "orphan"}))
          (assert result.unit-id "snapshot missing unit-id")
          (assert (= result.unit-id "orphan") "unit-id mismatch")
          (assert (= result.supported false) "unknown loader should report snapshot unsupported")
          (assert (= result.state nil) "unsupported snapshot should have nil state"))))))

(table.insert tests {:name "external-unit-mcp: snapshot returns unsupported for unknown loader"
                     :fn test-snapshot-returns-unsupported-for-unknown-loader})

(fn test-snapshot-returns-unsupported-for-filesystem-unit-without-snapshot []
  ;; R1-3 remaining: a filesystem unit without an actual snapshot export
  ;; must return supported=false, not supported=true with nil state.
  (with-temp-dir
    (fn [dir]
      (local simple-path (write-unit-file dir "no-snapshot"
                            (.. "(fn init [] true)\n"
                                "(fn drop [] true)\n"
                                "{:init init :drop drop}")))
      (with-service dir
        (fn [mgr _dir]
          (local fennel-paths (.. dir "/?.fnl;" dir "/?/init.fnl"))
          (local unit (Units.ModuleUnit
                        {:id "user-no-snapshot"
                         :module-name "no-snapshot"
                         :module-paths fennel-paths
                         :source :user
                         :suppress-run-main? true
                         :owned-paths [simple-path]}))
          (mgr:register unit))
        (fn [_mgr service]
          (local result (service:snapshot {:unit_id "user-no-snapshot"}))
          (assert result.unit-id "snapshot missing unit-id")
          (assert (= result.unit-id "user-no-snapshot") "unit-id mismatch")
          (assert (= result.supported false)
                  "filesystem unit without snapshot export should report unsupported")
          (assert (= result.state nil)
                  "unsupported snapshot should have nil state"))))))

(table.insert tests {:name "external-unit-mcp: snapshot returns unsupported for filesystem unit without snapshot export"
                      :fn test-snapshot-returns-unsupported-for-filesystem-unit-without-snapshot})

(fn test-snapshot-supports-module-unit-with-default-snapshot-export []
  ;; R1-3: A ModuleUnit constructed without explicit :snapshot-export but
  ;; whose module exports a default "snapshot" function must report
  ;; supported=true and return the snapshot state — i.e. the unit must
  ;; still be called even when :snapshot-export was not explicitly set.
  (with-temp-dir
    (fn [dir]
      (local default-snap-path (write-unit-file dir "default-snapshot"
                                  (.. "(fn init [] true)\n"
                                      "(fn drop [] true)\n"
                                      "(fn snapshot [] {:items [1 2 3] :version 1})\n"
                                      "{:init init :drop drop :snapshot snapshot}")))
      (with-service dir
        (fn [mgr _dir]
          (local fennel-paths (.. dir "/?.fnl;" dir "/?/init.fnl"))
          ;; Construct ModuleUnit WITHOUT :snapshot-export — defaults to "snapshot"
          (local unit (Units.ModuleUnit
                        {:id "user-default-snap"
                         :module-name "default-snapshot"
                         :module-paths fennel-paths
                         :source :user
                         :suppress-run-main? true
                         :owned-paths [default-snap-path]}))
          (mgr:register unit))
        (fn [_mgr service]
          (local result (service:snapshot {:unit_id "user-default-snap"}))
          (assert result.unit-id "snapshot missing unit-id")
          (assert (= result.unit-id "user-default-snap") "unit-id mismatch")
          (assert (= result.supported true)
                  (.. "module with default snapshot export should be supported, got "
                      (tostring result.supported)))
          (assert (not= result.state nil)
                  "module with default snapshot export should have non-nil state")
          (assert (= (type result.state) "table")
                  (.. "state should be a table, got " (type result.state)))
          (assert (= result.state.version 1)
                  (.. "state.version should be 1, got " (tostring result.state.version)))
          (assert (= (length result.state.items) 3)
                  "state.items should have 3 items"))))))

(table.insert tests {:name "external-unit-mcp: snapshot supports ModuleUnit with default snapshot export"
                      :fn test-snapshot-supports-module-unit-with-default-snapshot-export})


(fn test-snapshot-propagates-error-from-real-snapshot-implementation []
  ;; R1-3: a filesystem unit with an actual snapshot function that throws
  ;; an error containing "missing function" must propagate that error,
  ;; not silently return supported=false.
  (with-temp-dir
    (fn [dir]
      (local thrower-path (write-unit-file dir "snapshot-thrower"
                             (.. "(fn init [] true)\n"
                                 "(fn drop [] true)\n"
                                 "(fn snapshot []\n"
                                 "  (error \"missing function foo in snapshot\"))\n"
                                 "{:init init :drop drop :snapshot snapshot}")))
      (with-service dir
        (fn [mgr _dir]
          (local fennel-paths (.. dir "/?.fnl;" dir "/?/init.fnl"))
          (local unit (Units.ModuleUnit
                        {:id "user-snapshot-thrower"
                         :module-name "snapshot-thrower"
                         :module-paths fennel-paths
                         :source :user
                         :suppress-run-main? true
                         :owned-paths [thrower-path]
                         :snapshot-export "snapshot"}))
          (mgr:register unit))
        (fn [_mgr service]
          (local (ok err) (pcall #(service:snapshot {:unit_id "user-snapshot-thrower"})))
          (assert (not ok) "should propagate error from real snapshot implementation")
          (assert (string.find (or err "") "missing function foo" 1 true)
                  (.. "error should contain the snapshot function's message, got: " (or err ""))))))))

(table.insert tests {:name "external-unit-mcp: snapshot propagates error from real snapshot implementation"
                     :fn test-snapshot-propagates-error-from-real-snapshot-implementation})

(fn test-snapshot-errors-on-default-export-module-load-failure []
  ;; R1-3: A ModuleUnit without explicit :snapshot-export whose module fails
  ;; to load (e.g. a compile error) must propagate the load error, not
  ;; silently return supported=false. The defect was that has-snapshot?
  ;; used pcall(require-module) and treated the load failure as "no
  ;; snapshot capability" instead of propagating it.
  (with-temp-dir
    (fn [dir]
      (local bad-path (write-unit-file dir "broken-module"
                        "(fn init [] tru\n"  ;; missing closing paren + bad bool
                        "(fn drop [] true)\n"
                        "{:init init :drop drop}\n"))
      (with-service dir
        (fn [mgr _dir]
          (local fennel-paths (.. dir "/?.fnl;" dir "/?/init.fnl"))
          ;; No :snapshot-export — the lazy has-snapshot? will try to
          ;; load the module and must propagate the compile error.
          (local unit (Units.ModuleUnit
                        {:id "user-broken-module"
                         :module-name "broken-module"
                         :module-paths fennel-paths
                         :source :user
                         :suppress-run-main? true
                         :owned-paths [bad-path]}))
          (mgr:register unit))
        (fn [_mgr service]
          (local (ok err) (pcall #(service:snapshot {:unit_id "user-broken-module"})))
          (assert (not ok) "should propagate module load error, not return supported=false")
          (assert (string.find (or err "") "broken-module" 1 true)
                  (.. "error should mention the failing module name, got: " (or err ""))))))))

(table.insert tests {:name "external-unit-mcp: snapshot errors on default-export module load failure"
                     :fn test-snapshot-errors-on-default-export-module-load-failure})

(fn test-read-log-returns-filtered-recent-lines []
  ;; read-log returns structured lines, total-lines, and log-path.
  ;; R1-4: uses an isolated controlled log fixture with a known exact
  ;; newline-terminated line count instead of the live application log.
  ;; The controlled fixture is injected via ExternalUnitService opts
  ;; (:log_path), not via a public args.log_path on read-log itself.
  (with-temp-dir
    (fn [dir]
      ;; Create a controlled log fixture with exactly 5 lines
      ;; and a trailing newline (newline-terminated).
      (local fixture-path (fs.join-path dir "controlled.log"))
      (local fixture-content "alpha\nbeta\ngamma\ndelta\nepsilon\n")
      (fs.write-file fixture-path fixture-content)
      (with-service* dir
        (fn [mgr _dir] nil)  ;; no units needed
        {:log_path fixture-path}
        (fn [_mgr service]
          (local result (service:read-log {}))
          (assert result.lines "read-log missing lines")
          (assert (= (type result.lines) "table") "lines should be a table")
          ;; total-lines must exactly match the known fixture count (5)
          (assert result.total-lines "read-log missing total-lines")
          (assert (= (type result.total-lines) "number")
                  "total-lines should be a number")
          (assert (= result.total-lines 5)
                  (.. "total-lines should be 5 for 5-line newline-terminated fixture, got "
                      result.total-lines))
          (assert result.log-path "read-log missing log-path")
          (assert (= result.log-path fixture-path) "log-path should match fixture path")
          ;; Verify all 5 lines are present and line numbers are correct
          (assert (= (length result.lines) 5)
                  (.. "expected 5 lines, got " (length result.lines)))
          (local expected ["1: alpha" "2: beta" "3: gamma" "4: delta" "5: epsilon"])
          (each [i line (ipairs result.lines)]
            (assert (= line (. expected i))
                    (.. "line " i " mismatch: " line " vs " (. expected i))))
          ;; grep filtering: only lines containing "ta" (beta, delta)
          (local filtered (service:read-log {:grep "ta"}))
          (assert (= (length filtered.lines) 2)
                  (.. "grep for 'ta' should find 2 lines, got " (length filtered.lines)))
          (assert (= filtered.total-lines 5) "total-lines should still be 5")
          (assert (= (. filtered.lines 1) "2: beta")
                  (.. "first grep hit: " (. filtered.lines 1)))
          (assert (= (. filtered.lines 2) "4: delta")
                  (.. "second grep hit: " (. filtered.lines 2))))))))

(table.insert tests {:name "external-unit-mcp: read-log returns filtered recent lines"
                     :fn test-read-log-returns-filtered-recent-lines})

(fn test-run-tests-executes-unit-test-module []
  (with-temp-dir
    (fn [dir]
      ;; Create a directory-based unit with a test module at the standard location:
      ;; <unit-dir>/test-init.fnl (not nested under the module name).
      ;; get-unit-fennel-root returns the parent of unit-dir, so Fennel path
      ;; <parent>/?.fnl resolves module run-tests-unit.test-init to <unit-dir>/test-init.fnl.
      (local unit-dir (fs.join-path dir "run-tests-unit"))
      (fs.create-dirs unit-dir)
      (local init-path (fs.join-path unit-dir "init.fnl"))
      (fs.write-file init-path
        (.. "(fn init [] true)\n"
            "(fn drop [] true)\n"
            "{:init init :drop drop}"))
      ;; Create the test module at the standard location: unit-dir/test-init.fnl
      (local test-path (fs.join-path unit-dir "test-init.fnl"))
      (fs.write-file test-path
        (.. "(fn main []\n"
            "  (print \"ALL TESTS PASSED\")\n"
            "  (print \"1/1 passing\"))\n"
            "(fn tests [])\n"
            "{:main main :tests tests}"))
      (with-service dir
        (fn [mgr _dir]
          ;; Fennel path must include the parent directory (dir) so that
          ;; module run-tests-unit.test-init resolves to dir/run-tests-unit/test-init.fnl
          (local fennel-paths (.. dir "/?.fnl;" dir "/?/init.fnl"))
          (local unit (Units.ModuleUnit
                        {:id "user-run-tests-unit"
                         :module-name "run-tests-unit"
                         :module-paths fennel-paths
                         :source :user
                         :suppress-run-main? true
                         :owned-paths [unit-dir init-path]}))
          (mgr:register unit))
        (fn [_mgr service]
          (local result (service:run-tests {:unit_id "user-run-tests-unit"
                                             :test_name "init"}))
          (assert (= result.passed true) "tests should pass")
          (assert (= result.exit-code 0)
                  (.. "exit-code should be 0, got " result.exit-code
                      " stdout: " (or result.stdout "")
                      " stderr: " (or result.stderr "")))
          (assert result.stdout "run-tests missing stdout")
          (assert (or (string.find result.stdout "PASS" 1 true)
                      (string.find result.stdout "passing" 1 true)
                      (string.find result.stdout "ALL TESTS" 1 true))
                  (.. "stdout should contain success indicator: " result.stdout)))))))

(table.insert tests {:name "external-unit-mcp: run-tests executes unit test module"
                     :fn test-run-tests-executes-unit-test-module})

(fn test-run-tests-rejects-unknown-loader []
  ;; R1-2: run-tests must fail loudly when the loader lacks run-test capability.
  (with-temp-dir
    (fn [dir]
      (with-service dir
        (fn [mgr _dir]
          ;; Register an unknown-loader unit (no owned paths)
          (local orphan-unit (Units.Unit {:id "orphan"
                                           :source :user
                                           :load (fn [_] true)
                                           :unload (fn [_] true)}))
          (mgr:register orphan-unit))
        (fn [_mgr service]
          (local (ok err) (pcall #(service:run-tests {:unit_id "orphan"})))
          (assert (not ok) "should reject run-tests for unknown loader")
          (assert (or (string.find (or err "") "does not support" 1 true)
                      (string.find (or err "") "test execution" 1 true))
                  (.. "error should mention lack of test support, got: " (or err ""))))))))

(table.insert tests {:name "external-unit-mcp: run-tests rejects unknown loader without run-test capability"
                     :fn test-run-tests-rejects-unknown-loader})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "external-unit-mcp"
                       :tests tests})))

{:name "external-unit-mcp"
 :tests tests
 :main main}
