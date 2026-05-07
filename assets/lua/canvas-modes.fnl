(global app (or app {}))

(local Signal (require :signal))

(local persisted-mode-migrations {})

(fn clone-list [items]
  (icollect [_ item (ipairs (or items []))]
    item))

(fn noop-deactivate [_ctx _session]
  true)

(fn noop-snapshot [_ctx _session]
  nil)

(fn noop-restore [_ctx _session _state]
  true)

(fn ensure-registry []
  (when (not app.canvas-mode-registry)
    (set app.canvas-mode-registry
         {:modes {}
          :ordered-ids []
          :active-mode-id nil
          :active-mode-spec nil
          :active-mode-session nil}))
  app.canvas-mode-registry)

(fn mode-registered? [mode-id]
  (local registry (ensure-registry))
  (and (= (type mode-id) :string)
       (not (= mode-id ""))
       (. registry.modes mode-id)))

(fn clear-mode-runtime-hooks! []
  (set app.canvas-mode-root-actions nil)
  (set app.canvas-mode-selection-actions nil)
  (set app.canvas-mode-left-dock-builder nil)
  (set app.canvas-mode-command-hints-provider nil)
  (set app.canvas-mode-delete-selection nil)
  (set app.canvas-mode-activate-focused nil)
  (set app.canvas-mode-drawing-enabled? nil)
  (set app.canvas-mode-context-enricher nil)
  (set app.canvas-mode-input-handlers nil)
  (set app.canvas-mode-target-enabled? nil)
  (set app.canvas-mode-update nil)
  true)

(fn empty-mode-hooks []
  {:root-actions nil
   :selection-actions nil
   :left-dock-builder nil
   :command-hints-provider nil
   :delete-selection nil
   :activate-focused nil
   :drawing-enabled? nil
   :context-enricher nil
   :input-handlers nil
   :target-enabled? nil
   :update nil})

(fn apply-mode-hooks! [hook-state]
  (local hooks (or hook-state (empty-mode-hooks)))
  (set app.canvas-mode-root-actions hooks.root-actions)
  (set app.canvas-mode-selection-actions hooks.selection-actions)
  (set app.canvas-mode-left-dock-builder hooks.left-dock-builder)
  (set app.canvas-mode-command-hints-provider hooks.command-hints-provider)
  (set app.canvas-mode-delete-selection hooks.delete-selection)
  (set app.canvas-mode-activate-focused hooks.activate-focused)
  (set app.canvas-mode-drawing-enabled? hooks.drawing-enabled?)
  (set app.canvas-mode-context-enricher hooks.context-enricher)
  (set app.canvas-mode-input-handlers hooks.input-handlers)
  (set app.canvas-mode-target-enabled? hooks.target-enabled?)
  (set app.canvas-mode-update hooks.update)
  true)

(fn sync-app-active-mode! [mode-id]
  (set app.active-canvas-mode mode-id)
  (when app.active-world-runtime
    (set app.active-world-runtime.active-canvas-mode mode-id))
  true)

(fn ensure-modes-changed-signal []
  (set app.canvas-modes-changed (or app.canvas-modes-changed (Signal)))
  app.canvas-modes-changed)

(fn emit-modes-changed! [payload]
  (when app.canvas-modes-changed
    (app.canvas-modes-changed:emit payload))
  true)

(fn assert-mode-spec-shape! [mode-spec]
  (local mode-id (assert (. mode-spec :id) "Canvas mode spec requires :id"))
  (assert (= (type mode-id) :string)
          (.. "Canvas mode id must be a string, got " (type mode-id)))
  (when (= (. mode-spec :show-in-sidebar?) true)
    (assert (. mode-spec :icon)
            (.. "Canvas mode " mode-id " requires :icon when shown in sidebar"))
    (assert (. mode-spec :button-name)
            (.. "Canvas mode " mode-id " requires :button-name when shown in sidebar"))
    (assert (. mode-spec :label)
            (.. "Canvas mode " mode-id " requires :label when shown in sidebar")))
  (assert (= (type (or (. mode-spec :activate) (fn [] true))) :function)
          (.. "Canvas mode " mode-id " requires :activate function"))
  mode-spec)

