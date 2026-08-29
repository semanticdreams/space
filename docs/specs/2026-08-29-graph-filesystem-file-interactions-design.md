# Graph Filesystem File Interactions Design

## Context

Filesystem paths are currently exposed in the graph through `fs:<path>` nodes.
The same `FsNode` adapter is used for directories and regular files. Directory
nodes work well: their view renders a searchable list of directory entries and
opening an entry materializes a child graph node.

Regular file nodes currently inherit the same directory-oriented view. The view
attempts to list the file path with `fs.list-dir`; that failure is caught and an
empty item list is displayed. The result is that a file node looks like an empty
folder, even though the node already has file-aware actions such as external
edit and “open as Fennel/C++/text module”.

The graph doctrine applies directly here: the graph is an exposure/adaptor layer,
not the owner of filesystem data. File content remains owned by the filesystem,
and graph persistence remains limited to visible node keys and edge keys.

## Goals

- Make regular filesystem file nodes useful when reached through graph
  filesystem navigation.
- Keep `fs:<path>` as the generic filesystem path adapter for compatibility.
- For regular files, show only a search view over explicit specialized
  interactions rather than a directory-style empty listing.
- For text-like files, include:
  - an external editor interaction;
  - an internal viewer interaction;
  - type-specific module interactions such as Fennel module, C++ module, or
    generic text module.
- The internal viewer must be safe for arbitrarily large files by reading only
  bounded windows of content, never the entire file.
- The initial internal viewer is read-only. Editing and saving inside Space are
  intentionally out of scope.
- Double-clicking the internal viewer content should open the external editor.

## Non-goals

- No full internal text editor in this iteration.
- No write/save support from the internal viewer.
- No whole-file loading for large files.
- No split of `FsNode` into separate directory and file key families in this
  iteration.
- No MIME database integration, file watching, live reload, or full virtualized
  scrolling across an entire file.
- No graph ownership or persistence of file content.

## Existing Logic To Reuse

- `FsNode` already has path stat checks and extension checks for Fennel/C++/text
  module actions.
- Existing module nodes expose source files as dependency/reference graph nodes:
  `fnl-module:<path>`, `cpp-module:<path>`, and `text-module:<path>`.
- `ExternalEditor.open-file` is the canonical external edit path.
- `SearchView` is the established pattern for graph views that expose explicit
  related objects or actions.
- `Input` and `fs.read-file` are not suitable for arbitrary file sizes because
  they load/render whole content.

## Considered Approaches

### Approach A: Mode-aware `FsNode` plus dedicated lazy viewer node

Keep `fs:<path>` as the existing adapter. Directory paths continue to show
directory entries. Regular file paths build a search list of file interactions.
Selecting a graph-producing row materializes a specialized child node; selecting
an action row such as external edit performs the action without adding topology.

Text viewing is handled by a separate UX-purpose node such as
`fs-file-viewer:<absolute-path>`. That node owns only view state such as the
current offset and bounded window metadata. It reads file windows through a new
bounded filesystem API.

This is the recommended approach. It preserves existing keys, follows graph
doctrine, keeps dense content out of the generic file node, and keeps the first
implementation focused.

### Approach B: Split filesystem directories and files into separate node types

Introduce distinct directory and file node constructors and possibly distinct
key schemes. This would make responsibilities purer, but it risks graph-state
churn and key-loader compatibility problems. The current `fs:<path>` adapter can
branch by `fs.stat`, so the split is not necessary for the initial feature.

### Approach C: Render file content directly inside `FsNodeView`

This would be the smallest visible change, but it conflates filesystem
navigation with dense file content and encourages the same view to handle both
directories and file viewing. It also makes whole-file loading mistakes more
likely. Dense file content belongs in a specialized full node view/panel.

## Proposed Architecture

### `fs:<path>` remains the filesystem path adapter

`FsNode` continues to represent an existing filesystem path. It determines its
mode from `fs.stat(path)`:

- Directories build the existing sorted directory-entry search rows.
- Regular files build file-interaction search rows.

Directory behavior remains unchanged: opening a directory entry materializes a
child `fs:<child-path>` node and adds an explicit edge.

File behavior changes: opening a file node no longer attempts `fs.list-dir`.
Instead, the node produces rows such as:

- `Edit externally` — calls `ExternalEditor.open-file(path, callback)` and does
  not add a graph edge.
- `View text` — materializes `fs-file-viewer:<absolute-path>` and adds an edge.
- `Open as Fennel Module` for `.fnl` files — materializes the existing
  `fnl-module:<absolute-path>` node.
- `Open as C++ Module` for C/C++ source/header files — materializes the existing
  `cpp-module:<absolute-path>` node.
- `Open as Text Module` for other recognized text-like files — materializes the
  existing `text-module:<absolute-path>` node.

