# Tempfile Module Implementation Plan

## Overview

Create a Fennel `tempfile` module that mirrors Python's `tempfile` functionality, providing secure creation of temporary files and directories with automatic cleanup via `drop` methods.

## Dependencies

### New: `lua_random.cpp` (C++ sol2 binding)

A general-purpose random module similar to Python's `random`, required for generating secure temporary file names.

**API:**

```fennel
(local random (require :random))

;; Seeding
(random.seed n)                    ; seed with integer
(random.seed)                      ; seed from system entropy (std::random_device)

;; Integer generation
(random.randint a b)               ; random integer in [a, b] inclusive
(random.randrange stop)            ; random integer in [0, stop)
(random.randrange start stop)      ; random integer in [start, stop)
(random.randrange start stop step) ; random integer in range with step

;; Float generation
(random.random)                    ; random float in [0.0, 1.0)
(random.uniform a b)               ; random float in [a, b]

;; Bytes
(random.randbytes n)               ; n random bytes as raw string
(random.randbytes-hex n)           ; n random bytes as hex string (2n chars)

;; Sequence operations
(random.choice seq)                ; random element from sequence (table)
(random.shuffle seq)               ; shuffle sequence in-place, returns it
(random.sample seq k)              ; k unique random elements (new table)
```

**Implementation notes:**
- Use `std::mt19937_64` as the PRNG engine
- Seed from `std::random_device` by default for non-deterministic behavior
- Use `std::uniform_int_distribution` and `std::uniform_real_distribution`
- Thread-local generator to avoid contention
- `randbytes` uses the engine directly, extracting bytes from 64-bit outputs

### Existing: `fs` module

Already provides all needed filesystem operations:
- `fs.exists`, `fs.create-dir`, `fs.create-dirs`
- `fs.remove`, `fs.remove-all`
- `fs.join-path`, `fs.write-file`
- `fs.stat`

### Existing: `appdirs` module

Provides cross-platform temp directory:
- `appdirs.tmp-dir` returns system temp directory

## Fennel Module: `assets/lua/tempfile.fnl`

### API

```fennel
(local tempfile (require :tempfile))

;; Get temp directory
(tempfile.gettempdir)              ; returns system temp dir (via appdirs)

;; Low-level creation (returns path only, no automatic cleanup)
(tempfile.mkstemp)                 ; create temp file, returns path
(tempfile.mkstemp {:suffix ".txt" :prefix "data_" :dir "/custom/tmp"})

(tempfile.mkdtemp)                 ; create temp directory, returns path
(tempfile.mkdtemp {:suffix "_work" :prefix "build_" :dir "/custom/tmp"})

;; High-level handles (automatic cleanup via drop)
(tempfile.NamedTemporaryFile)      ; returns handle with :path and :drop
(tempfile.NamedTemporaryFile {:suffix ".log" :prefix "app_" :dir d :delete true})
;; handle.path   - the file path
;; handle:drop() - deletes file if :delete is true (default)

(tempfile.TemporaryDirectory)      ; returns handle with :path and :drop
(tempfile.TemporaryDirectory {:suffix "" :prefix "tmp" :dir d})
;; handle.path   - the directory path
;; handle:drop() - recursively deletes directory
```

### Defaults

- `prefix`: `"tmp"`
- `suffix`: `""`
- `dir`: `(appdirs.tmp-dir)`
- `delete`: `true` (for NamedTemporaryFile)

### Name Generation

Generate names using: `{prefix}{random_hex}{suffix}`

Where `random_hex` is 16 hex characters (8 random bytes) from `random.randbytes-hex`.

For collision avoidance, retry up to 10 times if path exists.

## File Structure

```
src/
  lua_random.cpp          ; new C++ binding

assets/lua/
  tempfile.fnl            ; new Fennel module

assets/lua/tests/
  test-random.fnl         ; tests for random module
  test-tempfile.fnl       ; tests for tempfile module
```

## Implementation Steps

### Phase 1: C++ Random Module

1. Create `src/lua_random.cpp`:
   - Include `<random>`, `<string>`, `<algorithm>`
   - Thread-local `std::mt19937_64` engine
   - Implement all API functions
   - Register via `lua_bind_random` in `lua_runtime.cpp`

2. Add declaration and call in `src/lua_runtime.cpp`:
   ```cpp
   void lua_bind_random(sol::state&);
   // ...
   lua_bind_random(lua);
   ```

3. Build and verify: `make build`

### Phase 2: Random Module Tests

Create `assets/lua/tests/test-random.fnl`:
- Test `seed` produces reproducible sequences
- Test `randint` bounds are inclusive
- Test `randrange` bounds and step
- Test `random` and `uniform` produce floats in range
- Test `randbytes` and `randbytes-hex` length
- Test `choice` returns element from table
- Test `shuffle` modifies in place
- Test `sample` returns correct count without duplicates

### Phase 3: Fennel Tempfile Module

Create `assets/lua/tempfile.fnl`:
- Require `random`, `fs`, `appdirs`
- Implement `gettempdir`
- Implement `mkstemp` and `mkdtemp` with retry logic
- Implement `NamedTemporaryFile` returning handle table
- Implement `TemporaryDirectory` returning handle table

### Phase 4: Tempfile Module Tests

Create `assets/lua/tests/test-tempfile.fnl`:
- Test `gettempdir` returns non-empty string
- Test `mkstemp` creates file that exists
- Test `mkdtemp` creates directory that exists
- Test `NamedTemporaryFile` path exists, drop deletes it
- Test `NamedTemporaryFile` with `delete=false` preserves file
- Test `TemporaryDirectory` path exists as dir, drop removes it
- Test custom prefix/suffix/dir options
- Test collision retry (mock or stress test)

### Phase 5: Register Tests

Add new test modules to `assets/lua/tests/fast.fnl`.

## Error Handling

- Throw errors (via `error()` or `assert`) for:
  - Failed file/directory creation after retries exhausted
  - Invalid arguments (negative byte counts, empty sequences for choice)
- Do not silently fail or return nil

## Thread Safety

- C++ random module uses thread-local storage for the PRNG
- Fennel tempfile module is not thread-safe (Lua single-threaded)

## Validation

After implementation:
1. `make build` succeeds
2. `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test` passes
3. Manual verification of temp file creation and cleanup
