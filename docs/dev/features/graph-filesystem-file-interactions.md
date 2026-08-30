# Graph Filesystem File Interactions

`fs:<path>` is the generic filesystem path adapter. Directory paths render the existing searchable directory listing and opening an entry materializes a child `fs:<child-path>` node with an explicit edge.

Regular file paths render a SearchView of explicit interaction rows. Interaction rows are data objects with `kind` fields; labels are display text only.

File type detection is conservative and extension-based for this iteration. Viewer and module rows are emitted only for regular files classified as known text/source extensions; unknown regular files expose only the safe `:external-editor` interaction.

## File interactions

- `:external-editor` opens `ExternalEditor.open-file(path, callback)` and does not add graph topology.
- `:file-viewer` materializes `fs-file-viewer:<absolute-path>` and adds an explicit edge from the file `FsNode`.
- `:module` materializes `fnl-module:<absolute-path>`, `cpp-module:<absolute-path>`, or `text-module:<absolute-path>` and adds an explicit edge.

## Editable lazy internal viewer

`fs-file-viewer:<absolute-path>` is a UX-purpose graph node backed by `LazyTextSource.file`, `LazyTextBuffer`, and the `VirtualInput` widget. It opens regular text/source files as editable lazy text without loading the whole file into memory and without serializing file contents into graph state.

The viewer UI uses `VirtualInput` for internal editing. `Input` and `InputModel` remain for small in-memory controls and must not be used for file-scale text. `VirtualInput` renders only visible rows from bounded viewport snapshots and routes edits to the lazy piece-table buffer.

The viewer provides explicit `Save` and `Edit externally` controls. The external-editor button remains available because double-click behavior is not the primary file-opening affordance for this lazy editable viewer.

Saving never blindly overwrites externally changed files. Before saving, the viewer checks whether the file token still matches the buffer baseline; the buffer then saves through `fs.atomic-replace-if-current`, which revalidates the token after writing the temporary replacement and reports a conflict instead of replacing a modified file.

## Persistence invariant

Graph persistence stores visible node keys and explicit edge keys only. File content remains owned by the filesystem and is never captured in graph topology state.
