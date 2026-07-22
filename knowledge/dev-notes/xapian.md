---
type: dev-note
tags:
  - note
---

# Xapian Binding

This repo exposes Xapian to Lua/Fennel as the `xapian` module. It supports creating documents, opening databases (read-only or writable), indexing, and searching.

## Quick Start (Fennel)

```fennel
(local xapian (require :xapian))

;; Create or overwrite a writable database
(local db (xapian.open "/tmp/xapian-demo" {:writable true :create true :overwrite true}))

;; Build a document and index text
(local doc (xapian.document {
  :data "doc-1"
  :text "hello world from fennel"
  :stemmer "en"
  :terms ["tag:demo"]
  :values {0 "alpha"}
}))

(local id (db:add-document doc))
(db:commit)
(db:close)

;; Reopen read-only and search
(local rdb (xapian.open "/tmp/xapian-demo"))
(local result (rdb:search "hello" {:limit 10 :default-op "and" :stemmer "en"}))

;; Access matches
(each [_ match (ipairs result.matches)]
  (print match.docid match.score match.data))

(rdb:close)
```

## API

### `xapian.open path opts`

Open a database. Returns a `Database` handle.

- `path` (string): database directory.
- `opts` (table, optional):
  - `writable` (bool): open writable.
  - `create` (bool): create if missing. Requires `writable=true`.
  - `overwrite` (bool): create or overwrite. Requires `writable=true`.

Examples:

```fennel
(local db (xapian.open "/tmp/db" {:writable true :create true}))
(local rdb (xapian.open "/tmp/db"))
```

### `xapian.document opts`

Create a Xapian document with optional data, indexed text, terms, and values. Returns a `Document`.

- `opts` (table, optional):
  - `data` (string): stored document payload.
  - `text` (string): text to index via `TermGenerator`.
  - `stemmer` (string): stemmer language (ex: `"en"`) used for `text`.
  - `terms` (array of string): explicit terms to add.
  - `values` (map of integer -> string): document values. Keys must be non-negative integers.

### `Database` methods

- `db:is-closed()` -> bool
- `db:is-writable()` -> bool
- `db:close()`
- `db:doccount()` -> integer
- `db:commit()`
- `db:add-document doc` -> docid
- `db:replace-document docid doc`
- `db:delete-document docid`
- `db:get-document docid` -> table `{ :data "...", :values {...} }`
- `db:search query opts` -> table

### `db:search query opts`

Execute a query. Returns a table with:

- `estimated`: estimated match count
- `count`: actual count returned
- `matches`: array of match tables

Each match has:

- `docid`: Xapian document id
- `rank`: rank within the match set
- `percent`: relevance percent
- `score`: weight
- `data`: document data
- `values`: document values map

Options:

- `limit` (int, default 10): max results.
- `offset` (int, default 0): result offset.
- `default-op` (string): `"and"` or `"or"`.
- `stemmer` (string): stemmer language for query parsing.
- `flags` (int or list of string): query parser flags. If omitted, uses Xapian defaults.
- `prefixes` (list of `{ :field \"...\" :prefix \"...\" }`): weighted field prefixes.
- `boolean-prefixes` (list of `{ :field \"...\" :prefix \"...\" }`): boolean filter prefixes.
- `boolean-filters` (list of `{ :prefix \"...\" :value \"...\" }`): filter terms applied via `OP_FILTER`.
- `value-ranges` (list of `{ :slot N :start \"...\" :end \"...\" }`): value range filters applied via `OP_FILTER`.
- `sort` (table): value sort options.
  - `value` (int, required): value slot to sort on.
  - `descending` (bool, default false).
  - `then-relevance` (bool, default false): use value sort, then relevance.
- `collapse` (table): collapse options.
  - `value` (int, required): value slot to collapse on.
  - `max` (int, default 1): max documents per collapse key.
- `include-corrected` (bool): include `:corrected` in results when spelling correction is enabled.
- `expand` (table): query expansion options.
  - `docids` (array of docids, required): relevance set.
  - `limit` (int, default 10): max expansion terms.
  - `flags` (int or list): `include-query-terms`, `exact-termfreq`.
  - `min-weight` (number, default 0): minimum term weight.
- `rset` (array of docids): relevance set used by weighting schemes.
- `weighting` (string or table): weighting scheme configuration.
- `ranges` (list of range processor configs):
  - `type`: `date` or `number`
  - `slot`: value slot
  - `prefix`: optional prefix (ex: `"date:"`, `"price:"`)
  - `options`: table with `suffix`, `repeated`, `prefer-mdy`
