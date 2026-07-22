# SQL Builder (Fennel, SQLite)

`sql-builder` is the canonical query builder for this repo’s Fennel runtime.
It is immutable (builder-style chaining), SQLite-first, and intentionally strict:
features that are not valid for SQLite raise explicit errors.

## Module

```fennel
(local Sql (require :sql-builder))
```

## Design

- Immutable builders: every call returns a new query/expression.
- SQLite-first SQL generation.
- Strict unsupported behavior: no silent fallbacks for non-SQLite features.
- Parameterized compilation:
  - `:qmark` (default): `?` + positional params array
  - `:named`: `:p1`, `:p2`, ... + named param table

## Query Entry Points

- `Sql.select ...`
- `Sql.from table`
- `Sql.with name subquery`
- `Sql.with-recursive name subquery`
- `Sql.into table`
- `Sql.update table`
- `Sql.delete-from table`
- `Sql.create-table table-or-name`
- `Sql.create-index name`
- `Sql.create-view name`
- `Sql.drop-table table-or-name`
- `Sql.drop-view view-or-name`
- `Sql.drop-index index-or-name`

Query facade equivalents are available via `Sql.Query` (`from_`, `with_`, `with_recursive`, `into`, etc.).

## Tables, Fields, Schemas

- `Sql.table "users"` / `Sql.Table "users"`
- Field access:
  - dynamic: `users.id`
  - explicit: `(users:field "id")`
- Star:
  - dynamic: `users.star`
  - explicit: `(users:star)`
- Alias: `(users:as "u")`
- Schema/database helpers:
  - `(Sql.Schema "public")`
  - `(Sql.Database "hospital")` then `db.public.patients`

## Core SELECT

```fennel
(local u (Sql.table "users" "u"))
(local q
  (-> (Sql.from u)
      (:select u.id u.name)
      (:where (u.active:eq true))
      (:group-by u.id)
      (:having (Sql.gt (Sql.call "COUNT" u.id) 1))
      (:order-by [u.id :desc])
      (:limit 50)
      (:offset 0)))
```

Set operations:
- `:union`, `:union_all`, `:intersect`, `:except`, `:except_of`, `:minus`

CTEs:
- `:with name subquery`
- `:with_recursive`

## Joins

Direct joins:
- `:join target on-expr kind`
- `:join-using target ["col"] kind`
- typed helpers: `:left-join`, `:left_outer_join`, `:cross_join`, etc.

Joiner chaining (PyPika-style):
- `(q:join table):on(...)`
- `(q:join table):using(...)`
- `(q:join table):cross()`

## Expressions

Comparisons/operators:
- `eq ne gt gte lt lte like not-like not_like glob regexp`
- arithmetic: `add sub mul div mod`
- bitwise/shift: `bitwiseand lshift rshift`

Membership/ranges:
- `in_ not-in not_in notin contains not_contains`
- `between`
- term sugar: `:slice low high` and `Sql.slice expr low high` (BETWEEN)

Null checks:
- `is-null is_null isnull`
- `is-not-null is_not_null notnull isnotnull`

Boolean/unary:
- `and_ or_ not_`
- `negate` (alias of `not_`)
- `neg` (arithmetic unary minus)

CASE:
- `(Sql.case):when(cond, value):else_(default)`
- `(Sql.case expr):when(value, result):else_(default)`

Tuples:
- `Sql.tuple ...` / `Sql.Tuple ...`
- works with composite `IN` expressions

## Functions and Windows

Generic:
- `Sql.call "COUNT" expr`
- `Sql.fn "SUM" expr`
- `Sql.Functions.*` dynamic function helpers

Function aliases/chaining:
- `count-distinct` and `count_distinct`
- `:distinct`
- `:filter`
- `:over`
- `:orderby` and `:order_by`
- `:rows` / `:range`
- `:ignore-nulls` and `:ignore_nulls`

Analytics helpers:
- `Sql.Analytics.row_number`, `rank`, `dense_rank`, `lag`, `lead`, etc.

## INSERT / UPSERT / UPDATE / DELETE

INSERT values:
```fennel
(-> (Sql.into users)
    (:columns "id" "name")
    (:values [1 "sam"] [2 "pat"]))
```

INSERT from SELECT:
```fennel
(-> (Sql.into archived)
    (:columns "id" "name")
    (:from_select source-query))
```

Rules:
- `values` and `from_select` are mutually exclusive.

SQLite UPSERT:
- `:on-conflict ...` / `:on_conflict ...`
- `:do-update` / `:do_update`
- `:do-nothing` / `:do_nothing`
- `:conflict-where ...`
- `Sql.excluded "col"` for `excluded."col"`

Replace/ignore:
- `:replace`, `:insert_or_replace`, `:ignore`

DML returning:
- `:returning ...` on insert/update/delete

## DDL

Create table:
- `:if-not-exists`, `:temporary`
- `:column`, `:columns`
- `:primary-key`, `:unique`, `:check`, `:foreign-key`
- `:without-rowid`, `:strict`
- `:as-select`

Create index:
- `:if-not-exists`, `:unique`, `:on`, `:where`

Create view:
- `:if-not-exists`, `:temporary`, `:as`

Drop:
- `drop-table`, `drop-view`, `drop-index`, plus `:if-exists`

## Compile Output

```fennel
(local out (q:to-sql {:param-style :qmark}))
;; out.sql    -> SQL string
;; out.params -> positional params array

(local out2 (q:to-sql {:param-style :named}))
;; out2.sql    -> SQL with :pN names
;; out2.params -> table {p1=..., p2=...}
```

Helpers:
- `:to-sql`
- `:to-sql-string`
- `Sql.compile query opts`

## Strict SQLite Unsupported Surface

These intentionally raise explicit errors:

- Query methods:
  - `prewhere`
  - `for-update` / `for_update`
  - `use-index`
  - `force-index`
  - `with-totals`
  - `rollup`
  - `hash-join` / `hash_join`
- Table temporal methods:
  - `for_`
  - `for-portion` / `for_portion`
- Create-table extras:
  - `unlogged`
  - `with-system-versioning` / `with_system_versioning`
  - `period-for` / `period_for`
- Term helpers:
  - `from-to` / `from_to`
  - `as-of` / `as_of`
  - `all_`
  - `any_`
- Operators not valid in SQLite mode:
  - `ilike`, `not-ilike`
  - regex `~` (`regex`)
  - `rlike`
- Query facade:
  - `drop_database`
  - `drop_user`

## Test Coverage

Primary test module:
- `assets/lua/tests/test-sql-builder.fnl`

Included in fast suite:
- `assets/lua/tests/fast.fnl`
