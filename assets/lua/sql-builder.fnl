(local function-methods {})
(local field-methods {})
(local table-methods {})
(local schema-methods {})
(local case-methods {})
(local query-methods {})
(local create-table-methods {})
(local create-index-methods {})
(local create-view-methods {})

(fn copy-array [items]
  (local out [])
  (each [_ item (ipairs (or items []))]
    (table.insert out item))
  out)

(fn quote-ident [name]
  (assert (= (type name) :string) "identifier must be a string")
  (.. "\"" (string.gsub name "\"" "\"\"") "\""))

(fn merge-map [base updates]
  (local out {})
  (each [k v (pairs (or base {}))]
    (set (. out k) v))
  (each [k v (pairs (or updates {}))]
    (set (. out k) v))
  out)

(fn raw [sql]
  {:__tag :raw :sql sql})

(fn literal [value]
  {:__tag :literal :value value})

(fn param [value name]
  {:__tag :param :value value :_name name})

(fn parameter [placeholder]
  {:__tag :placeholder :kind :parameter :placeholder placeholder})

(fn table-term [name alias schema]
  {:__tag :table :_name name :_alias (or alias false) :_schema (or schema false)})

(fn field [tbl name alias]
  {:__tag :field :_table (or tbl false) :_name name :_alias (or alias false)})

(fn star [tbl]
  {:__tag :star :_table tbl})

(fn schema-term [name parent]
  {:__tag :schema :_name name :_parent (or parent false)})

(fn wrap-expr [value]
  (if (and (= (type value) :table) (. value :__tag))
      value
      (literal value)))

(fn binary [op left right]
  {:__tag :binary :op op :left (wrap-expr left) :right (wrap-expr right)})

(fn unary [op expr]
  {:__tag :unary :op op :expr (wrap-expr expr)})

(fn call [name ...]
  (local args [...])
  (setmetatable
    {:__tag :call :_name name :_args (icollect [_ a (ipairs args)] (wrap-expr a))}
    {:__index function-methods}))

(fn call-distinct [name ...]
  (local args [...])
  (setmetatable
    {:__tag :call :_name name :_distinct? true :_args (icollect [_ a (ipairs args)] (wrap-expr a))}
    {:__index function-methods}))

(fn call-no-parens [name]
  (setmetatable
    {:__tag :call :_name name :_args [] :_omit_parens? true}
    {:__index function-methods}))

(fn call-with-special [name args special]
  (setmetatable
    {:__tag :call
     :_name name
     :_args (icollect [_ a (ipairs (or args []))] (wrap-expr a))
     :_special special}
    {:__index function-methods}))

(fn as [expr alias]
  {:__tag :alias :expr (wrap-expr expr) :_alias alias})

(fn and_ [...]
  (local parts [])
  (each [_ value (ipairs [...])]
    (when value
      (local wrapped (wrap-expr value))
      (if (and (= (. wrapped :__tag) :logical) (= (. wrapped :op) :and))
          (each [_ inner (ipairs wrapped.items)]
            (table.insert parts inner))
          (table.insert parts wrapped))))
  {:__tag :logical :op :and :items parts})

(fn or_ [...]
  (local parts [])
  (each [_ value (ipairs [...])]
    (when value
      (local wrapped (wrap-expr value))
      (if (and (= (. wrapped :__tag) :logical) (= (. wrapped :op) :or))
          (each [_ inner (ipairs wrapped.items)]
            (table.insert parts inner))
          (table.insert parts wrapped))))
  {:__tag :logical :op :or :items parts})

(fn add [left right] (binary :add left right))
(fn sub [left right] (binary :sub left right))
(fn mul [left right] (binary :mul left right))
(fn div [left right] (binary :div left right))
(fn mod [left right] (binary :mod left right))

(fn not_ [value]
  (unary :not value))

(fn exists [subquery]
  {:__tag :exists :query subquery})

(fn excluded [column]
  (local name (if (= (type column) :string) column column._name))
  {:__tag :excluded-field :name name})

(fn case_ [parts else-value base]
  {:__tag :case
   :base (if (= base nil) nil (wrap-expr base))
   :parts (or parts [])
   :else (if (= else-value nil) nil (wrap-expr else-value))})

(local CURRENT_ROW "CURRENT ROW")

(fn normalize-order-item [item]
  (if (and (= (type item) :table) (not (. item :__tag)) (. item 1))
      {:expr (wrap-expr (. item 1)) :dir (or (. item 2) :asc)}
      {:expr (wrap-expr item) :dir :asc}))

(fn make-compile-state [opts]
  (local options (or opts {}))
  (local style (or options.param-style :qmark))
  {:param-style style
   :params []
   :named {}
   :next-index 1
   :next-name-index 1})

(fn add-param! [state value explicit-name]
  (if (= state.param-style :named)
      (do
        (local name (or explicit-name (.. "p" state.next-name-index)))
        (when (not explicit-name)
          (set state.next-name-index (+ state.next-name-index 1)))
        (set (. state.named name) value)
        (.. ":" name))
      (do
        (table.insert state.params value)
        "?")))

(var compile-query nil)
(var compile-expr nil)

(fn binary-op-sql [op]
  (if (= op :eq) "="
      (= op :ne) "<>"
      (= op :gt) ">"
      (= op :gte) ">="
      (= op :lt) "<"
      (= op :lte) "<="
      (= op :like) "LIKE"
      (= op :not_like) "NOT LIKE"
      (= op :glob) "GLOB"
      (= op :ilike) (error "ilike is not supported in sqlite sql-builder")
      (= op :not_ilike) (error "not-ilike is not supported in sqlite sql-builder")
      (= op :regex) (error "regex (~) is not supported in sqlite sql-builder")
      (= op :regexp) "REGEXP"
      (= op :rlike) (error "rlike is not supported in sqlite sql-builder")
      (= op :bitand) "&"
      (= op :lshift) "<<"
      (= op :rshift) ">>"
      (= op :add) "+"
      (= op :sub) "-"
      (= op :mul) "*"
      (= op :div) "/"
      (= op :mod) "%"
      (error (.. "unsupported binary operator " (tostring op)))))

