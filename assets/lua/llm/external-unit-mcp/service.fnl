;; External Unit MCP Service — loader-neutral unit discovery, handles, inspect, and resolve.
;; This is a read-only facade over the UnitManager that presents units in a loader-neutral
;; interface. It does not mutate units or expose raw filesystem paths directly.

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

(fn path-basename [path]
  (local (name) (string.match path "([^/]+)$"))
  name)

(fn path-has-fnl-extension? [path]
  (not= (string.match (or path "") "%.fnl$") nil))

(fn derive-source-artifacts [unit]
  (local paths (or unit.owned-paths []))
  (local artifacts [])
  ;; Collect regular files from owned paths for source artifacts.
  ;; Directories are included in owned-paths but are not source artifacts.
  (each [_ path (ipairs paths)]
    (when (and path (fs.exists path) (not (let [st (fs.stat path)] (and st st.is-dir))))
      (local source-id (path-basename path))
      (local primary (path-has-fnl-extension? path))
      (local file-size (or (and (fs.exists path)
                                (let [stat (fs.stat path)]
                                  (and stat.exists stat.size)))
                           0))
      (local (hash-ok file-hash) (pcall #(Sha256.hash-file path)))
      (table.insert artifacts
                    {:source-id source-id
                     :kind "file"
                     :primary primary
                     :size file-size
                     :hash (if hash-ok file-hash "unknown")})))
  artifacts)

(fn primary-source-artifact [artifacts]
  (var primary nil)
  (each [_ art (ipairs artifacts) &until primary]
    (when art.primary
      (set primary art)))
  (or primary (. artifacts 1)))

(fn build-source-handle [unit]
  (local artifacts (derive-source-artifacts unit))
  (if (= (length artifacts) 0)
      nil
      (let [primary (primary-source-artifact artifacts)]
        {:source-id primary.source-id
         :kind primary.kind
         :primary true
         :size primary.size
         :hash primary.hash})))

(fn build-edit-capabilities [loader]
  (if (= loader "filesystem")
      ["read" "write" "create" "delete"]
      []))

(fn build-test-capabilities [loader]
  (if (= loader "filesystem")
      ["run-test"]
      []))

(fn build-commit-capability [_loader]
  "none")

;; ── Handle construction ──

(fn unit-handle [self unit]
  (local loader (classify-loader unit))
  {:unit-id unit.id
   :loader loader
   :source-handle (build-source-handle unit)
   :edit-capabilities (build-edit-capabilities loader)
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

;; ── Service ──

(fn ExternalUnitService [opts]
  (local app (or opts.app (error "ExternalUnitService requires :app")))
  (local mgr (require-unit-manager app))

  (local self {})

  (fn list [_ args]
    (local results [])
    (local units (mgr:list))
    ;; Collect handles sorted by unit-id for deterministic ordering
    (each [_ unit (ipairs units)]
      (table.insert results (unit-handle self unit)))
    (table.sort results (fn [a b] (< a.unit-id b.unit-id)))
    results)

  (fn inspect [_ args]
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

  (fn resolve [self args]
    (local description (or args.description
                           (error "resolve requires :description")))
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
    ;; Apply optional limit
    (when (and limit (> (length candidates) limit))
      (while (> (length candidates) limit)
        (table.remove candidates)))
    {:candidates candidates})

  (set self.unit-handle unit-handle)
  (set self.list list)
  (set self.inspect inspect)
  (set self.resolve resolve)

  self)

{:ExternalUnitService ExternalUnitService}
