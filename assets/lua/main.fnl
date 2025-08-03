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

(fn Rectangle [opts]
  (set opts.color (or opts.color (glm.vec4:new 1 0 0 1)))
  (set opts.position (or opts.position (glm.vec3:new 0)))
  (set opts.size (or opts.size (glm.vec2:new 10)))
  (set opts.rotation (or opts.rotation (glm.quat:new 1 0 0 0)))
  (set opts.depth-offset-index (or opts.depth-offset-index 0))

  (fn build [self ctx]
    (local handle (ctx.triangle-vector:allocate (* 8 3 2)))

    (fn update [self]
      (local verts [[0 0 0] [0 opts.size.y 0] [opts.size.x opts.size.y 0]
                    [opts.size.x opts.size.y 0] [opts.size.x 0 0] [0 0 0]])
      (for [i 1 6]
        (ctx.triangle-vector:set_vec3
          handle
          (* (- i 1) 8)
          (+ (opts.rotation:rotate (glm.vec3:new (table.unpack (. verts i))))
             opts.position))
        (ctx.triangle-vector:set_vec4 handle (+ (* (- i 1) 8) 3) opts.color)
        (ctx.triangle-vector:set_float handle (+ (* (- i 1) 8) 7) opts.depth-offset-index)
        )
      )

    (fn drop [self]
      (ctx.triangle-vector:delete handle))

    {: update
     : drop}
    )

  {: opts
   : build})

(fn space.init []
  (let [world-entity (Entity:get "021cb530-ae60-47f3-a322-64383f850a05")
        world-entity-func (fennel.eval world-entity.code-str)]
    (set space.world (world-entity-func (G:make-this world-entity))))
  (local vb space.world.renderers.scene-triangle-vector)
  (local h (vb:allocate (* 8 3)))
  (vb:set_vec4 h 3 (glm.vec4:new 1 0 0 1))
  (vb:set_vec4 h 11 (glm.vec4:new 0 1 0 1))
  (vb:set_vec4 h 19 (glm.vec4:new 0 0 1 1))

  (vb:set_vec3 h 0 (glm.vec3:new -5 -5 0))
  (vb:set_vec3 h 8 (glm.vec3:new 5 -5 0))
  (vb:set_vec3 h 16 (glm.vec3:new 0 0 0))

  (local r (Rectangle {}))
  (local rr (r:build {:triangle-vector vb}))
  (rr:update)
  )

(fn space.update [delta]
  (space.world:update delta)
  )

(fn space.drop []
  (space.world:drop)
  )
