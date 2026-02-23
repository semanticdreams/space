(local tests [])
(local fs (require :fs))
(local c-builder (require :c-builder))
(local native-build (require :native-build))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "c-builder-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "c-builder-" (os.time) "-" temp-counter)))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  dir)

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn trim [text]
  (string.gsub text "^%s*(.-)%s*$" "%1"))

(fn test-hello-world-render []
  (local C (c-builder.Factory))
  (local code (C.sequence))
  (code:append (C.sysinclude "stdio.h"))
  (code:append (C.blank))
  (local char-ptr (C.type "char" {:pointer true}))
  (code:append
    (C.declaration
      (C.function "main" "int"
                  {:params [(C.variable "argc" "int")
                            (C.variable "argv" char-ptr {:pointer true})]})))
  (local body (C.block))
  (body:append (C.statement (C.func-call "printf" (C.str-literal "Hello World\\n"))))
  (body:append (C.statement (C.func-return 0)))
  (code:append body)

  (local writer (c-builder.Writer (c-builder.Style)))
  (local rendered (writer:write-str code))
  (assert (string.find rendered "#include <stdio.h>" 1 true) "must include stdio")
  (assert (string.find rendered "int main%(int argc, char %*%*argv%)" 1) "must render pointer-aligned argv")
  (assert (string.find rendered "printf%(\"Hello World\\\\n\"%)" 1) "must render printf call")
  (assert (string.find rendered "return 0;" 1 true) "must render return statement"))

(fn test-header-guard-and-extern []
  (local C (c-builder.Factory))
  (local code (C.sequence))
  (code:append (C.ifndef "INCLUDE_GUARD_H"))
  (code:append (C.define "INCLUDE_GUARD_H"))
  (code:append (C.blank))
  (code:append (C.ifndef "__cplusplus"))
  (code:append (C.line [(C.extern "C") "{"]))
  (code:append (C.endif))
  (code:append (C.blank))
  (code:append (C.line-comment " PLACEHOLDER"))
  (code:append (C.blank))
  (code:append (C.ifndef "__cplusplus"))
  (code:append (C.line "}"))
  (code:append [(C.endif) (C.line-comment " __cplusplus")])
  (code:append [(C.endif) (C.line-comment " INCLUDE_GUARD_H")])

  (local writer (c-builder.Writer (c-builder.Style)))
  (local rendered (writer:write-str code))
  (assert (string.find rendered "#ifndef INCLUDE_GUARD_H" 1 true) "must emit include guard start")
  (assert (string.find rendered "extern \"C\" {" 1 true) "must emit extern c block")
  (assert (string.find rendered "// PLACEHOLDER" 1 true) "must emit comments")
  (assert (string.find rendered "#endif // INCLUDE_GUARD_H" 1 true) "must emit include guard end comment"))

(fn test-struct-typedef-and-initializer []
  (local C (c-builder.Factory))
  (local code (C.sequence))
  (local s (C.struct "mystruct"
                     [(C.struct-member "field_1" "int")
                      (C.struct-member "field_2" "int")]))
  (local t (C.typedef "my_struct_t" (C.declaration s)))
  (code:append (C.statement (C.declaration t)))
  (code:append (C.blank))
  (code:append (C.statement (C.declaration (C.variable "instance" t) [0 0])))
  (code:append (C.statement (C.declaration (C.variable "named" t) {:field_1 3 :field_2 9})))

  (local writer (c-builder.Writer (c-builder.Style)))
  (local rendered (writer:write-str code))
  (assert (string.find rendered "typedef struct mystruct {" 1 true) "must emit typedef struct")
  (assert (string.find rendered "my_struct_t instance = {0, 0};" 1 true) "must emit array-style initializer")
  (assert (string.find rendered "my_struct_t named = {" 1 true) "must emit designated initializer container")
  (assert (string.find rendered "%.field_1 = 3" 1) "must emit designated initializer field_1")
  (assert (string.find rendered "%.field_2 = 9" 1) "must emit designated initializer field_2"))

(fn test-comments-and-line []
  (local C (c-builder.Factory))
  (local code (C.sequence))
  (code:append (C.line-comment " top "))
  (code:append (C.blank))
  (code:append (C.line (C.block-comment " block ")))
  (code:append (C.blank))
  (code:append (C.block-comment ["A" "B"] {:width 10 :line-start "* "}))
  (code:append (C.blank))
  (code:append [(C.statement (C.variable "value" "int")) (C.line-comment " side" {:adjust 2})])

  (local writer (c-builder.Writer (c-builder.Style)))
  (local rendered (writer:write-str code))
  (assert (string.find rendered "// top " 1 true) "must emit line comment")
  (assert (string.find rendered "/* block */" 1 true) "must emit inline block comment")
  (assert (string.find rendered "/%*%*%*%*%*%*%*%*%*%*" 1) "must emit sized block comment")
  (assert (string.find rendered "value;" 1 true) "must render statement in array line element")
  (assert (string.find rendered "// side" 1 true) "must render side comment in array line element"))

(fn test-write-str-elem []
  (local C (c-builder.Factory))
  (local writer (c-builder.Writer (c-builder.Style)))
  (local text (writer:write-str-elem (C.statement (C.assignment "a" 1))))
  (assert (= text "a = 1;") "write-str-elem should trim trailing newline by default"))

(fn test-generated-c-compiles-and-runs []
  (with-temp-dir
    (fn [dir]
      (local C (c-builder.Factory))
      (local code (C.sequence))
      (code:append (C.sysinclude "stdio.h"))
      (code:append (C.blank))
      (code:append (C.statement (C.declaration (C.variable "global_counter" "int") 7)))
      (code:append (C.blank))
      (code:append (C.declaration (C.function "main" "int")))
      (local body (C.block))
      (body:append (C.statement (C.func-call "printf" [(C.str-literal "generated-%d\\n") "global_counter"])))
      (body:append (C.statement (C.func-return 0)))
      (code:append body)

      (local source (fs.join-path dir "generated.c"))
      (local writer (c-builder.Writer (c-builder.Style)))
      (writer:write-file code source)

      (local compiler (native-build.Gcc {:standard "c11"}))
      (local project (native-build.Project {:name (fs.join-path dir "generated-app")
                                            :compiler compiler
                                            :build-dir (fs.join-path dir "obj")}))
      (project:add-executable source)
      (local binary (project:build))
      (assert (fs.exists binary) "compiled binary should exist")
      (local run-result (project:run))
      (assert (= run-result.exit-code 0)
              "compiled generated code should run successfully")
      (assert (string.find run-result.stdout "generated" 1 true)
              "compiled generated code should print generated marker"))))

(table.insert tests {:name "c-builder hello world render" :fn test-hello-world-render})
(table.insert tests {:name "c-builder header guard and extern" :fn test-header-guard-and-extern})
(table.insert tests {:name "c-builder struct typedef initializer" :fn test-struct-typedef-and-initializer})
(table.insert tests {:name "c-builder comments and line elements" :fn test-comments-and-line})
(table.insert tests {:name "c-builder write-str-elem" :fn test-write-str-elem})
(table.insert tests {:name "c-builder integration compile and run" :fn test-generated-c-compiles-and-runs})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "c-builder"
                       :tests tests})))

{:name "c-builder"
 :tests tests
 :main main}