Rows should be explicit data objects with a `kind` field, rather than inferred
from display labels. Invalid or unsupported file interactions should fail loudly
or be omitted; they should not silently no-op.

### File type classification

File type classification should be centralized in a small graph-facing helper,
for example `graph/file-types.fnl`, instead of duplicating extension checks in
nodes and views.

Initial classification is conservative and extension-based:

- `.fnl` -> Fennel module;
- `.cpp`, `.cc`, `.cxx`, `.h`, `.hpp`, `.hh` -> C++ module;
- common text/source/doc/config extensions -> generic text;
- unknown or likely binary files -> no text viewer/module rows in the first
  iteration.

This can later be extended with content sniffing or MIME-like detection without
changing the graph node contract.

### Lazy internal file viewer node

Add a UX-purpose graph node keyed as `fs-file-viewer:<absolute-path>`. This node
is a graph-visible adapter over a real file and stores only lightweight viewer
state:

- path;
- current byte offset;
- bounded window metadata;
- offset history for previous/next window navigation;
- a signal for window changes.

It never owns or persists file content. Its view renders only the current window.

The node exposes methods such as:

- `load-window(offset)`;
- `next-window()`;
- `previous-window()`;
- `open-external()`.

`open-external()` calls `ExternalEditor.open-file`.

### Bounded filesystem read API

The existing `fs.read-file` API reads the entire file and must not be used for
the internal viewer. Add a bounded API such as:

```text
fs.read-text-window(path, offset, max-bytes) -> table
```

Returned fields should include:

- `path`;
- `offset`;
- `next-offset`;
- `size`;
- `bytes-read`;
- `eof`;
- `text`;
- optional `truncated-utf8`.

The implementation must validate arguments, cap `max-bytes` to a safe upper
bound, seek to the requested offset, and read no more than the bounded window.
It should sanitize invalid UTF-8 and embedded NULs for display rather than
crashing or passing raw binary through text rendering.

### Viewer UI behavior

The `fs-file-viewer` view should be a full node view/panel-style surface for the
bounded text window. It should provide:

- bounded text display for the current window;
- `Previous`, `Next`, and `Refresh` controls;
- visible metadata such as offset and bytes read;
- an `Edit externally` control;
- double-click on the content area to open the external editor.

The first version does not need true virtualized scrolling over the full file.
Window navigation is sufficient as long as every operation remains bounded.

## Data Flow

1. User navigates a directory graph node and selects a file entry.
2. `FsNode:open-entry` materializes `fs:<file-path>`.
3. The file `FsNode` view emits searchable interaction rows instead of directory
   entries.
4. Selecting `Edit externally` calls the external editor and does not change
   graph topology.
5. Selecting `View text` materializes `fs-file-viewer:<file-path>` and adds an
   explicit edge from the file node.
6. The viewer node reads a bounded text window from the filesystem and emits a
   window-change signal.
7. The viewer view displays that bounded window. Double-clicking the content
   calls `open-external()`.
8. Selecting module rows materializes the existing module nodes using their
   existing key formats.

## Error Handling

- Missing path, missing graph context when topology must be changed, and invalid
  viewer paths should assert or error clearly.
- Regular files should not call `fs.list-dir` during normal file-mode rendering.
- Bounded reads should reject negative offsets, empty paths, and invalid window
  sizes.
- Unknown file types should show only interactions that are safe for that type,
  such as external edit if configured.
- External editor configuration errors should continue to surface through the
  existing external editor path.

## Testing Strategy

- Add focused filesystem-binding tests for bounded text-window reads.
- Extend graph view tests so a regular `.fnl` file `FsNode` shows external edit,
  text viewer, and Fennel module rows.
- Test that opening the external edit row calls the external editor without
  adding a graph edge.
- Test that opening the text viewer row adds `fs-file-viewer:<absolute-path>`.
- Test that opening module rows preserves existing module key formats.
- Test that directory `FsNode` behavior remains unchanged.
- Test that the viewer node reads bounded windows, advances to the next window,
  supports previous-window navigation, and is loadable by key.

Relevant validation ladder for the implementation:

1. Build when C++ bindings change.
2. Run project-native Fennel compile checks.
3. Run constraints.
4. Run focused filesystem and graph tests.
5. Run the broader relevant suite before integration because this touches C++
   bindings, graph key loading, and graph UI behavior.

## Acceptance Criteria

- Directory filesystem graph navigation continues to work as before.
- A regular file node no longer renders as an empty folder.
- A text-like file node renders a search view over explicit interactions.
- Text-like file interactions include external edit, lazy internal view, and the
  appropriate module node option when applicable.
- The internal viewer never loads the whole file.
- Double-clicking the internal viewer content opens the external editor.
- Graph topology stores only visible node keys and edges; no file content is
  persisted in graph state.
