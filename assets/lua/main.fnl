(global fennel (require :fennel))

(global pp (fn [x] (print (fennel.view x))))

;(local test (require :test))
;(test.hello)

(local sqlite (require :lsqlite3))

(fn get-db []
  (local db_path (space.join_path space.data_dir "space.db"))
  (sqlite.open db_path))

(fn get-entities-by-type [entity-type]
  (let [db (get-db)
        stmt (db:prepare "select * from entities where type = ?")
        rows []]
    (stmt:bind 1 entity-type)
    (while (= (stmt:step) sqlite.ROW)
      (table.insert rows (stmt:get_named_values)))
    (stmt:finalize)
    rows))

(fn get-entity [id parse-data?]
  (let [db (get-db)
        stmt (db:prepare "select * from entities where id = ?")]
    (stmt:bind 1 id)
    (assert (= (stmt:step) sqlite.ROW))
    (local result (stmt:get_named_values))
    (stmt:finalize)
    (when parse-data?
      (set result.data (json.loads result.data)))
    result))

(local Entity
  {:entity-type-cls-map {}
   :register-cls (fn [self entity-type entity-cls]
          (set (. self.entity-type-cls-map entity-type) entity-cls))
   :get (fn [self entity-id]
          (let [entity (get-entity entity-id true)
                entity-cls (. self.entity-type-cls-map entity.type)]
            (entity-cls entity)))
          })

(global one (fn [val] (assert (= (length val) 1) val) (. val 1)))

(fn matches-filters? [target filters]
  (or
    (= filters nil)
    (each [k v (pairs filters)]
      (when (not (= (. target k) v))
        (lua "return false")))
    true))

(Entity:register-cls
  :graph
  (fn [entity]
    {:id entity.id
     :type entity.type
     :nodes entity.data.nodes
     :edges entity.data.edges
     :positions entity.data.positions
     :force-layout-params entity.data.force_layout_params
     :get-outgoing-edges (fn [self entity]
                           (icollect [_ v (ipairs self.edges)]
                                     (if (= v.source_id entity.id) v)))
     :graph-code-obj (fn [self node-entity]
                        (let [func (fennel.eval (. node-entity :code-str))
                              (ok? res) (xpcall func debug.traceback (self:make-this node-entity))]
                          (if ok? res (error res))))
     :get-children (fn [self node-entity filters]
                     (icollect [_ v (ipairs
                                      (self:get-outgoing-edges node-entity))]
                               (let [e (Entity:get v.target_id)]
                                 (if (matches-filters? e filters) e))))
     :get-child (fn [self node-entity filters]
                  (one (self:get-children node-entity filters)))
     :make-this (fn [self node-entity]
                  {:graph self
                   :node node-entity
                   :graph-code-obj-by-child-name (fn [self2 child-name]
                                                   (self:graph-code-obj (self2:get-child {:name child-name})))
                   :get-children (fn [self2 filters]
                                   (self:get-children node-entity filters))
                   :get-child (fn [self2 filters]
                                (self:get-child node-entity filters))})}))

(Entity:register-cls
  :string
  (fn [entity]
    {:id entity.id
     :type entity.type
     :value entity.data}))

(Entity:register-cls
  :code
  (fn [entity]
    {:id entity.id
     :type entity.type
     :name entity.data.name
     :code-str entity.data.code_str
     :lang entity.data.lang}))

(Entity:register-cls
  :shader
  (fn [entity]
    {:id entity.id
     :type entity.type
     :code-str entity.data.code_str
     :name entity.data.name}))

(global G (Entity:get "18"))

;(local W (Entity:get "021cb530-ae60-47f3-a322-64383f850a05"))
;(-> (G:make-this W) (: :get-children {:value "widgets"}) (pp))
;(-> G (. :force-layout-params) (pp))

(fn space.init []
  (let [world-entity (Entity:get "021cb530-ae60-47f3-a322-64383f850a05")
        world-entity-func (fennel.eval world-entity.code-str)]
    (set space.world (world-entity-func (G:make-this world-entity))))
  ;(local vb (VectorBuffer.new))
  ;(gl.bufferDataFromVectorBuffer vb gl.GL_ARRAY_BUFFER gl.GL_STATIC_DRAW)
  (space.world:init)
  (local triangle-shader space.world.renderers.triangles.shader)
  )

(fn space.update [delta]
  (space.world:update delta))

(fn space.drop []
  (space.world:drop)
  )
