(local StringUtils (require :string-utils))

(local fuzzy-match StringUtils.fuzzy-match)

(local join-path
  (fn [a b]
    (if (or (= a "") (= (string.sub a -1) "/"))
        (.. a b)
        (.. a "/" b))))

(fn normalize-name [value]
  (local name (tostring (or value "")))
  (if (> (# name) 0)
      name
      nil))

(fn normalize-launchable [entry]
  (assert (= (type entry) :table) "Launcher expects launchable tables")
  (local name (normalize-name (or entry.name (. entry 1))))
  (assert name "Launchable requires a non-empty :name")
  (local run (or entry.run entry.fn (. entry 2)))
  (assert (= (type run) :function) (.. "Launchable " name " requires a :run function"))
  {:name name
   :run run})

(fn Launcher [_opts]
  (local fennel (require :fennel))

  (fn load-launchables []
    (local fs (require :fs))
    (assert (and app app.engine app.engine.get-asset-path)
            "Launcher requires app.engine.get-asset-path to load launchables")
    (assert (and fs fs.list-dir) "Launcher requires fs.list-dir to load launchables")
    (local dir (app.engine.get-asset-path "lua/launchables"))
    (local (ok dir-entries) (pcall fs.list-dir dir false))
    (if (not ok)
        (error (.. "Launcher failed to list launchables: " dir-entries)))
    (local items [])
    (each [_ entry (ipairs dir-entries)]
      (when (and entry entry.is-file entry.name (string.match entry.name "%.fnl$"))
        (local path (join-path dir entry.name))
        (local loaded (fennel.dofile path))
        (local launchable (if (= (type loaded) :function) (loaded) loaded))
        (table.insert items (normalize-launchable launchable))))
    items)

  (fn list-launchables []
    (local by-name {})
    (each [_ launchable (ipairs (load-launchables))]
      (when (. by-name launchable.name)
        (error (.. "Launchable already registered: " launchable.name)))
      (set (. by-name launchable.name) launchable))
    (local items [])
    (each [_ value (pairs by-name)]
      (table.insert items value))
    (table.sort items
                (fn [a b]
                  (< (string.lower a.name)
                     (string.lower b.name))))
    {:items items
     :by-name by-name})

  (fn list [_self]
    (local result (list-launchables))
    result.items)

  (fn search [self query]
    (local q (or query ""))
    (icollect [_ entry (ipairs (self:list))]
      (when (fuzzy-match q entry.name)
        entry)))

  (fn get [_self name]
    (local key (normalize-name name))
    (if key
        (do
          (local result (list-launchables))
          (. result.by-name key))
        nil))

  (fn run [self entry]
    (local launchable
      (if (and (= (type entry) :table) entry.name entry.run)
          entry
          (self:get entry)))
    (assert launchable "Launcher.run requires a launchable")
    (launchable.run)
    nil)

  {:list list
   :search search
   :get get
   :run run})

(local exports {:Launcher Launcher})

(setmetatable exports
              {:__call (fn [_ ...]
                         (Launcher ...))})

exports