(fn mode-context [mode-spec opts]
  (local options (or opts {}))
  (local staged-hooks options.staged-hooks)
  (local staged-cleanup options.staged-cleanup)
  (fn set-staged-hook! [key value]
    (assert staged-hooks "Canvas mode hook staging is only available during activation")
    (set (. staged-hooks key) value)
    value)
  (fn defer-cleanup! [cleanup]
    (assert staged-cleanup "Canvas mode cleanup staging is only available during activation")
    (assert (= (type cleanup) :function)
            (.. "Canvas mode cleanup must be a function, got " (type cleanup)))
    (table.insert staged-cleanup cleanup)
    cleanup)
  {:mode mode-spec
   :defer-cleanup! (fn [_self cleanup] (defer-cleanup! cleanup))
   :clear-runtime-hooks! clear-mode-runtime-hooks!
   :set-root-actions! (fn [_self value] (set-staged-hook! :root-actions value))
   :set-selection-actions! (fn [_self value] (set-staged-hook! :selection-actions value))
   :set-left-dock-builder! (fn [_self value] (set-staged-hook! :left-dock-builder value))
   :set-command-hints-provider! (fn [_self value] (set-staged-hook! :command-hints-provider value))
   :set-delete-selection! (fn [_self value] (set-staged-hook! :delete-selection value))
   :set-activate-focused! (fn [_self value] (set-staged-hook! :activate-focused value))
   :set-drawing-enabled! (fn [_self value]
                           (set-staged-hook! :drawing-enabled? (and value true)))
   :set-context-enricher! (fn [_self value] (set-staged-hook! :context-enricher value))
   :set-input-handlers! (fn [_self value] (set-staged-hook! :input-handlers value))
   :set-target-enabled! (fn [_self value] (set-staged-hook! :target-enabled? value))
   :set-update! (fn [_self value] (set-staged-hook! :update value))})

(fn run-cleanup-stack! [cleanup-stack]
  (for [i (length (or cleanup-stack [])) 1 -1]
    ((. cleanup-stack i)))
  true)

(fn make-active-session [user-session cleanup-stack]
  {:user-session user-session
   :cleanup cleanup-stack})

(fn active-user-session [mode-session]
  (if (and (= (type mode-session) :table)
           (not (= (. mode-session :cleanup) nil))
           (= (type mode-session.cleanup) :table))
      mode-session.user-session
      mode-session))

(fn active-session-cleanup [mode-session]
  (if (and (= (type mode-session) :table)
           (= (type mode-session.cleanup) :table))
      mode-session.cleanup
      []))

(fn active-mode-spec []
  (and (ensure-registry) app.canvas-mode-registry.active-mode-spec))

(fn active-mode-id []
  (and (ensure-registry) app.canvas-mode-registry.active-mode-id))

(fn active-mode-session []
  (and (ensure-registry) app.canvas-mode-registry.active-mode-session))

(fn snapshot-mode-state [mode-spec mode-session]
  ((or (. mode-spec :snapshot) noop-snapshot)
   (mode-context mode-spec)
   (active-user-session mode-session)))

(fn deactivate-active-mode []
  (local registry (ensure-registry))
  (local mode-spec registry.active-mode-spec)
  (local mode-session registry.active-mode-session)
  (when mode-spec
    ((or (. mode-spec :deactivate) noop-deactivate)
     (mode-context mode-spec)
     (active-user-session mode-session))
    (run-cleanup-stack! (active-session-cleanup mode-session)))
  (apply-mode-hooks! nil)
  (set registry.active-mode-id nil)
  (set registry.active-mode-spec nil)
  (set registry.active-mode-session nil)
  (sync-app-active-mode! nil)
  true)

(fn register-mode [mode-spec]
  (local registry (ensure-registry))
  (local spec (assert-mode-spec-shape! mode-spec))
  (local mode-id (. spec :id))
  (assert (not (. registry.modes mode-id))
          (.. "Duplicate canvas mode id: " mode-id))
  (set (. registry.modes mode-id) spec)
  (table.insert registry.ordered-ids mode-id)
  (ensure-modes-changed-signal)
  (emit-modes-changed! {:reason :registered
                        :mode-id mode-id})
  spec)

(fn resolve [mode-id]
  (if (= mode-id nil)
      nil
      (do
        (assert (= (type mode-id) :string)
                (.. "Canvas mode id must be a string, got " (type mode-id)))
        (assert (mode-registered? mode-id)
                (.. "Unknown canvas mode: " mode-id))
        mode-id)))

(fn unregister-mode [mode-id]
  (local registry (ensure-registry))
  (local resolved-id (if (= mode-id nil) nil (resolve mode-id)))
  (when (and resolved-id (= registry.active-mode-id resolved-id))
    (deactivate-active-mode))
  (set (. registry.modes resolved-id) nil)
  (local remaining [])
  (each [_ existing-id (ipairs registry.ordered-ids)]
    (when (not (= existing-id resolved-id))
      (table.insert remaining existing-id)))
  (set registry.ordered-ids remaining)
  (emit-modes-changed! {:reason :unregistered
                        :mode-id resolved-id})
  true)

(fn spec [mode-id]
  (if (= mode-id nil)
      nil
      (do
        (local registry (ensure-registry))
        (. registry.modes (resolve mode-id)))))

(fn mode-specs-in-order []
  (local registry (ensure-registry))
  (icollect [_ mode-id (ipairs registry.ordered-ids)]
    (. registry.modes mode-id)))

(fn sidebar-mode-specs []
  (local sidebar-modes [])
  (each [_ mode-spec (ipairs (mode-specs-in-order))]
    (when (= (and mode-spec (. mode-spec :show-in-sidebar?)) true)
      (table.insert sidebar-modes mode-spec)))
  sidebar-modes)

(fn matches-id? [mode-id expected-id]
  (if (or (= mode-id nil)
          (= expected-id nil))
      (= mode-id expected-id)
      (= (resolve mode-id) (resolve expected-id))))

