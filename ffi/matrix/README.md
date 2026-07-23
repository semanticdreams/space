# Matrix Rust Bridge

This crate exposes a minimal C ABI around matrix-rust-sdk so the C++ engine can call into Matrix
asynchronously via callbacks.

## Build

From the repo root:

```bash
make cmake
make build
```

The CMake build runs `cargo build --release` for the library (when `SPACE_BUILD_MATRIX=ON`
and `cargo` is present). Cargo incrementally compiles into a shared target directory
(by default `~/.cache/space/cargo-target/matrix/`), and CMake copies the artifact into
the build tree so each build tree owns its output at e.g. `build/libmatrix.so`.

## C ABI

Include `ffi/matrix/include/matrix.h` and link against the shared library. All async
operations invoke callbacks on a Tokio runtime thread.
