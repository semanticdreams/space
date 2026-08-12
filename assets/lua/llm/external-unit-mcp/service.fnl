;; External Unit MCP Service — loader-neutral unit discovery, handles, inspect, resolve,
;; source read, patch, create, and reload operations.

(local fs (require :fs))
(local Sha256 (require :repo/sha256))

;; ── Private helpers ──

(fn require-unit-manager [app]
  (assert app.unit-manager "ExternalUnitService requires app.unit-manager")
  app.unit-manager)

(fn classify-loader [unit]
  (if (and (= unit.source :user)
           unit.owned-paths
           (> (length unit.owned-paths) 0))
      "filesystem"
      "unknown"))

(fn path-separator? [c]
  (if (= c "/") true
      (= c "\\") true
      false))

(fn normalize-logical-path [path]
  (select 1 (string.gsub (if path path "") "\\" "/")))

(fn path-basename [path]
  (local normalized (normalize-logical-path path))
  (local name (string.match normalized "([^/]+)$"))
  name)

(fn path-has-fnl-extension? [path]
  (not= (string.match (or path "") "%.fnl$") nil))

(fn get-unit-root-dir [unit]
  ;; Find the unit root directory from owned-paths (first directory entry).
  (local paths (or unit.owned-paths []))
  (var root nil)
  (each [_ path (ipairs paths) &until root]
    (when (and path (fs.exists path))
      (local st (fs.stat path))
      (when (and st st.is-dir)
        (set root path))))
  root)

