(fn assert-fn [spec key]
  (local value (. spec key))
  (assert (= (type value) :function)
          (.. "Unit requires function :" key))
  value)

(fn noop-snapshot [_ctx]
  nil)

(fn noop-restore [_state _ctx]
  true)

(fn clone-list [items]
  (icollect [_ item (ipairs (or items []))]
    item))

(fn Unit [opts]
  (local spec (or opts {}))
  (local id (assert spec.id "Unit requires :id"))
  (local load-fn (assert-fn spec :load))
  (local unload-fn (assert-fn spec :unload))
  (local snapshot-fn (or spec.snapshot noop-snapshot))
  (local restore-fn (or spec.restore noop-restore))
  (var loaded? false)
  (var connected-signals {})

  (fn disconnect-all-signals []
    (each [name conn (pairs connected-signals)]
      (conn.signal:disconnect conn.wrapped-handler true)
      (tset connected-signals name nil)))

  {:id id
   :module-name (or spec.module-name id)
   :parent-id spec.parent-id
   :source (or spec.source :user)
   :owned-paths (clone-list spec.owned-paths)
   :loaded? (fn [_self] loaded?)
   :load (fn [self ctx]
           (load-fn ctx)
           (set loaded? true))
   :unload (fn [self ctx]
             (disconnect-all-signals)
             (local (ok err) (pcall unload-fn ctx))
             (when ok
               (set loaded? false))
             (when (not ok)
               (error err)))
   :snapshot (fn [_self ctx]
               (snapshot-fn ctx))
   :restore (fn [_self state ctx]
              (restore-fn state ctx))
   :reload (fn [self ctx]
             (local state (self:snapshot ctx))
             (self:unload ctx)
             (self:load ctx)
             (self:restore state ctx))
   :connect-signal (fn [self name signal handler]
                     (when (. connected-signals name)
                       (error (.. "Signal " name " already connected on unit " id)))
                     (local wrapped (fn [payload] (handler payload)))
                     (signal:connect wrapped)
                     (tset connected-signals name {:signal signal :wrapped-handler wrapped})
                     true)
   :disconnect-signal (fn [self name]
                        (local conn (. connected-signals name))
                        (when (not conn)
                          (error (.. "Signal " name " not connected on unit " id)))
                        (conn.signal:disconnect conn.wrapped-handler true)
                        (tset connected-signals name nil)
                        true)})

