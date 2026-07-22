---
type: dev-note
tags:
  - note
---

# Entity store

## Overview

The entity store provides JSON file-based persistence for the core data types used by the graph system. Five entity types exist, each backed by its own subdirectory under `{data-dir}/entities/` with CRUD operations, UUID-based keys, and signal emission for changes.

## Entity types

### String entity (`entities/string.fnl`, 163 lines)

The simplest entity type — arbitrary text content with optional YAML frontmatter. The module parses frontmatter blocks (`---\n...\n---\n...`) into a `{:frontmatter table :body string}` structure.

- **Store**: `entities/string/` — one JSON file per entity
- **Content**: Text with optional frontmatter
- **Search**: Linear scan over all string entities
- **Signals**: `string-entity-created`, `string-entity-updated`, `string-entity-deleted`
- **API**: `get`, `create`, `save`, `delete`, `search`, `all`, `count`

### Code entity (`entities/code.fnl`)

Source code entities with language, kernel, and metadata.

- **Fields**: `:code` (source text), `:language` (string), `:kernel-id` (optional), `:meta` (table)
- **Store**: `entities/code/`
- **Signals**: `code-entity-created`, `code-entity-updated`, `code-entity-deleted`

### Link entity (`entities/link.fnl`, 176 lines)

Bidirectional labeled connections between graph keys. Links have a source key, target key, and label. They are indexed in both directions for fast lookup.

- **Fields**: `:from` (source key), `:to` (target key), `:label` (string)
- **Store**: `entities/link/`
- **Indexing**: In-memory caches for `from` and `to` direction lookups
- **Signals**: `link-entity-created`, `link-entity-updated`, `link-entity-deleted`
- **API**: `get-by-from`, `get-by-to` — fast reverse lookup for graph traversal

### List entity (`entities/list.fnl`)

Ordered collections of entity references. Used for grouping related graph objects.

- **Fields**: `:items` (array of entity reference keys)
- **Store**: `entities/list/`
- **Signals**: `list-entity-created`, `list-entity-updated`, `list-entity-deleted`

### Identity entity (`entities/identity.fnl`)

Self-referential identity nodes for stable references within the graph. Identity entities let other entities reference them by a persistent key that survives content changes — essential for notebook references, task links, and graph edges where the target may be updated.

- **Store**: `entities/identity/`
- **API**: `get-or-create` — ensure an identity exists, returning existing or creating new
- **Signals**: `identity-entity-created`, `identity-entity-updated`, `identity-entity-deleted`

## Architecture pattern

All entity stores follow the same pattern:
1. **Directory-backed**: Entities are `.json` files in typed subdirectories
2. **UUID keys**: Each entity has a UUID as its primary key
3. **In-memory cache**: `cache` table holds loaded entities; writes go to disk then update cache
4. **Signal emission**: Every mutation (create, update, delete) emits a signal with the entity data
5. **Factory pattern**: `StringEntityStore(opts)`, `CodeEntityStore(opts)`, etc. — no constructors, plain tables

## Integration with graph system

The graph system (`graph/core.fnl`) uses entity stores as the persistence backend for graph nodes. Each graph node type maps to one entity type. When a graph node is created, its backing entity is created in the corresponding store. When loaded, the entity store resolves the node's key to its data.

Link entities are especially important — they are the backing store for graph edges. The bidirectional index on link entities (`get-by-from` / `get-by-to`) enables the graph to traverse relationships in either direction without scanning.

Identity entities provide stable references: a notebook reference to a code file uses an identity entity as the target. If the code file's content changes, the identity persists and all references remain valid.


## See also

- [Core Platform](/dev/features/core-platform), [Graph Foundation](/dev/features/graph-foundation)
