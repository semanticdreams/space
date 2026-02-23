# C Builder Module

`assets/lua/c-builder.fnl` is a C code-generation module for Fennel.

It provides:

- A factory API for building C AST nodes
- A configurable writer/formatter
- Loud failure on invalid node shapes or unsupported input

## Quick Start

```fennel
(local c-builder (require :c-builder))
(local C (c-builder.Factory))

(local code (C.sequence))
(code:append (C.sysinclude "stdio.h"))
(code:append (C.blank))
(code:append (C.declaration (C.function "main" "int")))

(local body (C.block))
(body:append (C.statement (C.func-call "printf" (C.str-literal "hello\\n"))))
(body:append (C.statement (C.func-return 0)))
(code:append body)

(local writer (c-builder.Writer (c-builder.Style)))
(local out (writer:write-str code))
```

## Main API

Factory methods (`C = (c-builder.Factory)`):

- Structure: `sequence`, `block`, `line`, `blank`, `whitespace`
- Comments: `line-comment`, `block-comment`
- Directives: `include`, `sysinclude`, `define`, `ifdef`, `ifndef`, `endif`, `extern`
- Types/declarations: `type`, `struct-member`, `struct`, `typedef`, `variable`, `function`, `declaration`
- Expressions/statements: `assignment`, `str-literal`, `func-call`, `func-return`, `statement`

Writer methods:

- `writer:write-str(sequence-or-block)`
- `writer:write-str-elem(element {:trim-end true|false})`
- `writer:write-file(sequence-or-block path)`

## Style

Use `c-builder.Style` to configure output.

Supported style enums:

- `c-builder.BraceStyle` (`:attach`, `:allman`, `:linux`)
- `c-builder.PointerAlignment` (`:left`, `:right`, `:middle`)
- `c-builder.ShortFunctionStyle` (`:never`, `:empty`, `:inline`)

Default style is tuned for common C output:

- Attached braces
- Right pointer alignment
- 4-space indentation

## Initializers

Declarations support extended initializer values:

- Scalar: `1`, `"text"`, `true/false`
- Array-style: `[1 2 3]`
- Nested arrays
- Designated object-style tables:
  - `{:field_1 10 :field_2 20}` -> `{.field_1 = 10, .field_2 = 20}`

## Integration with native-build

`c-builder` is generation-only. Use `native-build` to compile/run generated code:

```fennel
(local c-builder (require :c-builder))
(local native-build (require :native-build))

(local C (c-builder.Factory))
(local code (C.sequence))
;; ... build code ...

(local src "generated.c")
((c-builder.Writer (c-builder.Style)):write-file code src)

(local compiler (native-build.Gcc {:standard "c11"}))
(local project (native-build.Project {:name "generated-app"
                                      :compiler compiler
                                      :build-dir "__pysembled__"}))
(project:add-executable src)
(project:build)
(project:run)
```

## Tests

Dedicated tests are in:

- `assets/lua/tests/test-c-builder.fnl`

The suite includes an integration test that compiles and runs generated C via `native-build`.
