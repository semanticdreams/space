---
# https://vitepress.dev/reference/default-theme-home-page
layout: home

hero:
  name: "space"
  text: "A 3D Computing Interface"
  tagline: Build apps, tools, and worlds in a shared runtime where UI, code, and data stay connected.
  image:
    src: /space.png
    alt: space logo
  actions:
    - theme: brand
      text: Quick Start
      link: /user/quick-start
    - theme: alt
      text: User Docs
      link: /user/
    - theme: alt
      text: Developer Docs
      link: /dev/

features:
  - title: 3D-First Interface
    details: Go beyond flat windows with spatial UI, in-world media, and workflows that benefit from depth and context.
  - title: Fennel + C++ Runtime
    details: Script quickly with Fennel on top of a performant C++ engine, with strong control over behavior and layout.
  - title: Entity-Based Model
    details: Represent code, notes, tasks, and app state as linked entities for richer organization and navigation.
  - title: Space Graph
    details: Use graph relationships as a common interaction model across app features, tools, and views.
  - title: Collaboration by Design
    details: Build toward realtime shared spaces with synchronized entities and collaborative editing workflows.
  - title: Decentralized Pods
    details: Run user-owned service bundles for sync, communication, and distribution without central lock-in.
---

## What You Can Build

- Workflow-oriented apps that combine code, data, and UI in one place.
- Collaborative spaces for coding, planning, and knowledge management.
- Visual and spatial tools for exploring complex systems.

## Start Here

From the repository root:

```bash
make build
make run
make test
```

## Key Docs

- Quick Start: [/user/quick-start](/user/quick-start)
- User documentation: [/user/](/user/)
- Developer documentation: [/dev/](/dev/)
- Concepts: [/dev/concepts](/dev/concepts)
