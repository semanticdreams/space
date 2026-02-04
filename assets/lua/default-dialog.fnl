(local Dialog (require :dialog))

(fn DefaultDialog [opts]
  (local options (or opts {}))

  (fn copy-table [source]
    (local clone {})
    (when source
      (each [k v (pairs source)]
        (set (. clone k) v)))
    clone)

  (fn build [ctx runtime-opts]
    (var dialog nil)
    (var closed? false)
    (local build-opts {})
    (local incoming (or runtime-opts {}))
    (local base-runtime-opts (copy-table incoming))
    (set base-runtime-opts.on-close nil)
    (set base-runtime-opts.actions nil)
    (local parent-target ctx.pointer-target)

    (fn resolve-target [target]
      (if (and app.hud (= target app.hud))
          app.hud
          (if (and app.scene (= target app.scene))
              app.scene
              (if target target nil))))

    (fn resolve-destination [current]
      (if (and current (= current app.hud))
          app.scene
          (if (and current (= current app.scene))
              app.hud
              (or app.hud app.scene))))

    (fn detach-from-target [target]
      (var removed false)
      (local target-element (or dialog.__scene_wrapper dialog))
      (if (and target target.remove-panel-child target-element)
          (set removed (target:remove-panel-child target-element))
          (when (and dialog dialog.drop)
            (dialog:drop)
            (set removed true)))
      (when (and (not removed) dialog dialog.drop)
        (dialog:drop))
      removed)

    (fn attach-to-target [target]
      (when (and target target.add-panel-child)
        (target:add-panel-child {:builder (DefaultDialog options)
                                :builder-options (copy-table base-runtime-opts)})))

    (each [key value (pairs options)]
      (when (and (not (= key :actions))
                 (not (= key :on-close)))
        (set (. build-opts key) value)))
    (each [key value (pairs incoming)]
      (when (and (not (= key :actions))
                 (not (= key :on-close)))
        (set (. build-opts key) value)))

    (local combined-actions [])
    (each [_ action (ipairs (or options.actions []))]
      (table.insert combined-actions action))
    (each [_ action (ipairs (or incoming.actions []))]
      (table.insert combined-actions action))

    (local user-on-close (or incoming.on-close options.on-close))
    (fn handle-close [button event]
      (when (not closed?)
        (set closed? true)
        (when user-on-close
          (user-on-close dialog button event))
        (when (and (not user-on-close) dialog)
          (dialog:drop))))

    (fn handle-toggle [_button _event]
      (when (and (not closed?) dialog)
        (local current (or (resolve-target dialog.__parent_target)
                           (resolve-target parent-target)
                           app.scene
                           app.hud))
        (local destination (resolve-destination current))
        (when destination
          (detach-from-target current)
          (set dialog (attach-to-target destination)))))

    (table.insert combined-actions
                  {:name "toggle scene-hud"
                   :icon "move_item"
                   :on-click handle-toggle})
    (table.insert combined-actions {:name "close"
                                    :icon "close"
                                    :on-click handle-close})
    (set build-opts.actions combined-actions)

    (local builder (Dialog build-opts))
    (set dialog (builder ctx))
    (set dialog.__parent_target (resolve-target parent-target))
    dialog))

DefaultDialog