(fn compile-order-items [items state]
  (table.concat
    (icollect [_ item (ipairs items)]
      (do
        (local normalized (normalize-order-item item))
        (.. (compile-expr normalized.expr state)
            " "
            (if (= normalized.dir :desc) "DESC" "ASC"))))
    ", "))

(fn compile-function-special [special state]
  (if (not special)
      ""
      (if (= special.kind :as-type)
          (.. " AS "
              (if (and (= (type special.value) :table) special.value.__tag)
                  (compile-expr special.value state)
                  (string.upper (tostring special.value))))
          (if (= special.kind :using)
              (.. " USING " (tostring special.value))
              (if (= special.kind :raw)
                  (.. " " (tostring special.value))
                  "")))))

(fn compile-frame-bound [bound state]
  (if (= (type bound) :table)
      (if (= bound.__tag :frame-edge)
          (.. (if (or (= bound.value nil) (= bound.value false))
                  "UNBOUNDED"
                  (tostring bound.value))
              " "
              bound.modifier)
          (compile-expr bound state))
      (tostring bound)))

(fn compile-call [node state]
  (if (= node._extract true)
      (.. "EXTRACT("
          (compile-expr node._extract_part state)
          " FROM "
          (compile-expr node._extract_field state)
          ")")
      (do
        (var args-sql
          (table.concat
            (icollect [_ item (ipairs (or node._args []))]
              (compile-expr item state))
            ", "))
        (when node._distinct?
          (set args-sql (.. "DISTINCT " args-sql)))
        (var body
          (if (and node._omit_parens? (= (# (or node._args [])) 0) (not node._special))
              node._name
              (.. node._name "(" args-sql (compile-function-special node._special state) ")")))
        (when (and node._ignore_nulls? (not (= (# (or node._args [])) 0)))
          (set body
               (if (and node._special (not (= node._special.kind :raw)))
                   (.. node._name "(" args-sql (compile-function-special node._special state) " IGNORE NULLS)")
                   (.. node._name "(" args-sql " IGNORE NULLS)"))))
        (when (and node._filters (> (# node._filters) 0))
          (set body
               (.. body
                   " FILTER(WHERE "
                   (compile-expr (and_ (table.unpack node._filters)) state)
                   ")")))
        (when (or node._include_over? node._partition_by node._window_order_by node._window_frame)
          (local clauses [])
          (when (and node._partition_by (> (# node._partition_by) 0))
            (table.insert clauses
                          (.. "PARTITION BY "
                              (table.concat
                                (icollect [_ item (ipairs node._partition_by)]
                                  (compile-expr item state))
                                ", "))))
          (when (and node._window_order_by (> (# node._window_order_by) 0))
            (table.insert clauses
                          (.. "ORDER BY " (compile-order-items node._window_order_by state))))
          (when node._window_frame
            (local frame node._window_frame)
            (local frame-sql
              (if frame.and_bound
                  (.. frame.kind
                      " BETWEEN "
                      (compile-frame-bound frame.bound state)
                      " AND "
                      (compile-frame-bound frame.and_bound state))
                  (.. frame.kind " " (compile-frame-bound frame.bound state))))
            (table.insert clauses frame-sql))
          (set body (.. body " OVER(" (table.concat clauses " ") ")")))
        body)))

(set compile-expr
  (fn [expr state]
  (local node (wrap-expr expr))
  (local tag node.__tag)
  (if (= tag :raw)
      node.sql
      (= tag :literal)
      (add-param! state node.value nil)
      (= tag :param)
      (add-param! state node.value node._name)
      (= tag :placeholder)
      (if (= node.kind :qmark)
          "?"
          (= node.kind :numeric)
          (.. ":" (tostring node.placeholder))
          (= node.kind :named)
          (.. ":" (tostring node.placeholder))
          (= node.kind :format)
          "%s"
          (= node.kind :pyformat)
          (.. "%(" (tostring node.placeholder) ")s")
          (tostring node.placeholder))
      (= tag :table)
      (do
        (local table-sql
          (if (and node._schema (not (= node._schema false)))
              (.. (compile-expr node._schema state) "." (quote-ident node._name))
              (quote-ident node._name)))
        (if (and node._alias (not (= node._alias false)))
            (.. table-sql " AS " (quote-ident node._alias))
            table-sql))
      (= tag :schema)
      (if (and node._parent (not (= node._parent false)))
          (.. (compile-expr node._parent state) "." (quote-ident node._name))
          (quote-ident node._name))
      (= tag :field)
      (do
        (local base
          (if (and node._table (not (= node._table false)))
              (do
                (local table-name (or node._table._alias node._table._name))
                (.. (quote-ident table-name) "." (quote-ident node._name)))
              (quote-ident node._name)))
        (if (and node._alias (not (= node._alias false)))
            (.. base " AS " (quote-ident node._alias))
            base))
      (= tag :star)
      (if (and node._table (not (= node._table false)))
          (.. (quote-ident (or node._table._alias node._table._name)) ".*")
          "*")
      (= tag :alias)
      (.. (compile-expr node.expr state) " AS " (quote-ident node._alias))
      (= tag :binary)
      (.. "(" (compile-expr node.left state) " " (binary-op-sql node.op) " " (compile-expr node.right state) ")")
      (= tag :unary)
      (if (= node.op :not)
          (.. "(NOT " (compile-expr node.expr state) ")")
          (= node.op :neg)
          (.. "(-" (compile-expr node.expr state) ")")
          (error (.. "unsupported unary operator " (tostring node.op))))
      (= tag :logical)
      (do
        (local op (if (= node.op :and) " AND " " OR "))
        (if (= (# node.items) 0)
            (if (= node.op :and) "1=1" "1=0")
            (.. "("
                (table.concat
                  (icollect [_ item (ipairs node.items)]
                    (compile-expr item state))
                  op)
                ")")))
      (= tag :in)
      (do
        (local right
          (if (and (= (type node.values) :table) (not node.values.__tag))
              (.. "("
                  (table.concat
                    (icollect [_ item (ipairs node.values)]
                      (compile-expr item state))
                  ", ")
                  ")")
              (.. "(" (compile-expr node.values state) ")")))
        (.. "(" (compile-expr node.left state) " IN " right ")"))
      (= tag :not-in)
      (do
        (local right
          (if (and (= (type node.values) :table) (not node.values.__tag))
              (.. "("
                  (table.concat
                    (icollect [_ item (ipairs node.values)]
                      (compile-expr item state))
                    ", ")
                  ")")
              (.. "(" (compile-expr node.values state) ")")))
        (.. "(" (compile-expr node.left state) " NOT IN " right ")"))
      (= tag :between)
      (.. "("
          (compile-expr node.value state)
          " BETWEEN "
          (compile-expr node.low state)
          " AND "
          (compile-expr node.high state)
          ")")
      (= tag :from-to)
      (error "from-to is not supported in sqlite sql-builder")
      (= tag :as-of)
      (error "as-of is not supported in sqlite sql-builder")
      (= tag :all)
      (error "all_ is not supported in sqlite sql-builder")
      (= tag :any)
      (error "any_ is not supported in sqlite sql-builder")
      (= tag :is-null)
      (.. "(" (compile-expr node.expr state) " IS NULL)")
      (= tag :is-not-null)
      (.. "(" (compile-expr node.expr state) " IS NOT NULL)")
      (= tag :exists)
      (.. "EXISTS (" (compile-query node.query state) ")")
      (= tag :excluded-field)
      (.. "excluded." (quote-ident node.name))
      (= tag :tuple)
      (.. "("
          (table.concat
            (icollect [_ item (ipairs (or node.values []))]
              (compile-expr item state))
            ", ")
          ")")
      (= tag :call)
      (compile-call node state)
      (= tag :case)
      (do
        (local parts
          (icollect [_ part (ipairs (or node.parts []))]
            (.. "WHEN "
                (if node.base
                    (compile-expr part.when_value state)
                    (compile-expr part.when state))
                " THEN " (compile-expr part.then state))))
        (local else-sql
          (if node.else
              (.. " ELSE " (compile-expr node.else state))
              ""))
        (.. "CASE "
            (if node.base (.. (compile-expr node.base state) " ") "")
            (table.concat parts " ")
            else-sql
            " END"))
      (= tag :over)
      (do
        (local clauses [])
        (when (> (# node.partition-by) 0)
          (table.insert clauses
                        (.. "PARTITION BY "
                            (table.concat
                              (icollect [_ item (ipairs node.partition-by)]
                                (compile-expr item state))
                              ", "))))
        (when (> (# node.order-by) 0)
          (table.insert clauses
                        (.. "ORDER BY " (compile-order-items node.order-by state))))
        (when node.frame
          (table.insert clauses node.frame))
        (.. (compile-expr node.expr state)
            " OVER ("
            (table.concat clauses " ")
            ")"))
      (error (.. "unsupported expression tag " (tostring tag))))))

(fn compile-select [query state]
  (local chunks [])
  (when (> (# query._ctes) 0)
    (local ctes
      (icollect [_ cte (ipairs query._ctes)]
        (.. (quote-ident cte.name) " AS (" (compile-query cte.query state) ")")))
    (table.insert chunks
      (.. (if query._with_recursive? "WITH RECURSIVE " "WITH ")
          (table.concat ctes ", "))))

  (local select-prefix (if query._distinct? "SELECT DISTINCT " "SELECT "))
  (local select-items
    (if (> (# query._selects) 0)
        (table.concat
          (icollect [_ term (ipairs query._selects)]
            (compile-expr term state))
          ", ")
        "*"))
  (table.insert chunks (.. select-prefix select-items))

  (when query._from
    (table.insert chunks (.. "FROM " (compile-expr query._from state))))

  (each [_ join (ipairs query._joins)]
    (local kind
      (if (= join.kind :inner) "INNER JOIN"
          (= join.kind :left) "LEFT JOIN"
          (= join.kind :left_outer) "LEFT OUTER JOIN"
          (= join.kind :right) "RIGHT JOIN"
          (= join.kind :right_outer) "RIGHT OUTER JOIN"
          (= join.kind :full_outer) "FULL OUTER JOIN"
          (= join.kind :cross) "CROSS JOIN"
          "JOIN"))
    (var join-sql (.. kind " " (compile-expr join.table state)))
    (if join.on
        (set join-sql (.. join-sql " ON " (compile-expr join.on state)))
        (when join.using
          (set join-sql
               (.. join-sql " USING ("
                   (table.concat
                     (icollect [_ f (ipairs join.using)]
                       (quote-ident (if (= (type f) :string) f f._name)))
                     ", ")
                   ")"))))
    (table.insert chunks join-sql))

  (when query._where
    (table.insert chunks (.. "WHERE " (compile-expr query._where state))))

  (when (> (# query._group_by) 0)
    (table.insert chunks
      (.. "GROUP BY "
          (table.concat
            (icollect [_ term (ipairs query._group_by)]
              (compile-expr term state))
            ", "))))

  (when query._having
    (table.insert chunks (.. "HAVING " (compile-expr query._having state))))

  (when (> (# query._order_by) 0)
    (table.insert chunks
      (.. "ORDER BY " (compile-order-items query._order_by state))))

  (when query._limit
    (table.insert chunks (.. "LIMIT " query._limit)))

  (when query._offset
    (table.insert chunks (.. "OFFSET " query._offset)))

  (when query._for_update
    (table.insert chunks "FOR UPDATE"))

  (local sql (table.concat chunks " "))

  (if (> (# query._set_ops) 0)
      (do
        (var set-sql sql)
        (each [_ op (ipairs query._set_ops)]
          (local keyword
            (if (= op.op :union-all) "UNION ALL"
                (= op.op :union) "UNION"
                (= op.op :intersect) "INTERSECT"
                (= op.op :except) "EXCEPT"
                (error (.. "unsupported set operation " (tostring op.op)))))
          (set set-sql
               (.. "(" set-sql ") " keyword " (" (compile-query op.query state) ")")))
        set-sql)
      sql))

(fn compile-insert [query state]
  (assert query._into "insert query requires table")
  (local insert-prefix
    (if (= query._insert_mode :replace)
        "INSERT OR REPLACE INTO "
        (= query._insert_mode :ignore)
        "INSERT OR IGNORE INTO "
        "INSERT INTO "))
  (local chunks [(.. insert-prefix (compile-expr query._into state))])
  (if (> (# query._columns) 0)
      (table.insert chunks
        (.. "(" (table.concat
                   (icollect [_ c (ipairs query._columns)]
                     (if (= (type c) :string)
                         (quote-ident c)
                         (quote-ident c._name)))
                   ", ") ")"))
      nil)

  (assert (or (> (# query._values_rows) 0) query._select_query)
          "insert query requires values rows or a select query")
  (assert (not (and (> (# query._values_rows) 0) query._select_query))
          "insert query cannot mix values rows with select query")
  (if query._select_query
      (table.insert chunks (compile-query query._select_query state))
      (table.insert chunks
        (.. "VALUES "
            (table.concat
              (icollect [_ row (ipairs query._values_rows)]
                (.. "(" (table.concat
                          (icollect [_ value (ipairs row)]
                            (compile-expr value state))
                          ", ") ")"))
              ", "))))

  (when query._on_conflict
    (local conflict query._on_conflict)
    (local target-sql
      (if (and conflict.target (> (# conflict.target) 0))
          (.. "("
              (table.concat
                (icollect [_ term (ipairs conflict.target)]
                  (if (= (type term) :string)
                      (quote-ident term)
                      (compile-expr term state)))
                ", ")
              ")")
          ""))
    (if (= conflict.action :do-nothing)
        (table.insert chunks (.. "ON CONFLICT" target-sql " DO NOTHING"))
        (if (= conflict.action :do-update)
            (do
              (assert (> (# (or conflict.sets [])) 0)
                      "insert on-conflict do-update requires at least one set")
              (table.insert chunks
                (.. "ON CONFLICT"
                    target-sql
                    " DO UPDATE SET "
                    (table.concat
                      (icollect [_ item (ipairs conflict.sets)]
                        (do
                          (local left
                            (if (= (type item.field) :string)
                                (quote-ident item.field)
                                (compile-expr item.field state)))
                          (.. left " = " (compile-expr item.value state))))
                      ", ")))
              (when conflict.where
                (table.insert chunks (.. "WHERE " (compile-expr conflict.where state)))))
            nil)))

  (when (> (# (or query._returning [])) 0)
    (table.insert chunks
      (.. "RETURNING "
          (table.concat
            (icollect [_ term (ipairs query._returning)]
              (compile-expr term state))
            ", "))))

  (table.concat chunks " "))

(fn compile-update [query state]
  (assert query._table "update query requires table")
  (assert (> (# query._sets) 0) "update query requires at least one set")
  (local chunks [(.. "UPDATE " (compile-expr query._table state))])
  (table.insert chunks
    (.. "SET "
        (table.concat
          (icollect [_ item (ipairs query._sets)]
            (do
              (local left
                (if (= (type item.field) :string)
                    (quote-ident item.field)
                    (compile-expr item.field state)))
              (.. left " = " (compile-expr item.value state))))
          ", ")))
  (when query._where
    (table.insert chunks (.. "WHERE " (compile-expr query._where state))))
  (when (> (# (or query._returning [])) 0)
    (table.insert chunks
      (.. "RETURNING "
          (table.concat
            (icollect [_ term (ipairs query._returning)]
              (compile-expr term state))
            ", "))))
  (table.concat chunks " "))

(fn compile-delete [query state]
  (assert query._from "delete query requires table")
  (local chunks [(.. "DELETE FROM " (compile-expr query._from state))])
  (when query._where
    (table.insert chunks (.. "WHERE " (compile-expr query._where state))))
  (when (> (# (or query._returning [])) 0)
    (table.insert chunks
      (.. "RETURNING "
          (table.concat
            (icollect [_ term (ipairs query._returning)]
              (compile-expr term state))
            ", "))))
  (table.concat chunks " "))

(fn compile-column-definition [col state]
  (local chunks [(quote-ident col.name)])
  (when col.type
    (table.insert chunks col.type))
  (when (= col.nullable? false)
    (table.insert chunks "NOT NULL"))
  (when (= col.nullable? true)
    (table.insert chunks "NULL"))
  (when col.default
    (table.insert chunks (.. "DEFAULT " (compile-expr col.default state))))
  (when col.primary-key?
    (table.insert chunks "PRIMARY KEY"))
  (when col.autoincrement?
    (table.insert chunks "AUTOINCREMENT"))
  (when col.unique?
    (table.insert chunks "UNIQUE"))
  (when col.check
    (table.insert chunks (.. "CHECK (" (compile-expr col.check state) ")")))
  (when col.references
    (local refs col.references)
    (table.insert chunks
      (.. "REFERENCES "
          (compile-expr refs.table state)
          " ("
          (table.concat (icollect [_ r (ipairs refs.columns)] (quote-ident r)) ", ")
          ")"
          (if refs.on-delete (.. " ON DELETE " refs.on-delete) "")
          (if refs.on-update (.. " ON UPDATE " refs.on-update) ""))))
  (table.concat chunks " "))

(fn compile-table-constraint [constraint state]
  (if (= constraint.kind :primary-key)
      (.. "PRIMARY KEY ("
          (table.concat (icollect [_ c (ipairs constraint.columns)] (quote-ident c)) ", ")
          ")")
      (if (= constraint.kind :unique)
          (.. "UNIQUE ("
              (table.concat (icollect [_ c (ipairs constraint.columns)] (quote-ident c)) ", ")
              ")")
          (if (= constraint.kind :check)
              (.. "CHECK (" (compile-expr constraint.expr state) ")")
              (if (= constraint.kind :foreign-key)
                  (.. "FOREIGN KEY ("
                      (table.concat (icollect [_ c (ipairs constraint.columns)] (quote-ident c)) ", ")
                      ") REFERENCES "
                      (compile-expr constraint.references.table state)
                      " ("
                      (table.concat (icollect [_ c (ipairs constraint.references.columns)] (quote-ident c)) ", ")
                      ")"
                      (if constraint.references.on-delete
                          (.. " ON DELETE " constraint.references.on-delete)
                          "")
                      (if constraint.references.on-update
                          (.. " ON UPDATE " constraint.references.on-update)
                          ""))
                  (error (.. "unsupported table constraint kind " (tostring constraint.kind))))))))

(fn compile-create-table [query state]
  (assert query.table "create-table query requires table")
  (local prefix
    (if query.temporary?
        "CREATE TEMP TABLE"
        "CREATE TABLE"))
  (local header
    (if query.if-not-exists?
        (.. prefix " IF NOT EXISTS " (compile-expr query.table state))
        (.. prefix " " (compile-expr query.table state))))

  (if query.select-query
      (.. header " AS " (compile-query query.select-query state))
      (do
        (assert (> (+ (# query._columns_def) (# query._constraints)) 0)
                "create-table query requires columns or constraints")

        (local definitions [])
        (each [_ col (ipairs query._columns_def)]
          (table.insert definitions (compile-column-definition col state)))
        (each [_ constraint (ipairs query._constraints)]
          (table.insert definitions (compile-table-constraint constraint state)))

        (local suffix [])
        (when query.without-rowid?
          (table.insert suffix "WITHOUT ROWID"))
        (when query.strict?
          (table.insert suffix "STRICT"))

        (.. header
            " ("
            (table.concat definitions ", ")
            ")"
            (if (> (# suffix) 0)
                (.. " " (table.concat suffix " "))
                "")))))

(fn compile-create-index [query state]
  (assert query.name "create-index query requires name")
  (assert query.table "create-index query requires table")
  (assert (> (# query.columns) 0) "create-index query requires columns")
  (local prefix
    (if query.unique?
        "CREATE UNIQUE INDEX"
        "CREATE INDEX"))
  (local header
    (if query.if-not-exists?
        (.. prefix " IF NOT EXISTS " (quote-ident query.name))
        (.. prefix " " (quote-ident query.name))))
  (local columns-sql
    (table.concat
      (icollect [_ col (ipairs query.columns)]
        (if (= (type col) :string)
            (quote-ident col)
            (compile-expr col state)))
      ", "))
  (local sql
    (.. header
        " ON "
        (compile-expr query.table state)
        " ("
        columns-sql
        ")"))
  (if query.where
      (.. sql " WHERE " (compile-expr query.where state))
      sql))

(fn compile-create-view [query state]
  (assert query.view "create-view query requires view")
  (assert query.select-query "create-view query requires select query")
  (local prefix
    (if query.temporary?
        "CREATE TEMP VIEW"
        "CREATE VIEW"))
  (local header
    (if query.if-not-exists?
        (.. prefix " IF NOT EXISTS " (compile-expr query.view state))
        (.. prefix " " (compile-expr query.view state))))
  (.. header " AS " (compile-query query.select-query state)))

(fn compile-drop [query _state]
  (local kind
    (if (= query.kind :drop-table) "TABLE"
        (= query.kind :drop-view) "VIEW"
        (= query.kind :drop-index) "INDEX"
        (error (.. "unsupported drop query kind " (tostring query.kind)))))
  (.. "DROP " kind " "
      (if query.if-exists? "IF EXISTS " "")
      (compile-expr query.target (make-compile-state {:param-style :qmark}))))

(set compile-query
  (fn [query state]
    (if (= query.kind :select)
        (compile-select query state)
        (if (= query.kind :insert)
            (compile-insert query state)
            (if (= query.kind :update)
                (compile-update query state)
                (if (= query.kind :delete)
                    (compile-delete query state)
                    (if (= query.kind :create-table)
                        (compile-create-table query state)
                        (if (= query.kind :create-index)
                            (compile-create-index query state)
                            (if (= query.kind :create-view)
                                (compile-create-view query state)
                                (if (or (= query.kind :drop-table)
                                        (= query.kind :drop-view)
                                        (= query.kind :drop-index))
                                    (compile-drop query state)
                                    (error (.. "unsupported query kind " (tostring query.kind)))))))))))))

(fn clone-query [query]
  (local out (merge-map query {}))
  (set out._ctes (copy-array (or query._ctes [])))
  (set out._selects (copy-array (or query._selects [])))
  (set out._joins (copy-array (or query._joins [])))
  (set out._group_by (copy-array (or query._group_by [])))
  (set out._order_by (copy-array (or query._order_by [])))
  (set out._set_ops (copy-array (or query._set_ops [])))
  (set out._columns (copy-array (or query._columns [])))
  (set out._values_rows (copy-array (or query._values_rows [])))
  (set out._select_query query._select_query)
  (set out._sets (copy-array (or query._sets [])))
  (set out._returning (copy-array (or query._returning [])))
  (set out._columns_def (copy-array (or query._columns_def [])))
  (set out._constraints (copy-array (or query._constraints [])))
  (when query._on_conflict
    (set out._on_conflict
      {:target (copy-array (or query._on_conflict.target []))
       :action query._on_conflict.action
       :sets (copy-array (or query._on_conflict.sets []))
       :where query._on_conflict.where}))
  out)

(fn set-query-mt! [query]
  (setmetatable query {:__index (fn [_ key]
                                  (local method (. query-methods key))
                                  (if method method nil))})
  query)

(fn set-create-table-mt! [query]
  (setmetatable query {:__index (fn [_ key]
                                  (local method (. create-table-methods key))
                                  (if method method nil))})
  query)

(fn set-create-index-mt! [query]
  (setmetatable query {:__index (fn [_ key]
                                  (local method (. create-index-methods key))
                                  (if method method nil))})
  query)

(fn set-create-view-mt! [query]
  (setmetatable query {:__index (fn [_ key]
                                  (local method (. create-view-methods key))
                                  (if method method nil))})
  query)

(fn create-select-query []
  (set-query-mt!
    {:__tag :query
     :kind :select
     :_ctes []
     :_selects []
     :_from nil
     :_joins []
     :_where nil
     :_group_by []
     :_having nil
     :_order_by []
     :_limit nil
     :_offset nil
     :_for_update false
     :_distinct? false
     :_with_recursive? false
     :_set_ops []}))

(fn create-insert-query [into]
  (set-query-mt!
    {:__tag :query
     :kind :insert
     :_into into
     :_columns []
     :_values_rows []
     :_select_query nil
     :_insert_mode nil
     :_on_conflict nil
     :_returning []}))

(fn create-update-query [target]
  (set-query-mt!
    {:__tag :query
     :kind :update
     :_table target
     :_sets []
     :_where nil
     :_returning []}))

(fn create-delete-query [target]
  (set-query-mt!
    {:__tag :query
     :kind :delete
     :_from target
     :_where nil
     :_returning []}))

(fn create-create-table-query [target]
  (local resolved
    (if (= (type target) :string)
        (table-term target nil)
        target))
  (set-create-table-mt!
    {:__tag :query
     :kind :create-table
     :table resolved
     :if-not-exists? false
     :temporary? false
     :_columns_def []
     :_constraints []
     :select-query nil
     :without-rowid? false
     :strict? false}))

(fn create-create-index-query [name]
  (set-create-index-mt!
    {:__tag :query
     :kind :create-index
     :name name
     :if-not-exists? false
     :unique? false
     :table nil
     :columns []
     :where nil}))

(fn create-create-view-query [name]
  (set-create-view-mt!
    {:__tag :query
     :kind :create-view
     :view (if (= (type name) :string) (table-term name nil) name)
     :if-not-exists? false
     :temporary? false
     :select-query nil}))

(fn create-drop-query [kind target opts]
  (local resolved
    (if (= (type target) :string)
        (table-term target nil)
        target))
  (set-query-mt!
    {:__tag :query
     :kind kind
     :target resolved
     :if-exists? (= (. (or opts {}) :if-exists?) true)}))

(fn update-select-query [query updates]
  (local next (clone-query query))
  (each [k v (pairs updates)]
    (set (. next k) v))
  (set-query-mt! next))

(fn update-create-table-query [query updates]
  (local next (clone-query query))
  (each [k v (pairs updates)]
    (set (. next k) v))
  (set-create-table-mt! next))

(fn update-create-index-query [query updates]
  (local next (merge-map query {}))
  (set next.columns (copy-array (or query.columns [])))
  (each [k v (pairs updates)]
    (set (. next k) v))
  (set-create-index-mt! next))

(fn update-create-view-query [query updates]
  (local next (merge-map query {}))
  (each [k v (pairs updates)]
    (set (. next k) v))
  (set-create-view-mt! next))

(set function-methods.as
  (fn [self alias]
    (as self alias)))

(fn clone-call [self]
  (merge-map self
             {:_args (copy-array (or self._args []))
              :_filters (copy-array (or self._filters []))
              :_partition_by (copy-array (or self._partition_by []))
              :_window_order_by (copy-array (or self._window_order_by []))}))

(set function-methods.distinct
  (fn [self]
    (local next (clone-call self))
    (set next._distinct? true)
    (setmetatable next {:__index function-methods})))

(set function-methods.filter
  (fn [self ...]
    (local next (clone-call self))
    (local filters (copy-array (or next._filters [])))
    (each [_ criterion (ipairs [...])]
      (table.insert filters (wrap-expr criterion)))
    (set next._filters filters)
    (setmetatable next {:__index function-methods})))

(set function-methods.over
  (fn [self ...]
    (local next (clone-call self))
    (local parts (copy-array (or next._partition_by [])))
    (each [_ term (ipairs [...])]
      (table.insert parts (wrap-expr term)))
    (set next._partition_by parts)
    (set next._include_over? true)
    (setmetatable next {:__index function-methods})))

(set function-methods.orderby
  (fn [self ...]
    (local next (clone-call self))
    (local items (copy-array (or next._window_order_by [])))
    (each [_ term (ipairs [...])]
      (table.insert items term))
    (set next._window_order_by items)
    (set next._include_over? true)
    (setmetatable next {:__index function-methods})))
(set function-methods.order_by (fn [self ...] (self:orderby ...)))

(set function-methods.rows
  (fn [self bound and-bound]
    (local next (clone-call self))
    (set next._window_frame {:kind "ROWS" :bound bound :and_bound and-bound})
    (set next._include_over? true)
    (setmetatable next {:__index function-methods})))

(set function-methods.range
  (fn [self bound and-bound]
    (local next (clone-call self))
    (set next._window_frame {:kind "RANGE" :bound bound :and_bound and-bound})
    (set next._include_over? true)
    (setmetatable next {:__index function-methods})))

(set function-methods.ignore-nulls
  (fn [self]
    (local next (clone-call self))
    (set next._ignore_nulls? true)
    (setmetatable next {:__index function-methods})))
(set function-methods.ignore_nulls (fn [self] (self:ignore-nulls)))

(fn set-field-mt! [f]
  (setmetatable f
    {:__index (fn [_ key]
                (local method (. field-methods key))
                (if method method nil))})
  f)

(fn set-table-mt! [t]
  (setmetatable t
    {:__index (fn [tbl key]
                (local method (. table-methods key))
                (if method
                    method
                    (if (= key :star)
                        (star tbl)
                        (set-field-mt! (field tbl (tostring key))))))})
  t)

(fn set-schema-mt! [s]
  (setmetatable s
    {:__index (fn [self key]
                (local method (. schema-methods key))
                (if method
                    method
                    (if (rawget self "_database?")
                        (set-schema-mt! (schema-term (tostring key) self))
                        (set-table-mt! (table-term (tostring key) nil self)))))})
  s)

(set field-methods.as (fn [self alias] (set-field-mt! (field self._table self._name alias))))
(set field-methods.eq (fn [self value] (binary :eq self value)))
(set field-methods.ne (fn [self value] (binary :ne self value)))
(set field-methods.gt (fn [self value] (binary :gt self value)))
(set field-methods.gte (fn [self value] (binary :gte self value)))
(set field-methods.lt (fn [self value] (binary :lt self value)))
(set field-methods.lte (fn [self value] (binary :lte self value)))
(set field-methods.like (fn [self value] (binary :like self value)))
(set field-methods.not-like (fn [self value] (binary :not_like self value)))
(set field-methods.not_like (fn [self value] (self:not-like value)))
(set field-methods.glob (fn [self value] (binary :glob self value)))
(set field-methods.ilike (fn [self value] (binary :ilike self value)))
(set field-methods.not-ilike (fn [self value] (binary :not_ilike self value)))
(set field-methods.not_ilike (fn [self value] (binary :not_ilike self value)))
(set field-methods.regex (fn [self value] (binary :regex self value)))
(set field-methods.regexp (fn [self value] (binary :regexp self value)))
(set field-methods.rlike (fn [self value] (binary :rlike self value)))
(set field-methods.bitwiseand (fn [self value] (binary :bitand self value)))
(set field-methods.lshift (fn [self value] (binary :lshift self value)))
(set field-methods.rshift (fn [self value] (binary :rshift self value)))
(set field-methods.negate (fn [self] (not_ self)))
(set field-methods.neg (fn [self] (unary :neg self)))
(set field-methods.in_
  (fn [self items]
    (if (and (= (type items) :table) (not (. items :__tag)))
        {:__tag :in :left (wrap-expr self) :values (icollect [_ v (ipairs items)] (wrap-expr v))}
        {:__tag :in :left (wrap-expr self) :values (wrap-expr items)})))
(set field-methods.isin (fn [self items] (self:in_ items)))
(set field-methods.contains (fn [self items] (self:in_ items)))
(set field-methods.not-in
  (fn [self items]
    (if (and (= (type items) :table) (not (. items :__tag)))
        {:__tag :not-in :left (wrap-expr self) :values (icollect [_ v (ipairs items)] (wrap-expr v))}
        {:__tag :not-in :left (wrap-expr self) :values (wrap-expr items)})))
(set field-methods.notin (fn [self items] (self:not-in items)))
(set field-methods.not_contains (fn [self items] (self:not-in items)))
(set field-methods.between
  (fn [self low high]
    {:__tag :between :value (wrap-expr self) :low (wrap-expr low) :high (wrap-expr high)}))
(set field-methods.slice (fn [self low high] (self:between low high)))
(set field-methods.from-to
  (fn [self start end]
    {:__tag :from-to :value (wrap-expr self) :start (wrap-expr start) :end (wrap-expr end)}))
(set field-methods.from_to (fn [self start end] (self:from-to start end)))
(set field-methods.as-of
  (fn [self point]
    {:__tag :as-of :value (wrap-expr self) :point (wrap-expr point)}))
(set field-methods.as_of (fn [self point] (self:as-of point)))
(set field-methods.all_ (fn [self] {:__tag :all :expr (wrap-expr self)}))
(set field-methods.any_ (fn [self] {:__tag :any :expr (wrap-expr self)}))
(set field-methods.is-null (fn [self] {:__tag :is-null :expr (wrap-expr self)}))
(set field-methods.is-not-null (fn [self] {:__tag :is-not-null :expr (wrap-expr self)}))
(set field-methods.is_null (fn [self] (self:is-null)))
(set field-methods.is_not_null (fn [self] (self:is-not-null)))
(set field-methods.isnull (fn [self] (self:is-null)))
(set field-methods.notnull (fn [self] (self:is-not-null)))
(set field-methods.isnotnull (fn [self] (self:is-not-null)))

(set case-methods.when
  (fn [self condition value]
    (local next
      (case_ (copy-array (or self.parts [])) self.else self.base))
    (local parts (copy-array next.parts))
    (if self.base
        (table.insert parts {:when_value (wrap-expr condition) :then (wrap-expr value)})
        (table.insert parts {:when (wrap-expr condition) :then (wrap-expr value)}))
    (set next.parts parts)
    (setmetatable next
      {:__index (fn [_ key]
                  (local method (. case-methods key))
                  (if method method nil))})))

(set case-methods.else
  (fn [self value]
    (local next
      (case_ (copy-array (or self.parts [])) value self.base))
    (setmetatable next
      {:__index (fn [_ key]
                  (local method (. case-methods key))
                  (if method method nil))})))
(set case-methods.else_
  (fn [self value]
    ((. case-methods :else) self value)))
(set case-methods.as (fn [self alias] (as self alias)))

(fn table* [name alias schema]
  (set-table-mt! (table-term name alias schema)))

(fn field* [tbl name alias]
  (set-field-mt! (field tbl name alias)))

(fn schema* [name parent]
  (set-schema-mt! (schema-term name parent)))

(fn database* [name]
  (local db (schema* name nil))
  (set db._database? true)
  db)

(fn make-tables [names opts]
  (local options (or opts {}))
  (local schema-value
    (if options.schema
        (if (= (type options.schema) :string)
            (schema* options.schema nil)
            options.schema)
        nil))
  (icollect [_ name (ipairs names)]
    (if (and (= (type name) :table) (not name.__tag) (. name 1) (. name 2))
        (table* (. name 1) (. name 2) schema-value)
        (table* name nil schema-value))))

(fn make-columns [names]
  (icollect [_ name (ipairs names)]
    (if (and (= (type name) :table) (. name 1) (. name 2))
        {:name (. name 1) :type (. name 2)}
        {:name name})))

(set schema-methods.table
  (fn [self name alias]
    (table* name alias self)))

(set schema-methods.schema
  (fn [self name]
    (schema* name self)))

(set table-methods.field
  (fn [self name]
    (field* self name nil)))

(set table-methods.star
  (fn [self]
    (star self)))

(fn select [...]
  (local q (create-select-query))
  (if (> (# [...]) 0)
      (q:select ...)
      q))

(fn from [source]
  (local q (create-select-query))
  (q:from source))

(fn with [name subquery]
  (local q (create-select-query))
  (q:with name subquery))

(fn with-recursive [name subquery]
  (local q0 (with name subquery))
  (q0:with-recursive))

(fn insert-into [target]
  (create-insert-query target))

(fn into [target]
  (insert-into target))

(fn update [target]
  (create-update-query target))

(fn delete-from [target]
  (create-delete-query target))

(fn create-table [target]
  (create-create-table-query target))

(fn drop-table [target opts]
  (create-drop-query :drop-table target opts))

(fn drop-view [target opts]
  (create-drop-query :drop-view target opts))

(fn drop-index [target opts]
  (create-drop-query :drop-index target opts))

(local QueryFacade
  {:from_ (fn [source] (from source))
   :select (fn [...] (select ...))
   :into (fn [target] (into target))
   :update (fn [target] (update target))
   :with_ (fn [subquery name]
            ;; PyPika signature is with_(table, name)
            (with name subquery))
   :with_recursive (fn [subquery name] (with-recursive name subquery))
   :create_table (fn [target] (create-table target))
   :create_index (fn [name] (create-create-index-query name))
   :create_view (fn [name] (create-create-view-query name))
   :drop_database (fn [target] (error "drop_database is not supported in sqlite sql-builder"))
   :drop_table (fn [target] (drop-table target {}))
    :drop_user (fn [user] (error "drop_user is not supported in sqlite sql-builder"))
   :drop_view (fn [target] (drop-view target {}))
   :drop_index (fn [target] (drop-index target {}))
   :Table (fn [name] (table* name nil))
   :Tables (fn [...] (make-tables [...] {}))})

(local SqlBuilderMethods (require :sql-builder-methods))
(SqlBuilderMethods.install
  {:query-methods query-methods
   :create-table-methods create-table-methods
   :create-index-methods create-index-methods
   :create-view-methods create-view-methods
   :table-methods table-methods
   :copy-array copy-array
   :clone-query clone-query
   :wrap-expr wrap-expr
   :and_ and_
   :update-select-query update-select-query
   :update-create-table-query update-create-table-query
   :update-create-index-query update-create-index-query
   :update-create-view-query update-create-view-query
   :set-query-mt! set-query-mt!
   :set-create-table-mt! set-create-table-mt!
   :make-compile-state make-compile-state
   :compile-query compile-query
   :from from
   :star star
   :update update
   :insert-into insert-into
   :table* table*})

(local function-catalog
  ((. (require :sql-builder-functions) :install)
    {:function-methods function-methods
     :call call
     :call-distinct call-distinct
     :call-no-parens call-no-parens
     :call-with-special call-with-special
     :wrap-expr wrap-expr
     :literal literal}))

(local SqlBuilderExports (require :sql-builder-exports))
(SqlBuilderExports.install
  {:table* table*
   :make-tables make-tables
   :make-columns make-columns
   :field* field*
   :star star
   :schema* schema*
   :database* database*
   :raw raw
   :literal literal
   :param param
   :parameter parameter
   :select select
   :from from
   :with with
   :with-recursive with-recursive
   :insert-into insert-into
   :into into
   :update update
   :delete-from delete-from
   :create-table create-table
   :create-create-index-query create-create-index-query
   :create-create-view-query create-create-view-query
   :drop-table drop-table
   :drop-view drop-view
   :drop-index drop-index
   :as as
   :binary binary
   :unary unary
   :wrap-expr wrap-expr
   :not_ not_
   :and_ and_
   :or_ or_
   :add add
   :sub sub
   :mul mul
   :div div
   :mod mod
   :exists exists
   :excluded excluded
   :case_ case_
   :case-methods case-methods
   :copy-array copy-array
   :CURRENT_ROW CURRENT_ROW
   :call call
   :call-distinct call-distinct
   :function-catalog function-catalog
   :QueryFacade QueryFacade})