- `include-stoplist` (bool): include stoplist terms in results as `:stoplist`.
- `include-unstem` (bool): include unstem map as `:unstem` keyed by term.
- `include-collapse` (bool): include collapse key/count per match.
- `include-sort-key` (bool): include sort key per match.
- `include-matching-terms` (bool): include matching terms per match.

Example:

```fennel
(local result (db:search "hello world" {:limit 20 :offset 0 :default-op "and" :stemmer "en"}))
```

Supported `flags` strings:

- `boolean`
- `phrase`
- `lovehate`
- `boolean-any-case`
- `wildcard`
- `pure-not`
- `partial`
- `spelling-correction`
- `synonym`
- `auto-synonyms`
- `auto-multiword-synonyms`
- `cjk-ngram`
- `accumulate`
- `default`

Example with prefixes and filters:

```fennel
(local result
  (db:search "title:hello type:cat"
    {:flags ["boolean"]
     :prefixes [{:field "title" :prefix "T"}]
     :boolean-prefixes [{:field "type" :prefix "X"}]
     :boolean-filters [{:prefix "X" :value "cat"}]}))
```

Example with sorting, ranges, and collapse:

```fennel
(local result
  (db:search "hello"
    {:sort {:value 0 :descending true}
     :value-ranges [{:slot 0 :start "b" :end "c"}]
     :collapse {:value 1 :max 1}}))
```

Example with spelling correction and expansion:

```fennel
(local result
  (db:search "helo"
    {:flags ["spelling-correction"]
     :include-corrected true}))

(local expanded
  (db:search "alpha"
    {:expand {:docids [123] :limit 5 :flags ["include-query-terms"]}}))
```

Example with weighting + rset:

```fennel
(local result
  (db:search "alpha"
    {:weighting {:name "bm25" :params {:k1 1.2 :b 0.75}}
     :rset [123]}))
```

## Spelling and Synonyms

Writable databases can manage spellings and synonyms:

```fennel
(db:add-spelling "hello" 3)
(db:remove-spelling "hello" 1)
(db:add-synonym "car" "auto")
(db:remove-synonym "car" "auto")
(db:clear-synonyms "car")
(local suggestion (db:spelling-suggestion "helo" 2))
(local syns (db:synonyms "car"))
(local result (db:search "car" {:flags ["auto-synonyms"]}))
```

## Term Introspection

```fennel
(local terms (db:termlist docid {:positions true}))
(local positions (db:positions docid "alpha"))
(local all (db:allterms "T")) ;; optional prefix
(local freq (db:termfreq "alpha"))
```

## Query Parser Extras

```fennel
(local value (xapian.sortable-serialise 10))
(local result
  (db:search "price:5..15 date:2020-01-01..2020-12-31"
    {:ranges [{:type "number" :slot 3 :prefix "price:"}
              {:type "date" :slot 2 :prefix "date:"}]
     :include-stoplist true
     :include-unstem true
     :stemmer "en"}))
```

## Postings

```fennel
(local postings (db:postings "alpha" {:positions true :limit 100}))
```

## Stats

```fennel
(local stats (db:stats))
(local docstats (db:doc-stats docid))
(local cf (db:collection-freq "alpha"))
```

## Metadata

```fennel
(db:set-metadata "app.version" "1.0.0")
(local version (db:get-metadata "app.version"))
(local keys (db:metadata-keys "app."))
```

## MSet Extras

```fennel
(local result
  (db:search "alpha beta"
    {:collapse {:value 1 :max 1}
     :sort {:value 0}
     :include-collapse true
     :include-sort-key true
     :include-matching-terms true}))
```

## Spellings and Synonym Keys

```fennel
(local spellings (db:spellings))
(local keys (db:synonym-keys))
```

## Values

```fennel
(local values (db:values 4))
```

## Weighting Schemes

Supported names:

- `bm25` (params: `k1`, `k2`, `k3`, `b`, `min-normlen`)
- `bm25plus` (params: `k1`, `k2`, `k3`, `b`, `min-normlen`, `delta`)
- `trad` (param: `k`)
- `tfidf` (param: `normalizations`, e.g. `"ntn"`)
- `inl2`, `ifb2`, `ineb2`, `bb2`, `pl2`, `pl2plus` (param: `c`)
- `dlh`, `dph`, `bool`, `coord`
- `lm` (params: `log`, `smoothing`, `smoothing1`, `smoothing2`)

`smoothing` supports: `two-stage`, `jelinek-mercer`, `dirichlet`, `absolute`, `dirichlet-plus`.

## Error Behavior

- Invalid option types or values throw Lua errors (for example, negative `limit`/`offset`).
- Read-only databases throw if you call write operations.
- Xapian errors are surfaced with context like `"xapian search: ..."`.


## See also

- [[core-platform]]
