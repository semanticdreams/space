(fn install [opts]
  (local query-methods opts.query-methods)
  (local create-table-methods opts.create-table-methods)
  (local create-index-methods opts.create-index-methods)
  (local create-view-methods opts.create-view-methods)
  (local table-methods opts.table-methods)

  (local copy-array opts.copy-array)
  (local clone-query opts.clone-query)
  (local wrap-expr opts.wrap-expr)
  (local and_ opts.and_)
  (local update-select-query opts.update-select-query)
  (local update-create-table-query opts.update-create-table-query)
  (local update-create-index-query opts.update-create-index-query)
  (local update-create-view-query opts.update-create-view-query)
  (local set-query-mt! opts.set-query-mt!)
  (local set-create-table-mt! opts.set-create-table-mt!)
  (local make-compile-state opts.make-compile-state)
  (local compile-query opts.compile-query)

  (local from opts.from)
  (local star opts.star)
  (local update opts.update)
  (local insert-into opts.insert-into)
  (local table* opts.table*)

  (set query-methods.select
    (fn [self ...]
      (assert (= self.kind :select) "select is only valid on select queries")
      (local terms (copy-array self._selects))
      (each [_ term (ipairs [...])]
        (table.insert terms (wrap-expr term)))
      (update-select-query self {:_selects terms})))
  (set query-methods.from_ (fn [self source] (self:from source)))
  (set query-methods.with_ (fn [self name subquery] (self:with name subquery)))

  (set query-methods.from
    (fn [self source]
      (update-select-query self {:_from source})))

  (set query-methods.with
    (fn [self name subquery]
      (local ctes (copy-array self._ctes))
      (table.insert ctes {:name name :query subquery})
      (update-select-query self {:_ctes ctes})))

  (set query-methods.with-recursive
    (fn [self]
      (assert (= self.kind :select) "with-recursive is only valid on select queries")
      (update-select-query self {:_with_recursive? true})))
  (set query-methods.with_recursive (fn [self] (self:with-recursive)))

  (set query-methods.delete
    (fn [self]
      (assert (= self.kind :select) "delete is only valid on select queries")
      (assert self._from "delete requires a source table")
      (local q0 {:__tag :query
                 :kind :delete
                 :_from self._from
                 :_where self._where
                 :_returning []})
      (set-query-mt! q0)))

  (set query-methods.distinct
    (fn [self]
      (update-select-query self {:_distinct? true})))

  (set query-methods.where
    (fn [self criterion]
      (if self._where
          (update-select-query self {:_where (and_ self._where criterion)})
          (update-select-query self {:_where (wrap-expr criterion)}))))

  (set query-methods.prewhere
    (fn [self criterion]
      (error "prewhere is not supported in sqlite sql-builder")))

  (set query-methods.having
    (fn [self criterion]
      (if self._having
          (update-select-query self {:_having (and_ self._having criterion)})
          (update-select-query self {:_having (wrap-expr criterion)}))))

  (set query-methods.group-by
    (fn [self ...]
      (local groups (copy-array self._group_by))
      (each [_ term (ipairs [...])]
        (table.insert groups (wrap-expr term)))
      (update-select-query self {:_group_by groups})))
  (set query-methods.groupby (fn [self ...] (self:group-by ...)))

  (set query-methods.order-by
    (fn [self ...]
      (local items (copy-array self._order_by))
      (each [_ term (ipairs [...])]
        (table.insert items term))
      (update-select-query self {:_order_by items})))
  (set query-methods.orderby (fn [self ...] (self:order-by ...)))

  (set query-methods.limit
    (fn [self value]
      (update-select-query self {:_limit value})))

  (set query-methods.offset
    (fn [self value]
      (update-select-query self {:_offset value})))

  (set query-methods.for-update
    (fn [self]
      (error "for-update is not supported in sqlite sql-builder")))
  (set query-methods.for_update (fn [self] (self:for-update)))

  (set query-methods.slice
    (fn [self start stop]
      (local off (or start 0))
      (local lim (if stop (math.max 0 (- stop off)) nil))
      (local next (update-select-query self {:_offset off}))
      (if lim
          (next:limit lim)
          next)))

  (set query-methods.use-index
    (fn [self ...]
      (error "use-index is not supported in sqlite sql-builder")))

  (set query-methods.force-index
    (fn [self ...]
      (error "force-index is not supported in sqlite sql-builder")))

  (set query-methods.with-totals
    (fn [self]
      (error "with-totals is not supported in sqlite sql-builder")))

  (set query-methods.rollup
    (fn [self ...]
      (error "rollup is not supported in sqlite sql-builder")))

  (local joiner-methods {})
  (fn make-joiner [query target kind]
    (setmetatable
      {:query query :target target :kind (or kind :inner)}
      {:__index joiner-methods}))

  (set joiner-methods.on
    (fn [self criterion]
      (self.query:join self.target criterion self.kind)))

  (set joiner-methods.using
    (fn [self ...]
      (self.query:join-using self.target [...] self.kind)))

  (set joiner-methods.cross
    (fn [self]
      (self.query:cross-join self.target)))

  (set query-methods.join
    (fn [self target on kind]
      (if (= on nil)
          (make-joiner self target kind)
          (do
            (local joins (copy-array self._joins))
            (table.insert joins {:kind (or kind :inner) :table target :on (wrap-expr on)})
            (update-select-query self {:_joins joins})))))

  (set query-methods.join-using
    (fn [self target fields kind]
      (local joins (copy-array self._joins))
      (table.insert joins {:kind (or kind :inner) :table target :using (copy-array (or fields []))})
      (update-select-query self {:_joins joins})))

  (set query-methods.inner-join (fn [self target on] (self:join target on :inner)))
  (set query-methods.inner_join (fn [self target on] (self:inner-join target on)))
  (set query-methods.left-join (fn [self target on] (self:join target on :left)))
  (set query-methods.left_join (fn [self target on] (self:left-join target on)))
  (set query-methods.left-outer-join (fn [self target on] (self:join target on :left_outer)))
  (set query-methods.left_outer_join (fn [self target on] (self:left-outer-join target on)))
  (set query-methods.right-join (fn [self target on] (self:join target on :right)))
  (set query-methods.right_join (fn [self target on] (self:right-join target on)))
  (set query-methods.right-outer-join (fn [self target on] (self:join target on :right_outer)))
  (set query-methods.right_outer_join (fn [self target on] (self:right-outer-join target on)))
  (set query-methods.outer-join (fn [self target on] (self:join target on :full_outer)))
  (set query-methods.outer_join (fn [self target on] (self:outer-join target on)))
  (set query-methods.full-outer-join (fn [self target on] (self:join target on :full_outer)))
  (set query-methods.full_outer_join (fn [self target on] (self:full-outer-join target on)))
  (set query-methods.hash-join (fn [self target on] (error "hash-join is not supported in sqlite sql-builder")))
  (set query-methods.hash_join (fn [self target on] (self:hash-join target on)))
  (set query-methods.cross-join
    (fn [self target]
      (local joins (copy-array self._joins))
      (table.insert joins {:kind :cross :table target})
      (update-select-query self {:_joins joins})))
  (set query-methods.cross_join (fn [self target] (self:cross-join target)))

  (set query-methods.union
    (fn [self other]
      (local ops (copy-array self._set_ops))
      (table.insert ops {:op :union :query other})
      (update-select-query self {:_set_ops ops})))

  (set query-methods.union-all
    (fn [self other]
      (local ops (copy-array self._set_ops))
      (table.insert ops {:op :union-all :query other})
      (update-select-query self {:_set_ops ops})))
  (set query-methods.union_all (fn [self other] (self:union-all other)))

  (set query-methods.intersect
    (fn [self other]
      (local ops (copy-array self._set_ops))
      (table.insert ops {:op :intersect :query other})
      (update-select-query self {:_set_ops ops})))

  (set query-methods.except
    (fn [self other]
      (local ops (copy-array self._set_ops))
      (table.insert ops {:op :except :query other})
      (update-select-query self {:_set_ops ops})))

  (set query-methods.except-of (fn [self other] (self:except other)))
  (set query-methods.except_of (fn [self other] (self:except other)))
  (set query-methods.minus (fn [self other] (self:except other)))

  (set query-methods.columns
    (fn [self ...]
      (assert (= self.kind :insert) "columns is only valid on insert queries")
      (local next (clone-query self))
      (set next._columns (copy-array [...]))
      (set-query-mt! next)))

  (set query-methods.values
    (fn [self ...]
      (assert (= self.kind :insert) "values is only valid on insert queries")
      (local next (clone-query self))
      (local rows (copy-array next._values_rows))
      (each [_ row (ipairs [...])]
        (if (and (= (type row) :table) (not row.__tag))
            (table.insert rows (icollect [_ v (ipairs row)] (wrap-expr v)))
            (table.insert rows [(wrap-expr row)])))
      (set next._values_rows rows)
      (set next._select_query nil)
      (set-query-mt! next)))

  (set query-methods.from-select
    (fn [self select-query]
      (assert (= self.kind :insert) "from-select is only valid on insert queries")
      (local next (clone-query self))
      (set next._values_rows [])
      (set next._select_query select-query)
      (set-query-mt! next)))
  (set query-methods.from_select (fn [self select-query] (self:from-select select-query)))

  (set query-methods.insert-or-replace
    (fn [self ...]
      (assert (= self.kind :insert) "insert-or-replace is only valid on insert queries")
      (self:replace ...)))
  (set query-methods.insert_or_replace (fn [self ...] (self:insert-or-replace ...)))

  (set query-methods.replace
    (fn [self ...]
      (assert (= self.kind :insert) "replace is only valid on insert queries")
      (local next (clone-query self))
      (local rows (copy-array next._values_rows))
      (each [_ row (ipairs [...])]
        (if (and (= (type row) :table) (not row.__tag))
            (table.insert rows (icollect [_ v (ipairs row)] (wrap-expr v)))
            (table.insert rows [(wrap-expr row)])))
      (set next._values_rows rows)
      (set next._insert_mode :replace)
      (set-query-mt! next)))

  (set query-methods.ignore
    (fn [self]
      (assert (= self.kind :insert) "ignore is only valid on insert queries")
      (local next (clone-query self))
      (if (not (= next._insert_mode :replace))
          (set next._insert_mode :ignore))
      (set-query-mt! next)))

  (set query-methods.set
    (fn [self field-name value]
      (assert (or (= self.kind :update) (= self.kind :insert)) "set is only valid on update and insert queries")
      (local next (clone-query self))
      (if (= self.kind :update)
          (do
            (local sets (copy-array next._sets))
            (table.insert sets {:field field-name :value (wrap-expr value)})
            (set next._sets sets))
          (do
            (assert next._on_conflict "insert:set requires on-conflict first")
            (assert (= next._on_conflict.action :do-update)
                    "insert:set requires on-conflict do-update mode")
            (local conflict
              {:target (copy-array (or next._on_conflict.target []))
               :action next._on_conflict.action
               :sets (copy-array (or next._on_conflict.sets []))
               :where next._on_conflict.where})
            (table.insert conflict.sets {:field field-name :value (wrap-expr value)})
            (set next._on_conflict conflict)))
      (set-query-mt! next)))

  (set query-methods.on-conflict
    (fn [self ...]
      (assert (= self.kind :insert) "on-conflict is only valid on insert queries")
      (local next (clone-query self))
      (set next._on_conflict {:target (copy-array [...]) :action nil :sets [] :where nil})
      (set-query-mt! next)))
  (set query-methods.on_conflict (fn [self ...] (self:on-conflict ...)))

  (set query-methods.do-nothing
    (fn [self]
      (assert (= self.kind :insert) "do-nothing is only valid on insert queries")
      (assert self._on_conflict "do-nothing requires on-conflict first")
      (local next (clone-query self))
      (set next._on_conflict
           {:target (copy-array (or self._on_conflict.target []))
            :action :do-nothing
            :sets []
            :where nil})
      (set-query-mt! next)))
  (set query-methods.do_nothing (fn [self] (self:do-nothing)))

  (set query-methods.do-update
    (fn [self]
      (assert (= self.kind :insert) "do-update is only valid on insert queries")
      (assert self._on_conflict "do-update requires on-conflict first")
      (local next (clone-query self))
      (set next._on_conflict
           {:target (copy-array (or self._on_conflict.target []))
            :action :do-update
            :sets (copy-array (or self._on_conflict.sets []))
            :where self._on_conflict.where})
      (set-query-mt! next)))
  (set query-methods.do_update (fn [self] (self:do-update)))

  (set query-methods.conflict-where
    (fn [self criterion]
      (assert (= self.kind :insert) "conflict-where is only valid on insert queries")
      (assert self._on_conflict "conflict-where requires on-conflict first")
      (assert (= self._on_conflict.action :do-update)
              "conflict-where requires on-conflict do-update mode")
      (local next (clone-query self))
      (set next._on_conflict
           {:target (copy-array (or self._on_conflict.target []))
            :action self._on_conflict.action
            :sets (copy-array (or self._on_conflict.sets []))
            :where (wrap-expr criterion)})
      (set-query-mt! next)))
  (set query-methods.conflict_where (fn [self criterion] (self:conflict-where criterion)))

  (set query-methods.returning
    (fn [self ...]
      (assert (or (= self.kind :insert) (= self.kind :update) (= self.kind :delete))
              "returning is only valid on insert/update/delete queries")
      (local next (clone-query self))
      (local terms (copy-array next._returning))
      (each [_ term (ipairs [...])]
        (table.insert terms (wrap-expr term)))
      (set next._returning terms)
      (set-query-mt! next)))

  (set query-methods.if-exists
    (fn [self]
      (assert (or (= self.kind :drop-table) (= self.kind :drop-view) (= self.kind :drop-index))
              "if-exists is only valid on drop queries")
      (local next (clone-query self))
      (set next.if-exists? true)
      (set-query-mt! next)))

  (set query-methods.compile
    (fn [self opts]
      (local state (make-compile-state opts))
      (local sql (compile-query self state))
      (if (= state.param-style :named)
          {:sql sql :params state.named}
          {:sql sql :params state.params})))
  (set query-methods.to-sql (fn [self opts] (self:compile opts)))
  (set query-methods.to-sql-string (fn [self opts] (. (self:compile opts) :sql)))

  (set create-table-methods.if-not-exists (fn [self] (update-create-table-query self {:if-not-exists? true})))
  (set create-table-methods.temporary (fn [self] (update-create-table-query self {:temporary? true})))
  (set create-table-methods.unlogged
    (fn [self]
      (error "unlogged is not supported in sqlite sql-builder")))
  (set create-table-methods.with-system-versioning
    (fn [self]
      (error "with-system-versioning is not supported in sqlite sql-builder")))
  (set create-table-methods.with_system_versioning
    (fn [self]
      (self:with-system-versioning)))

  (set create-table-methods.column
    (fn [self name type opts]
      (local options (or opts {}))
      (local next (clone-query self))
      (local columns (copy-array next._columns_def))
      (table.insert columns
        {:name name
         :type type
         :nullable? options.nullable?
         :default (if (= options.default nil) nil (wrap-expr options.default))
         :primary-key? (= options.primary-key? true)
         :autoincrement? (= options.autoincrement? true)
         :unique? (= options.unique? true)
         :check (if options.check (wrap-expr options.check) nil)
         :references options.references})
      (set next._columns_def columns)
      (set-create-table-mt! next)))

  (set create-table-methods.columns
    (fn [self ...]
      (var next self)
      (each [_ item (ipairs [...])]
        (if (and (= (type item) :table) (. item 1) (. item 2))
            (set next (next:column (. item 1) (. item 2)))
            (set next (next:column item nil))))
      next))

  (set create-table-methods.as-select
    (fn [self select-query]
      (local next (clone-query self))
      (set next.select-query select-query)
      (set-create-table-mt! next)))
  (set create-table-methods.period-for
    (fn [self name start-col end-col]
      (error "period-for is not supported in sqlite sql-builder")))
  (set create-table-methods.period_for
    (fn [self name start-col end-col]
      (self:period-for name start-col end-col)))

  (set create-table-methods.primary-key
    (fn [self ...]
      (local next (clone-query self))
      (local constraints (copy-array next._constraints))
      (table.insert constraints {:kind :primary-key :columns (copy-array [...])})
      (set next._constraints constraints)
      (set-create-table-mt! next)))
  (set create-table-methods.unique
    (fn [self ...]
      (local next (clone-query self))
      (local constraints (copy-array next._constraints))
      (table.insert constraints {:kind :unique :columns (copy-array [...])})
      (set next._constraints constraints)
      (set-create-table-mt! next)))
  (set create-table-methods.check
    (fn [self expr]
      (local next (clone-query self))
      (local constraints (copy-array next._constraints))
      (table.insert constraints {:kind :check :expr (wrap-expr expr)})
      (set next._constraints constraints)
      (set-create-table-mt! next)))

  (set create-table-methods.foreign-key
    (fn [self columns ref-table ref-columns opts]
      (local options (or opts {}))
      (local next (clone-query self))
      (local constraints (copy-array next._constraints))
      (table.insert constraints
        {:kind :foreign-key
         :columns (copy-array columns)
         :references {:table ref-table
                      :columns (copy-array ref-columns)
                      :on-delete options.on-delete
                      :on-update options.on-update}})
      (set next._constraints constraints)
      (set-create-table-mt! next)))

  (set create-table-methods.without-rowid (fn [self] (update-create-table-query self {:without-rowid? true})))
  (set create-table-methods.strict (fn [self] (update-create-table-query self {:strict? true})))
  (set create-table-methods.compile
    (fn [self opts]
      (local state (make-compile-state opts))
      (local sql (compile-query self state))
      (if (= state.param-style :named)
          {:sql sql :params state.named}
          {:sql sql :params state.params})))
  (set create-table-methods.to-sql create-table-methods.compile)
  (set create-table-methods.to-sql-string (fn [self opts] (. (self:compile opts) :sql)))

  (set create-index-methods.if-not-exists (fn [self] (update-create-index-query self {:if-not-exists? true})))
  (set create-index-methods.unique (fn [self] (update-create-index-query self {:unique? true})))
  (set create-index-methods.on
    (fn [self table-name ...]
      (update-create-index-query self
                                 {:table (if (= (type table-name) :string)
                                             (table* table-name nil)
                                             table-name)
                                  :columns (copy-array [...])})))
  (set create-index-methods.where
    (fn [self criterion]
      (update-create-index-query self {:where (wrap-expr criterion)})))
  (set create-index-methods.compile
    (fn [self opts]
      (local state (make-compile-state opts))
      (local sql (compile-query self state))
      (if (= state.param-style :named)
          {:sql sql :params state.named}
          {:sql sql :params state.params})))
  (set create-index-methods.to-sql create-index-methods.compile)
  (set create-index-methods.to-sql-string (fn [self opts] (. (self:compile opts) :sql)))

  (set create-view-methods.if-not-exists (fn [self] (update-create-view-query self {:if-not-exists? true})))
  (set create-view-methods.temporary (fn [self] (update-create-view-query self {:temporary? true})))
  (set create-view-methods.as (fn [self select-query] (update-create-view-query self {:select-query select-query})))
  (set create-view-methods.compile
    (fn [self opts]
      (local state (make-compile-state opts))
      (local sql (compile-query self state))
      (if (= state.param-style :named)
          {:sql sql :params state.named}
          {:sql sql :params state.params})))
  (set create-view-methods.to-sql create-view-methods.compile)
  (set create-view-methods.to-sql-string (fn [self opts] (. (self:compile opts) :sql)))

  (set table-methods.as (fn [self alias] (table* self._name alias)))
  (set table-methods.for_
    (fn [self criterion]
      (error "table for_ is not supported in sqlite sql-builder")))
  (set table-methods.for-portion
    (fn [self period-criterion]
      (error "table for-portion is not supported in sqlite sql-builder")))
  (set table-methods.for_portion (fn [self period-criterion] (self:for-portion period-criterion)))
  (set table-methods.select
    (fn [self ...]
      (local q0 (from self))
      (if (> (# [...]) 0)
          (q0:select ...)
          (q0:select (star self)))))
  (set table-methods.update (fn [self] (update self)))
  (set table-methods.delete
    (fn [self]
      (local q0 (from self))
      (q0:delete)))
  (set table-methods.insert
    (fn [self ...]
      (local q0 (insert-into self))
      (if (> (# [...]) 0)
          (q0:values ...)
          q0))))

{:install install}
