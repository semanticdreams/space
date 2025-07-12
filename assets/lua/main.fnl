(local fennel (require :fennel))
(fn _G.pp [x] (print (fennel.view x)))

;(local test (require :test))
;(test.hello)

(local sqlite (require :lsqlite3))

(fn get-db []
  (local db_path (space.join_path space.data_dir "space.db"))
  (sqlite.open db_path))

(fn get-entities-by-type [type]
  (let [db (get-db)
        stmt (db:prepare "select * from entities where type = ?")
        rows []]
    (stmt:bind 1 type)
    (while (= (stmt:step) sqlite.ROW)
      (table.insert rows (stmt:get_named_values)))
    (stmt:finalize)
    rows))

(fn get-entity [id]
  (let [db (get-db)
        stmt (db:prepare "select * from entities where id = ?")]
    (stmt:bind 1 id)
    (assert (= (stmt:step) sqlite.ROW))
    (local result (stmt:get_named_values))
    (stmt:finalize)
    result))

(fn space.init []
  (let [world-entity (get-entity "021cb530-ae60-47f3-a322-64383f850a05")
        world-entity-code-str (json.loads (. world-entity :data))]
        (set space.world (fennel.eval world-entity-code-str)))
  (space.world.init)
  )

(fn space.update [delta]
  (space.world.update delta))

(fn space.drop []
  (space.world.drop)
  )