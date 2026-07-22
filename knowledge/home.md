---
type: index
aliases:
  - Home
tags:
  - index
---

# Space

Space is a 3D spatial computing platform and malleable software environment — a runtime where the world, the tools, and the data live in one unified graph. Built in C++ with Fennel (Lisp) scripting. GPLv3.

- **Website:** [spaceui.org](https://spaceui.org)
- **Source:** [github.com/semanticdreams/space](https://github.com/semanticdreams/space)
- **Docs:** [[docs/index|VitePress documentation]]

## Navigation

- [[goals|Goals]] — what we're building toward
- [[features|Features]] — what's being built
- [[adrs|Architecture Decisions]] — why we chose what we chose
- [[subsystems|Subsystems]] — how the pieces fit together
- [[dev-notes|Dev Notes]] — raw architecture & design notes
- [[milestones|Current Milestone]] — what's happening now
- [[ideas|Ideas]] — things worth exploring
- [[research|Research]] — investigations in progress or completed
- [[history|Project History]] — how we got here

## Work tracking

- [[bugs|Bugs]]
- [[tech-debt|Technical Debt]]
- [[lifecycle-hardening-plan|Lifecycle Hardening Plan]]

## Journal

See [[journal|all journal entries]].

Recent entries:

```dataview
LIST
FROM "knowledge/journal"
WHERE type = "journal"
SORT file.name DESC
LIMIT 5
```

## Status

See [[milestones]] for the current milestone and roadmap. The project is currently focused on Milestone 1: making the graph foundation usable as a uniform interface for all system objects, code, files, and user-facing data.
