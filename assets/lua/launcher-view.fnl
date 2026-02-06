(local DefaultDialog (require :default-dialog))
(local SearchView (require :search-view))
(local Launcher (require :launcher))

(fn normalize-launchables [items]
  (local pairs [])
  (each [_ entry (ipairs (or items []))]
    (when entry
      (local name (tostring (or entry.name entry)))
      (table.insert pairs [entry name])))
  pairs)

(fn LauncherView [opts]
  (local options (or opts {}))

  (fn build [ctx runtime-opts]
    (local incoming (or runtime-opts {}))
    (local user-on-close (or incoming.on-close options.on-close))
    (local user-on-submit (or incoming.on-submit options.on-submit))
    (local registry (Launcher {}))

    (local search
      ((SearchView {:items []
                    :name (or options.search-name "launcher-search")
                    :placeholder (or options.placeholder "Search launchables")
                    :items-per-page (or options.items-per-page 12)
                    :scrollbar-policy :as-needed})
       ctx))

    (local submitted-handler
      (search.submitted:connect
        (fn [pair]
          (local entry (and pair (. pair 1)))
          (if user-on-submit
              (user-on-submit entry)
              (when entry
                (registry:run entry))))))

    (local dialog
      ((DefaultDialog {:title (or options.title "Launcher")
                       :name (or options.name "launcher-dialog")
                       :on-close user-on-close
                       :child (fn [_] search)})
       ctx))

    (set dialog.search search)
    (set dialog.set-items
         (fn [_self items]
           (search:set-items (normalize-launchables items))))
    (set dialog.set-query
         (fn [_self query]
           (when (and search search.input search.input.model search.input.model.set-text)
             (search.input.model:set-text (or query "")))))
    (search:set-items (normalize-launchables (registry:list)))
    (local base-drop dialog.drop)
    (set dialog.drop
         (fn [self]
           (when submitted-handler
             (search.submitted:disconnect submitted-handler true))
           (when base-drop
             (base-drop self))))
    dialog)

  build)

(local exports {:LauncherView LauncherView})

(setmetatable exports
              {:__call (fn [_ ...]
                         (LauncherView ...))})

exports