(fn restore-previous-mode! [registry previous-id previous-spec previous-state]
  (if previous-spec
      (do
        (local staged-hooks (empty-mode-hooks))
        (local staged-cleanup [])
        (local previous-session
          ((or (. previous-spec :activate) (fn [_ctx] nil))
           (mode-context previous-spec
                         {:staged-hooks staged-hooks
                          :staged-cleanup staged-cleanup})))
        (apply-mode-hooks! staged-hooks)
        (set registry.active-mode-id previous-id)
        (set registry.active-mode-spec previous-spec)
        (set registry.active-mode-session (make-active-session previous-session staged-cleanup))
        (sync-app-active-mode! previous-id)
        ((or (. previous-spec :restore) noop-restore)
         (mode-context previous-spec)
         previous-session
         previous-state)
         previous-session)
      (do
        (set registry.active-mode-id nil)
        (set registry.active-mode-spec nil)
        (set registry.active-mode-session nil)
        (apply-mode-hooks! nil)
        (sync-app-active-mode! nil)
        nil)))

(fn activate-mode [mode-id]
  (local registry (ensure-registry))
  (local resolved-id (resolve mode-id))
  (local previous-id registry.active-mode-id)
  (local previous-spec registry.active-mode-spec)
  (if (= resolved-id nil)
      (do
        (deactivate-active-mode)
        nil)
      (do
        (local next-spec (. registry.modes resolved-id))
        (local previous-state
          (if previous-spec
              (snapshot-mode-state previous-spec registry.active-mode-session)
              nil))
        (if (and previous-id
                 (= previous-id resolved-id)
                 registry.active-mode-session)
            registry.active-mode-session
            (do
              (deactivate-active-mode)
              (apply-mode-hooks! nil)
              (local staged-hooks (empty-mode-hooks))
              (local staged-cleanup [])
              (local (ok mode-session-or-err)
                (pcall
                  (fn []
                    ((or (. next-spec :activate) (fn [_ctx] nil))
                     (mode-context next-spec
                                   {:staged-hooks staged-hooks
                                    :staged-cleanup staged-cleanup})))))
              (if ok
                  (do
                    (apply-mode-hooks! staged-hooks)
                    (set registry.active-mode-id resolved-id)
                    (set registry.active-mode-spec next-spec)
                    (set registry.active-mode-session
                         (make-active-session mode-session-or-err staged-cleanup))
                    (sync-app-active-mode! resolved-id)
                    mode-session-or-err)
                  (do
                    (run-cleanup-stack! staged-cleanup)
                    (apply-mode-hooks! nil)
                    (local (rollback-ok rollback-session-or-err)
                      (pcall restore-previous-mode!
                             registry
                             previous-id
                             previous-spec
                             previous-state))
                    (if rollback-ok
                        (error (.. "Canvas mode activation failed for "
                                   resolved-id
                                   ": "
                                   mode-session-or-err))
                        (error (.. "Canvas mode activation failed for "
                                   resolved-id
                                   ": "
                                   mode-session-or-err
                                   " (rollback failed: "
                                   rollback-session-or-err
                                   ")"))))))))))

(fn snapshot-active-mode []
  (local registry (ensure-registry))
  (if registry.active-mode-spec
      ((or (. registry.active-mode-spec :snapshot) noop-snapshot)
       (mode-context registry.active-mode-spec)
       registry.active-mode-session)
      nil))

(fn restore-active-mode [state]
  (local registry (ensure-registry))
  (if registry.active-mode-spec
      ((or (. registry.active-mode-spec :restore) noop-restore)
       (mode-context registry.active-mode-spec)
       (active-user-session registry.active-mode-session)
       state)
      true))

(fn normalize-persisted [mode-id]
  (if (= mode-id nil)
      (values nil false nil)
      (if (and (= (type mode-id) :string)
               (> (# mode-id) 0))
          (do
            (local migrated (. persisted-mode-migrations mode-id))
            (if migrated
                (values migrated
                        true
                        (.. "migrating persisted canvas.active_mode from "
                            (tostring mode-id)
                            " to "
                            migrated))
                (values mode-id false nil)))
          (values nil
                  true
                  (.. "invalid persisted canvas.active_mode "
                      (tostring mode-id)
                      "; clearing to nil")))))

{:clear-mode-runtime-hooks! clear-mode-runtime-hooks!
 :ensure-registry ensure-registry
 :ensure-modes-changed-signal ensure-modes-changed-signal
 :register-mode register-mode
 :mode-registered? mode-registered?
 :unregister-mode unregister-mode
 :resolve resolve
 :spec spec
 :mode-specs-in-order mode-specs-in-order
 :sidebar-mode-specs sidebar-mode-specs
 :matches-id? matches-id?
 :activate-mode activate-mode
 :deactivate-active-mode deactivate-active-mode
 :active-mode-id active-mode-id
 :active-mode-spec active-mode-spec
 :active-mode-session active-mode-session
 :snapshot-active-mode snapshot-active-mode
 :restore-active-mode restore-active-mode
 :normalize-persisted normalize-persisted}
