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
  {:id id
   :parent-id spec.parent-id
   :owned-paths (clone-list spec.owned-paths)
   :load (fn [_self ctx]
           (load-fn ctx))
   :unload (fn [_self ctx]
             (unload-fn ctx))
   :snapshot (fn [_self ctx]
               (snapshot-fn ctx))
   :restore (fn [_self state ctx]
              (restore-fn state ctx))
   :reload (fn [self ctx]
             (local state (self:snapshot ctx))
             (self:unload ctx)
             (self:load ctx)
             (self:restore state ctx))})

(fn ModuleUnit [opts]
  (local options (or opts {}))
  (local module-name (or options.module-name options.module_name))
  (assert (= (type module-name) :string)
          "ModuleUnit requires string :module-name")
  (local load-export (or options.load-export "init-app!"))
  (local unload-export (or options.unload-export "drop-app!"))
  (local snapshot-export (or options.snapshot-export "snapshot-app!"))
  (local restore-export (or options.restore-export "restore-app!"))
  (local suppress-run-main? (not (= options.suppress-run-main? false)))
  (local module-paths options.module-paths)

  (fn require-module []
    (local previous (and app app.__suppress-main-run?))
    (when app
      (set app.__suppress-main-run? suppress-run-main?))
    (local fennel (require :fennel))
    (local old-fennel-path fennel.path)
    (when module-paths
      (set fennel.path (.. module-paths ";" fennel.path)))
    (local (ok result) (pcall require module-name))
    (when module-paths
      (set fennel.path old-fennel-path))
    (when app
      (set app.__suppress-main-run? previous))
    (if ok
        result
        (error result)))

  (fn call-export [export-name args]
    (local module (require-module))
    (assert (= (type module) :table)
            (.. "Unit module " module-name " did not return a table"))
    (local handler (. module export-name))
    (assert (= (type handler) :function)
            (.. "Unit module " module-name " missing function " export-name))
    (if (= args nil)
        (handler)
        (handler args)))

  (Unit {:id (or options.id module-name)
         :parent-id options.parent-id
         :owned-paths options.owned-paths
         :load (fn [_ctx]
                 (call-export load-export nil))
         :unload (fn [_ctx]
                   (call-export unload-export nil))
         :snapshot (fn [_ctx]
                     (call-export snapshot-export nil))
         :restore (fn [state _ctx]
                    (call-export restore-export state))}))

(fn SourceUnit [opts]
  (local options (or opts {}))
  (local id (assert options.id "SourceUnit requires :id"))
  (local source (assert options.source "SourceUnit requires :source"))
  (local load-export (or options.load-export "init-app!"))
  (local unload-export (or options.unload-export "drop-app!"))
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

  (Unit {:id id
         :parent-id options.parent-id
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

{:Unit Unit
 :ModuleUnit ModuleUnit
 :SourceUnit SourceUnit}
