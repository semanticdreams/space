# Graph Filesystem File Interactions

`fs:<path>` is the generic filesystem path adapter. Directory paths render the existing searchable directory listing and opening an entry materializes a child `fs:<child-path>` node with an explicit edge.

Regular file paths render a SearchView of explicit interaction rows. Interaction rows are data objects with `kind` fields; labels are display text only.

File type detection is conservative and extension-based for this iteration. Viewer and module rows are emitted only for regular files classified as known text/source extensions; unknown regular files expose only the safe `:external-editor` interaction.

## File interactions

- `:external-editor` opens `ExternalEditor.open-file(path, callback)` and does not add graph topology.
- `:file-viewer` materializes `fs-file-viewer:<absolute-path>` and adds an explicit edge from the file `FsNode`.
- `:module` materializes `fnl-module:<absolute-path>`, `cpp-module:<absolute-path>`, or `text-module:<absolute-path>` and adds an explicit edge.

## Bounded internal viewer

`fs-file-viewer:<absolute-path>` is a UX-purpose graph node. It owns viewer state such as current byte offset, previous offsets, and current bounded window metadata. It does not own or persist file content.

The viewer reads through `fs.read-text-window(path, offset, max-bytes)`, which caps reads at 262144 bytes, seeks to the requested zero-based byte offset, sanitizes display text, and returns bounded window metadata. Viewer UI must not use `Input` or `fs.read-file`.

Double-clicking the viewer content opens the external editor. Internal editing and saving are not part of this feature.

## Persistence invariant

Graph persistence stores visible node keys and explicit edge keys only. File content remains owned by the filesystem and is never captured in graph topology state.