(fn ModuleUnit [opts]
  (local options (or opts {}))
  (local module-name options.module-name)
  (assert (= (type module-name) :string)
          "ModuleUnit requires string :module-name")
  (local load-export (or options.load-export "init"))
  (local unload-export (or options.unload-export "drop"))
  (local explicit-snapshot? (not= (. options :snapshot-export) nil))
  (local explicit-restore? (not= (. options :restore-export) nil))
  (local snapshot-export (or options.snapshot-export "snapshot"))
  (local restore-export (or options.restore-export "restore"))
  (local suppress-run-main? (not (= options.suppress-run-main? false)))
  (local module-paths options.module-paths)
  (var owned-module-roots nil)
  (var loaded-owned-modules {})

  (fn loaded-or-required [name]
    (or (. package.loaded name)
        (require name)))

  (fn module-root-from-pattern [pattern]
    (if (string.match pattern "/%?%.fnl$")
        (string.sub pattern 1 (- (# pattern) 6))
        (string.match pattern "/%?/init%.fnl$")
        (string.sub pattern 1 (- (# pattern) 11))
        nil))

  (fn path-separator? [c]
    (or (= c "/") (= c "\\")))

  (fn path-under? [path root]
    (and path root
         (do
           (local path-len (# path))
           (local root-len (# root))
           (and (>= path-len root-len)
                (= (string.sub path 1 root-len) root)
                (or (= path-len root-len)
                    (path-separator? (string.sub path (+ root-len 1) (+ root-len 1))))))))

  (fn module-roots []
    (when (= owned-module-roots nil)
      (set owned-module-roots [])
      (when module-paths
        (local fs (loaded-or-required :fs))
        (each [pattern (string.gmatch module-paths "[^;]+")]
          (local root (module-root-from-pattern pattern))
          (when root
            (table.insert owned-module-roots (fs.absolute root))))))
    owned-module-roots)

  (fn owned-module-path? [path]
    (when path
      (local fs (loaded-or-required :fs))
      (local abs-path (fs.absolute path))
      (var matched? false)
      (each [_ root (ipairs (module-roots)) &until matched?]
        (when (path-under? abs-path root)
          (set matched? true)))
      matched?))

  (fn module-source-path [name]
    (local fennel (loaded-or-required :fennel))
    (local old-fennel-path fennel.path)
    (when module-paths
      (set fennel.path (.. module-paths ";" fennel.path)))
    (local (ok path) (pcall fennel.search-module name))
    (when module-paths
      (set fennel.path old-fennel-path))
    (if ok path nil))

  (fn remember-owned-module! [name]
    (when (and (= (type name) :string))
      (local source-path (module-source-path name))
      (when (owned-module-path? source-path)
        (tset loaded-owned-modules name source-path))))

  (fn clear-owned-loaded-modules! []
    (each [name source-path (pairs loaded-owned-modules)]
      (tset package.loaded name nil)
      (when source-path
        (local (ok-main main-mod) (pcall require :main))
        (when (and ok-main main-mod main-mod.clear-fennel-module-cache!)
          (pcall main-mod.clear-fennel-module-cache! name source-path)))
      (tset loaded-owned-modules name nil))
    true)

  (fn with-module-paths [f]
    (local fennel (loaded-or-required :fennel))
    (local old-fennel-path fennel.path)
    (local original-require _G.require)
    (when module-paths
      (set fennel.path (.. module-paths ";" fennel.path)))
    (when module-paths
      (set _G.require
           (fn [name]
             (local result (original-require name))
             (remember-owned-module! name)
             result)))
    (local (ok result) (pcall f))
    (when module-paths
      (set _G.require original-require))
    (when module-paths
      (set fennel.path old-fennel-path))
    (if ok result (error result)))

  (fn require-module []
    (loaded-or-required :fs)
    (local previous (and app app.__suppress-main-run?))
    (when app
      (set app.__suppress-main-run? suppress-run-main?))
    (local (ok result) (pcall with-module-paths #(require module-name)))
    (when app
      (set app.__suppress-main-run? previous))
    (if ok
        (do
          (remember-owned-module! module-name)
          result)
        (error result)))

  (fn call-handler [handler-name handler args]
    (local (ok result)
      (pcall
        (fn []
          (with-module-paths #(if (= args nil) (handler) (handler args))))))
    (when (not ok)
      (error (.. "Unit module " module-name " export " handler-name " error: " result)))
    result)

  (fn call-export [export-name args]
    (local module (require-module))
    (assert (= (type module) :table)
            (.. "Unit module " module-name " did not return a table"))
    (local handler (. module export-name))
    (assert (= (type handler) :function)
            (.. "Unit module " module-name " missing function " export-name))
    (call-handler export-name handler args))

  (fn call-optional-export [export-name args]
    (when export-name
      (local module (require-module))
      (local handler (. module export-name))
      (when (= (type handler) "function")
        (call-handler export-name handler args))))

  (local self (Unit {:id (or options.id module-name)
                      :module-name module-name
                      :parent-id options.parent-id
                      :source options.source
                      :owned-paths options.owned-paths
                      :load (fn [_ctx]
                               (call-export load-export nil))
                      :unload (fn [_ctx]
                                (call-export unload-export nil)
                                (clear-owned-loaded-modules!))
                      :snapshot (fn [_ctx]
                                  (if explicit-snapshot?
                                      (call-export snapshot-export nil)
                                      (do
                                        (local result (call-optional-export snapshot-export nil))
                                        (if (= result nil) nil result))))
                      :restore (fn [state _ctx]
                                 (if explicit-restore?
                                     (call-export restore-export state)
                                     (do
                                       (local result (call-optional-export restore-export state))
                                       (if (= result nil) true result))))}))
  (tset self :force-purge-module-cache! (fn [_self] (clear-owned-loaded-modules!)))
  (tset self :load-export load-export)
  (tset self :unload-export unload-export)
  (tset self :snapshot-export snapshot-export)
  (tset self :restore-export restore-export)
  self)

(fn SourceUnit [opts]
  (local options (or opts {}))
  (local id (assert options.id "SourceUnit requires :id"))
  (local source (assert options.source "SourceUnit requires :source"))
  (local load-export (or options.load-export "init"))
  (local unload-export (or options.unload-export "drop"))
  (local snapshot-export options.snapshot-export)
  (local restore-export options.restore-export)
  (local fennel-path options.fennel-path)
  (var module-table nil)

  (fn eval-source []
    (local fennel (require :fennel))
    (local old-fennel-path fennel.path)
    (when fennel-path
      (set fennel.path fennel-path))
    (local (ok lua-source) (pcall fennel.compile-string source {:filename id}))
    (when fennel-path
      (set fennel.path old-fennel-path))
    (when (not ok)
      (error (.. "SourceUnit " id " compile error: " lua-source)))
    (local (chunk err) (load lua-source id :t))
    (when (not chunk)
      (error (.. "SourceUnit " id " eval error: " (or err "unknown"))))
    (local (eval-ok result) (pcall chunk))
    (when (not eval-ok)
      (error (.. "SourceUnit " id " runtime error: " result)))
    (set module-table (if (= (type result) :table) result {})))

  (fn ensure-module []
    (when (not module-table)
      (eval-source))
    module-table)

  (fn clear-module []
    (set module-table nil))

  (fn call-export [export-name args]
    (when export-name
      (local module (ensure-module))
      (assert (= (type module) :table)
              (.. "SourceUnit " id " did not return a table"))
      (local handler (. module export-name))
      (assert (= (type handler) :function)
              (.. "SourceUnit " id " missing function " export-name))
      (if (= args nil)
          (handler)
          (handler args))))

  (local self (Unit {:id id
                      :parent-id options.parent-id
                      :source (or options.source-type :user)
                      :owned-paths (clone-list options.owned-paths)
                      :load (fn [_ctx]
                              (call-export load-export nil))
                      :unload (fn [_ctx]
                                (call-export unload-export nil)
                                (clear-module))
                      :snapshot (fn [_ctx]
                                  (when snapshot-export
                                    (call-export snapshot-export nil)))
                      :restore (fn [state _ctx]
                                 (when restore-export
                                   (call-export restore-export state))
                                 true)}))
  (tset self :force-purge-module-cache! (fn [_self] (clear-module)))
  self)

{:Unit Unit
 :ModuleUnit ModuleUnit
 :SourceUnit SourceUnit}