(fn derive-source-artifacts [unit]
  (local loader (classify-loader unit))
  ;; R1-1: Only filesystem loaders expose source artifacts.
  (when (not= loader "filesystem")
    (lua "return {}"))
  (local paths (or unit.owned-paths []))
  (local artifacts [])
  (local unit-root (get-unit-root-dir unit))
  (local seen-ids {})
  ;; Collect regular files from owned paths for source artifacts.
  ;; Directories are included in owned-paths but are not source artifacts.
  (each [_ path (ipairs paths)]
    (when (and path (fs.exists path) (not (let [st (fs.stat path)] (and st st.is-dir))))
      ;; R1-2: For directory units, compute source-id as the path relative to the
      ;; unit root so that nested artifacts (e.g. components/view.fnl) are
      ;; addressable by source-id.  For flat units, fall back to basename.
      (local source-id
        (if unit-root
            (let [norm-root (normalize-logical-path unit-root)
                  norm-path (normalize-logical-path path)
                  prefix (.. norm-root "/")]
              (if (= (string.sub norm-path 1 (# prefix)) prefix)
                  (string.sub norm-path (+ (# prefix) 1))
                  (path-basename path)))
            (path-basename path)))
      ;; Reject duplicate source-ids to prevent collisions.
      (assert (not (. seen-ids source-id))
              (.. "duplicate source-id in unit " unit.id ": " source-id))
      (tset seen-ids source-id true)
      (local primary (path-has-fnl-extension? path))
      (local file-size (or (and (fs.exists path)
                                (let [stat (fs.stat path)]
                                  (and stat.exists stat.size)))
                           0))
      (local file-hash (.. "sha256:" (Sha256.hash-file path)))
      (table.insert artifacts
                    {:source-id source-id
                     :kind "file"
                     :primary primary
                     :size file-size
                     :hash file-hash})))
  artifacts)

(fn primary-source-artifact [artifacts]
  (var primary nil)
  (each [_ art (ipairs artifacts) &until primary]
    (when art.primary
      (set primary art)))
  (or primary (. artifacts 1)))

(fn build-source-handle [unit]
  (local loader (classify-loader unit))
  ;; R1-1: Only filesystem loaders expose source handles.
  (when (not= loader "filesystem")
    (lua "return nil"))
  (local artifacts (derive-source-artifacts unit))
  (if (= (length artifacts) 0)
      nil
      (let [primary (primary-source-artifact artifacts)]
        {:source-id primary.source-id
         :kind primary.kind
         :primary true
         :size primary.size
         :hash primary.hash})))

(fn build-test-capabilities [loader]
  (if (= loader "filesystem")
      ["run-test"]
      []))

(fn build-commit-capability [_loader]
  "none")

;; ── Task 2: Source resolution and mutation helpers ──

(fn hash-file [path]
  (.. "sha256:" (Sha256.hash-file path)))

(fn validate-source-id [source-id operation]
  (assert (= (type source-id) "string")
          (.. operation " requires a string :source_id"))
  (assert (> (# source-id) 0)
          (.. operation " :source_id must not be empty"))
  (assert (not (string.find source-id "\0" 1 true))
          (.. operation " :source_id contains a NUL byte"))
  (assert (not (or (string.match source-id "^/")
                   (string.match source-id "^%a:[\\/]")))
          (.. operation " :source_id must be relative, not absolute"))
  (assert (not (or (string.match source-id "%f[^/\\]%.%.[/\\]")
                    (string.match source-id "%.%.$")
                    (= source-id "..")))
          (.. operation " :source_id must not contain .. segments")))

(fn is-directory-unit? [unit]
  (not= (get-unit-root-dir unit) nil))

(fn build-edit-capabilities [loader unit]
  (if (= loader "filesystem")
      (if (is-directory-unit? unit)
          ["read" "write" "create" "delete"]
          ["read" "write" "delete"])
      []))

(fn get-primary-source-path [unit]
  ;; Find the first .fnl file in owned-paths.
  (local paths (or unit.owned-paths []))
  (var primary nil)
  (each [_ path (ipairs paths) &until primary]
    (when (and path (path-has-fnl-extension? path))
      (set primary path)))
  primary)

(fn get-primary-source-basename [unit]
  (local primary-path (get-primary-source-path unit))
  (when primary-path
    (path-basename primary-path)))

(fn assert-filesystem-unit [unit operation]
  (assert (not (= unit.source :builtin))
          (.. operation ": cannot modify built-in unit " unit.id))
  (assert (= (classify-loader unit) "filesystem")
          (.. operation ": unit " unit.id " loader does not support write operations")))

(fn assert-directory-unit [unit operation]
  (assert-filesystem-unit unit operation)
  (assert (is-directory-unit? unit)
          (.. operation ": unit " unit.id " is a flat unit and cannot create new source artifacts")))

(fn resolve-source-path [unit source-id operation]
  ;; Resolve a source_id to a safe absolute file path for a filesystem unit.
  ;; Rejects invalid source_ids, path-escape attempts, and symlink traversal.
  (validate-source-id source-id operation)
  (var root nil)
  (var raw-joined nil)
  (if (is-directory-unit? unit)
      (do
        (set root (get-unit-root-dir unit))
        (set raw-joined (fs.join-path root source-id)))
      (let [primary-basename (get-primary-source-basename unit)]
        (assert primary-basename
                (.. operation ": unit " unit.id " has no primary source file"))
        (assert (= source-id primary-basename)
                (.. operation ": flat unit " unit.id " only accepts source_id " primary-basename))
        (local primary-path (get-primary-source-path unit))
        (set root (fs.parent primary-path))
        (set raw-joined primary-path)))
  ;; Path containment check against unit root — compare normalized paths
  ;; so that Windows backslash separators are treated the same as slashes.
  (local root-absolute (fs.absolute root))
  (local resolved-absolute (fs.absolute raw-joined))
  (local norm-root (normalize-logical-path root-absolute))
  (local norm-resolved (normalize-logical-path resolved-absolute))
  (assert (and (>= (# norm-resolved) (# norm-root))
               (= (string.sub norm-resolved 1 (# norm-root)) norm-root)
               (or (= (# norm-resolved) (# norm-root))
                   (= (string.sub norm-resolved (+ (# norm-root) 1)
                                  (+ (# norm-root) 1)) "/")))
          (.. operation ": source_id escapes unit directory: " source-id))
  ;; Reject symlink at the resolved path itself
  (when (fs.exists resolved-absolute)
    (local st (fs.stat resolved-absolute))
    (assert (not st.is-symlink)
            (.. operation ": target is a symlink: " source-id)))
  ;; Reject symlinked ancestor directories
  (var current (fs.parent resolved-absolute))
  (while (and current
              (> (# current) (# root-absolute))
              (not= (fs.absolute current) root-absolute))
    (local st (fs.stat current))
    (assert (not (and st.exists st.is-symlink))
            (.. operation ": path ancestor is a symlink: " current))
    (set current (fs.parent current)))
  resolved-absolute)

(fn validate-fnl-source [path source]
  (when (path-has-fnl-extension? path)
    (local fennel (require :fennel))
    (local (compile-ok compile-err) (pcall fennel.compile-string source
                                            {:filename path}))
    (assert compile-ok (.. "source does not compile: " (tostring compile-err)))))

(fn merge-reload-success [base reload-result]
  (each [k v (pairs (if reload-result reload-result {}))]
    (tset base k v))
  (tset base :reload-result reload-result)
  (when (and reload-result reload-result.activity)
    (tset base :activity reload-result.activity))
  base)

(fn validate-current-source-and-reload [mgr unit-id target-path]
  (local current-source (fs.read-file target-path))
  (validate-fnl-source target-path current-source)
  (mgr:reload-unit unit-id {}))

(fn reload-unit-with-result [mgr unit-id]
  (mgr:reload-unit unit-id {}))

(fn recovery-reload! [mgr unit-id]
  (pcall reload-unit-with-result mgr unit-id)
  true)

(fn apply-diff-patch-and-reload [mgr unit unit-id source-id target-path old-source patch]
  (assert (= (type patch) "string") "apply-patch :patch must be a string")
  (local ApplyPatch (require :llm/tools/apply-patch))
  (local root (if (get-unit-root-dir unit) (get-unit-root-dir unit) (fs.parent target-path)))
  (local (patch-ok patch-err)
    (pcall ApplyPatch.call
           {:path source-id :patch patch :allow_create false}
           {:cwd root}))
  (when (not patch-ok)
    (pcall fs.write-file target-path old-source)
    (error (.. "apply-patch failed, source restored: " (tostring patch-err))))
  (local (validate-ok reload-result-or-err)
    (pcall validate-current-source-and-reload mgr unit-id target-path))
  (if validate-ok
      (merge-reload-success {:unit-id unit.id :source-id source-id :reloaded true :hash (hash-file target-path)} reload-result-or-err)
      (do
        (pcall fs.write-file target-path old-source)
        (recovery-reload! mgr unit-id)
        (error (.. "apply-patch reload failed, source restored: " (tostring reload-result-or-err))))))

(fn exact-replacement-source [old-source old-text new-text]
  (assert (= (type old-text) "string") "apply-patch :old must be a string")
  (assert (= (type new-text) "string") "apply-patch :new must be a string")
  (assert (> (# old-text) 0) "apply-patch :old must not be empty")
  (local (start-pos end-pos) (string.find old-source old-text 1 true))
  (assert start-pos "apply-patch: :old text was not found in source")
  (local (next-pos) (string.find old-source old-text (+ end-pos 1) true))
  (assert (not next-pos) "apply-patch: :old text matched more than once")
  (.. (string.sub old-source 1 (- start-pos 1))
      new-text
      (string.sub old-source (+ end-pos 1))))

(fn apply-exact-replacement-and-reload [mgr unit unit-id source-id target-path old-source old-text new-text]
  (local new-source (exact-replacement-source old-source old-text new-text))
  (validate-fnl-source target-path new-source)
  (local (write-ok write-err) (pcall fs.write-file target-path new-source))
  (when (not write-ok)
    (error (.. "apply-patch failed to write: " (tostring write-err))))
  (local (reload-ok reload-result-or-err) (pcall reload-unit-with-result mgr unit-id))
  (if reload-ok
      (merge-reload-success {:unit-id unit.id :source-id source-id :reloaded true :hash (hash-file target-path)} reload-result-or-err)
      (do
        (pcall fs.write-file target-path old-source)
        (recovery-reload! mgr unit-id)
        (error (.. "apply-patch reload failed, source restored: " (tostring reload-result-or-err))))))

(fn create-source-and-reload [mgr unit unit-id source-id target-path source]
  (local parent-dir (fs.parent target-path))
  (when (and parent-dir (not (fs.exists parent-dir)))
    (fs.create-dirs parent-dir))
  (local (write-ok write-err) (pcall fs.write-file target-path source))
  (when (not write-ok)
    (error (.. "create-source failed to write: " (tostring write-err))))
  (local (reload-ok reload-result-or-err) (pcall reload-unit-with-result mgr unit-id))
  (if reload-ok
      (merge-reload-success {:unit-id unit.id :source-id source-id :created true :reloaded true :hash (hash-file target-path)} reload-result-or-err)
      (do
        (pcall fs.remove-all target-path)
        (error (.. "create-source reload failed, new file removed: " (tostring reload-result-or-err))))))

;; ── Handle construction ──

(fn unit-handle [self unit]
  (local loader (classify-loader unit))
  {:unit-id unit.id
   :loader loader
   :source-handle (build-source-handle unit)
   :edit-capabilities (build-edit-capabilities loader unit)
   :test-capabilities (build-test-capabilities loader)
   :commit-capability (build-commit-capability loader)})

;; ── Lifecycle export helpers ──

(fn lifecycle-exports [unit]
  {:init (or unit.load-export "init")
   :drop (or unit.unload-export "drop")
   :snapshot (or unit.snapshot-export "snapshot")
   :restore (or unit.restore-export "restore")})

;; ── Token matching for resolve ──

(fn tokenize [text]
  (local tokens [])
  (each [token (string.gmatch (string.lower (or text "")) "%w+")]
    (table.insert tokens token))
  tokens)

(fn match-tokens [candidate-text tokens]
  (local lowered (string.lower (or candidate-text "")))
  (var matches 0)
  (each [_ token (ipairs tokens)]
    (when (string.find lowered token 1 true)
      (set matches (+ matches 1))))
  matches)

(fn resolve-candidate-evidence [unit matched-tokens total-tokens]
  (local confidence (/ matched-tokens total-tokens))
  (local pct (string.format "%.0f" (* confidence 100)))
  (.. "matched " matched-tokens "/" total-tokens " tokens across unit id, module name, and source file basenames (" pct "%)"))

(fn read-log [self args]
  (local fs (require :fs))
  (local log-path
    (if self._log_path
        self._log_path
        (do
          (local logging (require :logging))
          (logging.get-output-path))))
  (when (not (fs.exists log-path))
    (error (.. "read-log: log file not found: " log-path)))
  (var content (fs.read-file log-path))
  (when (or (not content) (= content ""))
    (error "read-log: log file is empty"))
  (local all-lines [])
  (each [line (_G.string.gmatch content "([^\n]*)\n?")]
    (table.insert all-lines line))
  (when (= (# all-lines) 0)
    (error "read-log: log file is empty"))
  ;; Drop trailing empty string from final \n
  (when (and (> (# all-lines) 0) (= (. all-lines (# all-lines)) ""))
    (table.remove all-lines))
  (local total-count (# all-lines))
  (local grep (and args.grep (> (# args.grep) 0) args.grep))
  (var result-lines [])
  (var i (or args.offset 1))
  (var remaining (or args.limit (or (and args.offset 200) (or args.lines 100))))
  (when (< i 1) (set i 1))
  (when args.lines
    (set i (math.max 1 (- (# all-lines) args.lines -1))))
  (while (and (<= i (# all-lines)) (> remaining 0))
    (local line (. all-lines i))
    (when (or (not grep) (string.find line grep 1 true))
      (table.insert result-lines (.. i ": " line))
      (set remaining (- remaining 1)))
    (set i (+ i 1)))
  {:lines result-lines
   :total-lines total-count
   :log-path log-path})

(fn snapshot [self args]
  (local mgr self._mgr)
  (local unit-id (or args.unit_id (error "snapshot requires :unit_id")))
  (local unit (mgr:get unit-id))
  (assert unit (.. "unit not found: " unit-id))
  (local has-snapshot? (if (= (type unit.has-snapshot?) "function")
                          (unit.has-snapshot? unit)
                          unit.has-snapshot?))
  ;; Determine snapshot support structurally via has-snapshot?
  ;; before calling unit:snapshot, so we never invoke a noop/default.
  ;; For Unit: has-snapshot? is true only when a :snapshot function
  ;; was explicitly provided (defaults to noop otherwise).
  ;; For ModuleUnit: has-snapshot? is a function that checks whether
  ;; the option :snapshot-export was explicitly set OR the loaded
  ;; module has a matching default snapshot export.
  ;; For SourceUnit: has-snapshot? is true only when :snapshot-export
  ;; was explicitly set in the options.
  (if (not has-snapshot?)
      {:unit-id unit.id
       :supported false
       :state nil}
      (do
        (local (ok state) (pcall #(unit:snapshot {})))
        (if ok
            {:unit-id unit.id
             :supported true
             :state state}
            (error (.. "snapshot: call failed for unit " unit-id ": " (tostring state)))))))

(fn list-units [self args]
  (local mgr self._mgr)
  (local results [])
  (local units (mgr:list))
  ;; Collect handles sorted by unit-id for deterministic ordering
  (each [_ unit (ipairs units)]
    (table.insert results (unit-handle self unit)))
  (table.sort results (fn [a b] (< a.unit-id b.unit-id)))
  results)

(fn inspect-unit [self args]
  (local mgr self._mgr)
  (local unit-id (or args.unit_id (error "inspect requires :unit_id")))
  (local unit (mgr:get unit-id))
  (assert unit (.. "unit not found: " unit-id))
  (local loader (classify-loader unit))
  (local source-handle (build-source-handle unit))
  (local artifacts (derive-source-artifacts unit))
  {:unit-id unit.id
   :loader loader
   :source-handle source-handle
   :lifecycle (lifecycle-exports unit)
   :source-artifacts artifacts})

(fn resolve-unit [self args]
  (local mgr self._mgr)
  (local description (or args.description
                         (error "resolve requires :description")))
  (when (not= args.limit nil)
    (assert (= (type args.limit) :number)
            "resolve :limit must be a number")
    (assert (>= args.limit 0)
            "resolve :limit must be non-negative")
    (assert (= args.limit (math.floor args.limit))
            "resolve :limit must be an integer"))
  (local limit (or args.limit 20))
  (local tokens (tokenize description))
  (assert (> (length tokens) 0)
          "resolve :description must contain at least one token")
  (local units (mgr:list))
  (local candidates [])
  (each [_ unit (ipairs units)]
    (local loader (classify-loader unit))
    (local artifacts (derive-source-artifacts unit))
    (var total-matches 0)
    (var max-possible 0)
    ;; Match against unit id
    (set total-matches (+ total-matches (match-tokens unit.id tokens)))
    (set max-possible (+ max-possible (length tokens)))
    ;; Match against module name
    (set total-matches (+ total-matches (match-tokens (or unit.module-name "") tokens)))
    (set max-possible (+ max-possible (length tokens)))
    ;; Match against source artifact ids (basenames)
    (each [_ art (ipairs artifacts)]
      (set total-matches (+ total-matches (match-tokens art.source-id tokens)))
      (set max-possible (+ max-possible (length tokens))))
    (when (> total-matches 0)
      (local confidence (math.min 1.0 (/ total-matches max-possible)))
      (table.insert candidates
                    {:unit-id unit.id
                     :confidence confidence
                     :evidence (resolve-candidate-evidence unit total-matches (length tokens))})))
  ;; Sort by confidence descending, then by unit-id for deterministic tie-breaking
  (table.sort candidates
              (fn [a b]
                (if (> a.confidence b.confidence) true
                    (< a.confidence b.confidence) false
                    (< a.unit-id b.unit-id))))
  ;; Apply optional limit via bounded slicing — cannot loop indefinitely
  (when (> (length candidates) limit)
    (while (> (length candidates) limit)
      (table.remove candidates)))
  {:candidates candidates})

(fn read-source [self args]
  (local mgr self._mgr)
  (local unit-id (or args.unit_id (error "read-source requires :unit_id")))
  (local source-id (or args.source_id (error "read-source requires :source_id")))
  (local unit (mgr:get unit-id))
  (assert unit (.. "unit not found: " unit-id))
  ;; R1-1: Gate on filesystem loader and read capability.
  (local loader (classify-loader unit))
  (assert (= loader "filesystem")
          (.. "read-source: unit " unit-id " loader " loader
              " does not support source read operations"))
  (local edit-caps (build-edit-capabilities loader unit))
  (var has-read false)
  (each [_ cap (ipairs edit-caps)]
    (when (= cap "read") (set has-read true)))
  (assert has-read
          (.. "read-source: unit " unit-id " loader " loader
              " does not support read capability"))
  (local target-path (resolve-source-path unit source-id "read-source"))
  (assert (fs.exists target-path)
          (.. "read-source: source file not found: " source-id))
  (local content (fs.read-file target-path))
  {:unit-id unit.id
   :source-id source-id
   :content content
   :hash (hash-file target-path)})

(fn apply-patch [self args]
  (local mgr self._mgr)
  (local unit-id (or args.unit_id (error "apply-patch requires :unit_id")))
  (local source-id (or args.source_id (error "apply-patch requires :source_id")))
  (local unit (mgr:get unit-id))
  (assert unit (.. "unit not found: " unit-id))
  (assert-filesystem-unit unit "apply-patch")
  (local target-path (resolve-source-path unit source-id "apply-patch"))
  (assert (fs.exists target-path)
          (.. "apply-patch: source file not found: " source-id))
  (when args.expected_hash
    (local current-hash (hash-file target-path))
    (assert (= current-hash args.expected_hash)
            (.. "apply-patch rejected: expected hash " args.expected_hash
                " but current hash is " current-hash)))
  (local old-source (fs.read-file target-path))
  (local has-patch (not= args.patch nil))
  (local has-old (not= args.old nil))
  (local has-new (not= args.new nil))
  (assert (not (and has-patch (or has-old has-new)))
          "apply-patch: provide either :patch or :old/:new, not both")
  (assert (or has-patch (and has-old has-new))
          "apply-patch: provide either :patch or both :old and :new")
  (assert (or has-patch (= has-old has-new))
          "apply-patch: both :old and :new are required for exact replacement")
  (if has-patch
      (apply-diff-patch-and-reload mgr unit unit-id source-id target-path old-source args.patch)
      (apply-exact-replacement-and-reload mgr unit unit-id source-id target-path old-source args.old args.new)))

(fn create-source [self args]
  (local mgr self._mgr)
  (local unit-id (or args.unit_id (error "create-source requires :unit_id")))
  (local source-id (or args.source_id (error "create-source requires :source_id")))
  (local source (or args.source (error "create-source requires :source")))
  (assert (= (type source) "string") "create-source :source must be a string")
  (local unit (mgr:get unit-id))
  (assert unit (.. "unit not found: " unit-id))
  (assert-directory-unit unit "create-source")
  (local target-path (resolve-source-path unit source-id "create-source"))
  (assert (not (fs.exists target-path))
          (.. "create-source: file already exists: " source-id))
  (validate-fnl-source target-path source)
  (create-source-and-reload mgr unit unit-id source-id target-path source))

(fn reload-unit [self args]
  (local mgr self._mgr)
  (local unit-id (or args.unit_id (error "reload requires :unit_id")))
  (local unit (mgr:get unit-id))
  (assert unit (.. "unit not found: " unit-id))
  (merge-reload-success {:unit-id unit.id
                         :reloaded true}
                        (mgr:reload-unit unit-id {})))

(fn get-unit-fennel-root [unit]
  ;; Return the directory that serves as the Fennel path base for this unit.
  (local paths (if unit.owned-paths unit.owned-paths []))
  (var root nil)
  (each [_ path (ipairs paths) &until root]
    (when (and path (fs.exists path))
      (local st (fs.stat path))
      (if (and st st.is-dir)
          (set root (fs.parent path))
          (set root (fs.parent path)))))
  root)

(fn resolve-space-bin [fs]
  (if (os.getenv "SPACE_BIN")
      (os.getenv "SPACE_BIN")
      (do
        (local cwd (fs.cwd))
        (local base-candidates [(fs.join-path cwd "build" "space")
                                (fs.join-path cwd "build" "dist" "windows" "space")
                                (fs.join-path cwd "space")
                                (fs.join-path cwd ".." "build" "space")])
        (var resolved nil)
        (each [_ candidate (ipairs base-candidates) &until resolved]
          (when (fs.exists candidate)
            (set resolved candidate))
          (when (and (not resolved) (fs.exists (.. candidate ".exe")))
            (set resolved (.. candidate ".exe"))))
        (assert resolved
                (.. "run-tests: could not locate space binary from cwd " cwd))
        resolved)))

(fn run-tests [self args]
  (local mgr self._mgr)
  (local unit-id (or args.unit_id (error "run-tests requires :unit_id")))
  (local unit (mgr:get unit-id))
  (assert unit (.. "unit not found: " unit-id))
  (local loader (classify-loader unit))
  (local capabilities (build-test-capabilities loader))
  (var can-run? false)
  (each [_ cap (ipairs capabilities)]
    (when (= cap "run-test")
      (set can-run? true)))
  (assert can-run?
          (.. "run-tests: unit " unit-id " loader " loader
              " does not support test execution"))
  (local test-name (or args.test_name "init"))
  (local name (or unit.module-name unit.id))
  (local test-module (.. name ".test-" test-name))
  (local Process (require :process))
  (local runtime (require :runtime))
  (local fs (require :fs))
  (local assets-path (or (os.getenv "SPACE_ASSETS_PATH") runtime.assets-path))
  (local space-bin (resolve-space-bin fs))
  (local unit-root (get-unit-fennel-root unit))
  (assert unit-root
          (.. "run-tests: could not determine Fennel path root for unit " unit-id))
  (local unit-fennel-path
    (.. (fs.join-path unit-root "?" "init.fnl")
        ";" (fs.join-path unit-root "?.fnl")))
  (local fennel-path
    (if (> (# unit-fennel-path) 0)
        (.. unit-fennel-path ";" runtime.fennel-path)
        runtime.fennel-path))
  (local result (Process.run
                  {:args [space-bin "-m" (.. test-module ":main")]
                   :env {:FENNEL_PATH fennel-path
                         :FENNEL_MACRO_PATH fennel-path
                         :SPACE_ASSETS_PATH assets-path
                         :SPACE_DISABLE_AUDIO "1"}
                   :timeout 30}))
  {:passed (= result.exit-code 0)
   :exit-code result.exit-code
   :stdout (or result.stdout "")
   :stderr result.stderr})

;; ── Service ──

(fn ExternalUnitService [opts]
  (local app (or opts.app (error "ExternalUnitService requires :app")))
  (local mgr (require-unit-manager app))

  (local self {})
  (tset self :_mgr mgr)
  (tset self :_log_path opts.log_path)

  (set self.unit-handle unit-handle)
  (set self.list list-units)
  (set self.inspect inspect-unit)
  (set self.resolve resolve-unit)
  (set self.read-source read-source)
  (set self.apply-patch apply-patch)
  (set self.create-source create-source)
  (set self.reload reload-unit)
  (set self.run-tests run-tests)
  (set self.read-log read-log)
  (set self.snapshot snapshot)

  self)

{:ExternalUnitService ExternalUnitService
 :_normalize_logical_path normalize-logical-path}
