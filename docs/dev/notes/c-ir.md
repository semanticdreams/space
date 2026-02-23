# C IR Module

`assets/lua/c-ir.fnl` provides a backend-agnostic C program abstraction.

Use one IR to target:
- `c-builder` for source-file generation
- `gccjit` for runtime JIT compilation

## API

```fennel
(local c-ir (require :c-ir))
(local IR (c-ir.Factory))
```

Core constructors:
- `IR.Type(name [, opts])`
- `IR.StructType(name [, opts])`
- `IR.UnionType(name [, opts])`
- `IR.EnumType(name [, opts])`
- `IR.Param(name, type)`
- `IR.StructField(name, type)`
- `IR.EnumItem(name [, value])`
- `IR.Struct(name, fields)`
- `IR.Union(name, fields)`
- `IR.Enum(name, items)`
- `IR.Global(name, type [, init [, opts]])`
- `IR.Int(value)`
- `IR.Double(value)`
- `IR.StringLiteral(value)`
- `IR.InitList(values)`
- `IR.DesignatedInit(field, expr)`
- `IR.Null(type)`
- `IR.Var(name)`
- `IR.Binary(op, lhs, rhs [, opts])`
- `IR.Unary(op, expr [, opts])`
- `IR.Compare(op, lhs, rhs)`
- `IR.Cast(type, expr)`
- `IR.AddressOf(expr)`
- `IR.Deref(expr)`
- `IR.Field(base, field-name [, opts])`
- `IR.Index(base, index)`
- `IR.Call(name, args)`
- `IR.FunctionRef(name)`
- `IR.CallPtr(fn-expr, args, {:return-type ... :param-types [...] [:variadic true]})`
- `IR.Return(expr)`
- `IR.Declare(name, type [, init])`
- `IR.Assign(target, expr)` (`target` can be name or lvalue expression)
- `IR.Expr(expr)`
- `IR.Break()`
- `IR.Continue()`
- `IR.Block(body)`
- `IR.If(condition, then-body [, else-body])`
- `IR.While(condition, body)`
- `IR.DoWhile(body, condition)`
- `IR.For(init, condition, post, body)`
- `IR.SwitchCase(value, body)`
- `IR.Switch(expr, cases [, default-body])`
- `IR.Function(name, return-type, params, body [, opts])`
- `IR.Program({:includes ... :enums ... :structs ... :unions ... :globals ... :functions ...})`

Backends:
- `c-ir.to-c-builder(program)`
- `c-ir.write-file(program, path [, opts])`
- `c-ir.compile-jit(program [, opts])`
- `c-ir.validate-program(program, backend)`

Validation is strict and fails loudly:
- function call arity must match
- call argument types must be assignable to parameter types
- declaration initializers and assignments must be assignable to declared variable types
- return expressions must be assignable to function return type
- unreachable statements after terminators are rejected
- `break`/`continue` placement is validated
- `switch` operand and case values must be integral
- field/index/deref/address-of usage is type-checked
- init-lists are validated against struct/union member layout

Type compatibility currently follows practical C-like rules for:
- numeric assignments/conversions (`int`/`float`/`double`/etc.)
- usual arithmetic result inference for mixed numeric binary operations
- pointer compatibility for same-type pointers and `void*`-compatible cases

## Example

```fennel
(local c-ir (require :c-ir))
(local IR (c-ir.Factory))
(local int-t (IR.Type "int"))

(local program
  (IR.Program
    {:functions
     [(IR.Function "abs-val" int-t
                   [(IR.Param "x" int-t)]
                   [(IR.If (IR.Compare "<" (IR.Var "x") (IR.Int 0))
                           [(IR.Return (IR.Binary "-" (IR.Int 0) (IR.Var "x")))]
                           nil)
                    (IR.Return (IR.Var "x"))])
      (IR.Function "main" int-t []
                   [(IR.Return (IR.Binary "-"
                                        (IR.Call "abs-val" [(IR.Int -42)])
                                        (IR.Int 42)))])]}))

(c-ir.validate-program program :c-builder)
(c-ir.validate-program program :gccjit)

(local jit (c-ir.compile-jit program))
(print (jit:call-i32 "abs-val" [-42])) ; 42
(print (jit:call-i32 "main")) ; 0
(jit:drop)

(c-ir.write-file program "./generated.c")
```

## Tests

- `assets/lua/tests/test-c-ir.fnl`

This suite verifies the same IR produces equivalent behavior through both backends.
It is part of the slow suite (`tests.slow`) alongside `test-gccjit`.
Coverage includes structs/globals, pointers/address/deref, field access, while loops,
break/continue, switch/case, unary ops, and casts.
Coverage now also includes `for`, `do-while`, enum/union declarations, and init-list initializers.
It also includes designated init-list entries and implicit numeric argument conversion in calls.
Function-pointer-style invocation is supported via `FunctionRef` + `CallPtr`.

## Usage Ideas

- Shared implementation for offline + runtime:
  - Build function logic once in `c-ir`, write C sources for offline binaries/libraries with `c-builder`, and JIT the same logic at runtime with `gccjit`.
- Validation gate in codegen pipelines:
  - Run `c-ir.validate-program` in generation steps to fail early on arity/type/return mismatches before invoking compilers.
- A/B backend checks during development:
  - In tests, run the same IR through `c-ir.compile-jit` and through `c-ir.write-file` + `native-build` to detect lowering drift.
- Runtime specialization:
  - Generate small IR variants from runtime settings (constants, thresholds, modes), JIT them, and call them via `call-i32`/`call-double`.
- Stable artifact emission:
  - Use `c-ir` for authoring, emit reviewable `.c` files in CI or release builds, and keep JIT only for local/interactive workflows.
- Incremental migration:
  - Start by wrapping existing generated C snippets in IR nodes, then gradually replace stringly codegen with structured `Type`/`Function`/`If`/`Binary` forms.
