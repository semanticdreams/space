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
and `cargo` is present). The shared library lands at:

```
ffi/matrix/target/release/libmatrix.*
```

## C ABI

Include `ffi/matrix/include/matrix.h` and link against the shared library. All async
operations invoke callbacks on a Tokio runtime thread.
