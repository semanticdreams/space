---
type: dev-note
tags:
  - note
---

# Native Build Module

`assets/lua/native-build.fnl` provides a Fennel API for native C/C++ builds through the `process` module.

It wraps:

- `g++` via `native-build.Gpp`
- `gcc` via `native-build.Gcc`
- `ar` via `native-build.Ar`

## Factories

```fennel
(local native-build (require :native-build))

(local cxx (native-build.Gpp {:standard "c++17"
                              :optimization 2
                              :verbose false
                              :max-parallel 4}))
(local cc (native-build.Gcc {:standard "c11"}))
(local ar (native-build.Ar {}))
```

### Compiler options

- `:program` override executable name/path (`g++`, `gcc`)
- `:standard` language standard
- `:optimization` optimization level (`-O`)
- `:flags` extra default flags array
- `:verbose` print commands when true
- `:max-parallel` default async compile worker cap (integer `>= 1`)

## Project API

```fennel
(local project (native-build.Project {:name "my-app"
                                      :compiler cxx
                                      :build-dir "__pysembled__"}))

(project:add-executables ["src/main.cpp" "src/feature.cpp"])
(project:add-include-directory "include")
(project:add-link-path "lib")
(project:add-dynamic-lib "m")
(project:add-static-lib "build/libfoo.a")
(project:add-compile-flag "-Wall")
(project:add-linker-flag "-pthread")

(project:build {:max-parallel 2})
;; or async:
(local token (project:build-async {:max-parallel 2}))
(token:wait)

(local result (project:run {:args ["--help"]}))
```

## Library API

```fennel
(local lib (native-build.Library {:name "libexample"
                                  :compiler cxx
                                  :archiver ar
                                  :build-dir "__pysembled__"}))

(lib:add-source "src/example.cpp")
(lib:add-header "include/example.h")
(lib:add-include-directory "include")

(local static-path (lib:build))
(local shared-path (lib:build-shared))

(local package (lib:package {:dynamic true
                             :package-dir "dist/libexample"}))
```

`package` requires at least one header and creates:

- `<package-dir>/include`
- `<package-dir>/lib`

## Async Parallelism

`build-to-objects-async` now supports worker control:

- Compiler default: set `:max-parallel` on `Gpp`/`Gcc`
- Per-call override: pass `:max-parallel` to `build-async`/`build-shared-async`
- Validation: `:max-parallel` must be an integer `>= 1`

Behavior:

- `nil` means unlimited (spawn all compile jobs)
- finite value launches compile jobs up to the cap, then schedules remaining jobs as workers free up

## Errors

This module fails loudly:

- Non-zero command exits throw with command, exit code, stdout, and stderr.
- Missing required inputs (e.g., no sources, missing headers for `package`) throw.


## See also

- [[subsystems/build]]
