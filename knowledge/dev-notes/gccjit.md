---
type: dev-note
tags:
  - note
---

# GCCJIT Module

`src/lua_gccjit.cpp` registers `package.preload["gccjit"]` and exposes libgccjit to Lua/Fennel.

This is a thin wrapper over the C API with explicit release/drop behavior.

## Availability

- Linux only.
- Build requires `pkg-config --cflags --libs libgccjit`.

## Factory API

```fennel
(local gccjit (require :gccjit))

(local ctxt (gccjit.Context))
(local timer (gccjit.Timer))
```

## Core Objects

- `ContextRef` (`:drop`/`:release`)
- `ResultRef` (`:drop`/`:release`)
- `TimerRef` (`:drop`/`:release`)
- `BorrowedTimerRef` (returned by `ContextRef:get-timer`; no release/drop)
- `Type`, `Field`, `Struct`, `Function`, `Block`, `RValue`, `LValue`, `Param`, `Case`, `ExtendedAsm`, `Object`, `Location`

## Enum Tables

- `gccjit.StrOption`
- `gccjit.IntOption`
- `gccjit.BoolOption`
- `gccjit.OutputKind`
- `gccjit.Types`
- `gccjit.FunctionKind`
- `gccjit.GlobalKind`
- `gccjit.UnaryOp`
- `gccjit.BinaryOp`
- `gccjit.Comparison`

## Minimal Example

```fennel
(local gccjit (require :gccjit))

(local ctxt (gccjit.Context))
(local int-type (ctxt:get-type (. gccjit.Types "int")))
(local a (ctxt:new-param nil int-type "a"))
(local b (ctxt:new-param nil int-type "b"))

(local fn
  (ctxt:new-function nil
                     (. gccjit.FunctionKind "exported")
                     int-type
                     "add"
                     [a b]
                     false))

(local entry (fn:new-block "entry"))
(local sum (ctxt:new-binary-op nil
                               (. gccjit.BinaryOp "plus")
                               int-type
                               (a:as-rvalue)
                               (b:as-rvalue)))
(entry:end-with-return nil sum)

(local result (ctxt:compile))
(print (result:call-i32 "add" [2 3])) ; 5

(result:drop)
(ctxt:drop)
```

## Function Invocation from Fennel

`ResultRef` provides callable helpers:

- `call-i32(name [, args])`
- `call-i64(name [, args])`
- `call-double(name [, args])`
- `call-void(name [, args])`
- `call-word(name [, args])`
- `call-pointer(name [, args])`
- `call-void-word(name [, args])`

These are intended for direct runtime use in Fennel tests/tools. C++ integrations can use `get-code-address`/`get-global-address`.

Current helper limits:
- `call-i32`: up to 6 integer args
- `call-i64`: up to 4 integer args
- `call-double`: up to 8 double args
- `call-void`: up to 2 integer args
- `call-word`/`call-pointer`: up to 8 machine-word args (`uintptr_t` ABI path)
- `call-void-word`: up to 4 machine-word args

Use `call-word`/`call-pointer` for generic integer/pointer signatures from Fennel.
For mixed floating-point + integer/pointer signatures, use `get-code-address` from C++.

## Logfile Lifecycle

- `ContextRef:set-logfile(path)` replaces any prior logfile handle.
- `ContextRef:clear-logfile()` detaches and closes the logfile.

## Tests

- `assets/lua/tests/test-gccjit.fnl`
- Included in slow suite: `assets/lua/tests/slow.fnl`
- C++ binding smoke test: `tests/test_lua_gccjit_binding.cpp`

Note: deeper stress cases around child-context chaining/vector-heavy IR are kept out of default CI runs on this distro due an upstream GCC 12 `libgccjit` ICE.
Set `GCCJIT_STRESS=1` to enable those extra tests explicitly.


## See also

- [[subsystems/build]]
