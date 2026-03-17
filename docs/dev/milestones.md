# Milestones

This is a rough planning document for developer-facing roadmap discussion.
It is intentionally small and editable.

## Milestone 0: Current foundation

Current work already covers a substantial slice of the core platform:

- 3D runtime with scene rendering, physics, spatial UI, and in-world surfaces.
- Fennel + C++ application model with the new layout/widget system replacing the older Python prototype.
- Entity and graph-oriented architecture for app state, knowledge objects, and linked views.
- Core workspace widgets and interactions, including text, buttons, inputs, lists, layout primitives, focus, and selection.
- Embedded integrations already present in the codebase:
  - OpenAI responses client and graph-oriented LLM conversation work.
  - Xapian search.
  - Terminal widget.
  - FFmpeg video playback.
  - CEF-based browsing work.
  - Matrix bridge foundation.
  - libtorrent binding.
  - wallet-core based wallet flow.
- Internal tooling for tests, profiling, render capture, and remote-control debugging.

This milestone is less about missing capability and more about making the existing pieces feel coherent as one product.

## Milestone 1: Usable graph foundation

The graph is meant to expose everything through one uniform interface:
state, code, system objects, files, world objects, and other user-facing data.
It is also the basis for other interfaces layered on top of it, not just the current graph view.

Focus on making that model actually usable:

- tighten graph browsing and editing flows
- improve linking between tasks, notes, code, errors, files, and conversations
- make graph-backed objects easier to inspect, edit, and navigate
- keep the graph model view-agnostic so future interfaces such as audio-first interaction can sit on top of the same structure

This is the most important immediate milestone because it improves the conceptual center of the system without requiring the hardest infrastructure work first.

Focus/risk: prioritize a few strong universal interactions over theoretical completeness. If inspection, linking, filtering, and navigation are weak, expanding graph coverage will mostly create noise.

## Milestone 2: Integrated workspace loop

This milestone should stay practical and avoid the deepest runtime redesigns.

- connect graph, terminal, search, file/code views, and basic editing into one coherent workflow
- improve the browser and media surfaces enough for reference and exploration during development
- make common user actions obvious and easy to learn

This milestone is about establishing a small but coherent workspace loop.

Focus/risk: define one or two complete workflows and make them feel natural. Breadth matters less here than a loop that is easy to understand and repeat.

## Milestone 3: Interactive world building

After the graph foundation is usable, focus on live world editing:

- add and manipulate terrain interactively
- place arbitrary widgets into the world
- create new widgets and geometry live in context
- expose physics and lighting controls so worlds become editable, usable, and playable

This is a strong demo milestone because it shows why space is not just another desktop UI.

Focus/risk: keep the first version constrained. A small set of terrain, geometry, widget, physics, and lighting workflows is more valuable than an early attempt at a full editor.

## Milestone 4: Malleable live development

Move toward malleable systems by letting users edit things in the context of use:

- edit widgets where they are being used instead of in a disconnected toolchain
- improve live code reload so changes can be applied quickly and safely
- support code living in multiple repositories while still appearing live inside space

This milestone likely introduces some architectural challenges:

- code identity and reload boundaries
- mapping live objects back to source definitions
- fast reload without leaving stale state behind
- multi-repo development without collapsing into ad-hoc compatibility layers
- preparing for a permission model that still works once live code editing expands
- providing history, snapshots, and rollback so live editing is usable rather than fragile

Focus/risk: define explicit reload units early. Without clear boundaries, malleability can turn into global invalidation, unclear ownership, and difficult live-state bugs.

## Milestone 5: Graph-native conversations and tools

Use the existing OpenAI integration and graph LLM direction in a minimal way:

- make saved conversations first-class graph objects
- support branch/fork workflows cleanly
- connect conversations to related entities such as tasks, code, and notes

This should stay narrow: useful agentic workflows without trying to solve all automation at once.

Focus/risk: keep LLM features subordinate to the graph and entity model. The first version should make conversations, branches, and links useful before attempting broader automation.

## Milestone 6: Compiled update pipeline

The current update system resolves chains live.
A later milestone is to declare update dependencies and generate optimized update functions from that graph.

- declare update dependencies explicitly
- generate optimized and possibly inlined update functions
- explore whether this becomes the basis for render/update specialization more broadly

This may require a deeper architectural shift, so it should come after the system is already useful.

Focus/risk: it is still unclear whether declared update dependencies become part of the user-facing programming model or remain an optimization layer. That decision will shape the architecture significantly.

## Milestone 7: Live native generation

If the compiled update model works well, use the existing GCCJIT work more aggressively:

- generate update functions in C live
- explore live-generated renderers and other performance-critical paths
- keep the workflow interactive rather than turning this into an offline build system
- explore whether generated code paths can support capability-aware permission enforcement before native code is emitted

This stays intentionally later because it depends on earlier clarity about the runtime model.

Focus/risk: only push this once the update/runtime model is stable enough to justify native generation. Otherwise the system may accumulate compiler complexity before the abstractions are ready.

## Milestone 8: Matrix worlds and realtime sync

Shared worlds can start on Matrix and add more specialized realtime transport where needed:

- continue Matrix world and room capabilities for shared state
- define the first real shared-world workflow
- add yojimbo for realtime synchronization where Matrix alone is not a good fit
- define a permission model for shared-world actions so editable worlds do not imply unrestricted code and object mutation
- establish object provenance and trust so users can tell where shared code, assets, and behaviors came from

Focus/risk: keep durable shared state and fast transient sync as separate concerns. Matrix and yojimbo can complement each other, but only if their responsibilities stay clear.

## Milestone 9: Social and contribution features

Build social features on top of the collaboration layer:

- profile pages and discussions based on Matrix
- contribution-oriented views around code, assets, and worlds
- one-click tipping for useful contributions using the wallet-core integration

This is a good example of a feature area that should stay small at first and become richer only after the core workspace is compelling.

Focus/risk: keep social features centered on meaningful objects such as code, assets, widgets, and worlds. Avoid expanding into generic social surface area too early.

## Milestone 10: Shared world gameplay

Build more complete game-oriented shared world features on top of the collaboration and world-building foundations:

- support richer world actors such as avatars and vehicles
- make it possible to host and play multiple game-like experiences inside worlds
- keep gameplay systems compatible with live editing so worlds remain modifiable in use

Focus/risk: gameplay should grow out of the same editable world and object model rather than becoming a disconnected subsystem. The challenge is keeping interactivity, multiplayer behavior, and live modification coherent.

## Milestone 11: User-owned services and distribution

Use the existing pod/torrent/wallet concepts carefully and incrementally:

- identify one concrete "space pod" responsibility worth shipping first
- use libtorrent where it clearly helps with asset or bundle distribution
- keep wallet work focused on practical workflows, not broad chain coverage

This milestone should remain infrastructure-light until the core workspace and collaboration loops are stronger.

Focus/risk: let concrete usage shape pods and distribution responsibilities. Over-designing this layer too early would create infrastructure without a proven product loop above it.
