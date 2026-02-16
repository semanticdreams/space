---
# https://vitepress.dev/reference/default-theme-home-page
layout: home

hero:
  name: "space"
  text: "Realtime UI Engine + App Runtime"
  tagline: C++ engine + Lua/Fennel widgets for fast iteration and deterministic runtime behavior.
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
  - title: Engine + UI Architecture
    details: Build UI with composable Fennel widgets on top of a C++17 runtime and explicit layout contracts.
  - title: Fast Local Workflow
    details: Use Make targets for build, run, tests, profiling, and snapshot updates with reproducible environment settings.
  - title: Integration Reference
    details: Navigate mirrored OpenAI API references and guides from one place when wiring responses, realtime, and tools.
---

## Start Here

Use these commands from the repository root:

```bash
make build
make run
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

## Key Docs

- Quick Start: [/user/quick-start](/user/quick-start)
- User documentation: [/user/](/user/)
- Developer documentation: [/dev/](/dev/)
