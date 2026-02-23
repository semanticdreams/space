(local tests [])
(local fs (require :fs))
(local gccjit (require :gccjit))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "gccjit-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "gccjit-" (os.time) "-" temp-counter)))
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

(fn i32 [ctxt]
  (ctxt:get-type (. gccjit.Types "int")))

(fn i64 [ctxt]
  (ctxt:get-type (. gccjit.Types "long-long")))

(fn f64 [ctxt]
  (ctxt:get-type (. gccjit.Types "double")))

(fn assert-error [label f]
  (local (ok _err) (pcall f))
  (assert (not ok) label))

(fn test-version-and-enums []
  (assert (>= (gccjit:version-major) 1) "libgccjit major version should be >= 1")
  (assert (>= (gccjit:version-minor) 0) "libgccjit minor version should be >= 0")
  (assert (>= (gccjit:version-patchlevel) 0) "libgccjit patchlevel should be >= 0")
  (assert (= (type (. gccjit.FunctionKind "exported")) "number") "function kind must be numeric")
  (assert (= (type (. gccjit.BinaryOp "plus")) "number") "binary op must be numeric")
  (assert (= (type (. gccjit.OutputKind "object-file")) "number") "output kind must be numeric"))

(fn test-compile-and-call-i32 []
  (local ctxt (gccjit.Context))
  (local int-type (i32 ctxt))
  (local a (ctxt:new-param nil int-type "a"))
  (local b (ctxt:new-param nil int-type "b"))
  (local add-fn (ctxt:new-function nil (. gccjit.FunctionKind "exported") int-type "add_i32" [a b] false))
  (local entry (add-fn:new-block "entry"))
  (local sum (ctxt:new-binary-op nil (. gccjit.BinaryOp "plus") int-type (a:as-rvalue) (b:as-rvalue)))
  (entry:end-with-return nil sum)

  (local result (ctxt:compile))
  (assert (= (result:call-i32 "add_i32" [8 9]) 17) "jit i32 function should execute")
  (assert (= (result:call-word "add_i32" [5 7]) 12) "word-call helper should execute")
  (assert (> (result:get-code-address "add_i32") 0) "code address should be non-zero")

  (result:drop)
  (ctxt:drop))

(fn test-compile-and-call-i64-and-double []
  (local ctxt (gccjit.Context))

  (local ll-type (i64 ctxt))
  (local i-type (i32 ctxt))
  (local d-type (f64 ctxt))

  (local x (ctxt:new-param nil i-type "x"))
  (local widen (ctxt:new-function nil (. gccjit.FunctionKind "exported") ll-type "widen_i64" [x] false))
  (local widen-entry (widen:new-block "entry"))
  (local widened (ctxt:new-cast nil (x:as-rvalue) ll-type))
  (widen-entry:end-with-return nil widened)

  (local d (ctxt:new-param nil d-type "d"))
  (local half (ctxt:new-function nil (. gccjit.FunctionKind "exported") d-type "half_double" [d] false))
  (local half-entry (half:new-block "entry"))
  (local half-value (ctxt:new-binary-op nil (. gccjit.BinaryOp "divide") d-type
                                        (d:as-rvalue)
                                        (ctxt:new-rvalue-from-double d-type 2.0)))
  (half-entry:end-with-return nil half-value)

  (local result (ctxt:compile))
  (assert (= (result:call-i64 "widen_i64" [42]) 42) "jit i64 function should execute")
  (assert (= (result:call-double "half_double" [5.0]) 2.5) "jit double function should execute")

  (result:drop)
  (ctxt:drop))

(fn test-struct-fields-and-conditional []
  (local ctxt (gccjit.Context))
  (local int-type (i32 ctxt))

  (local field-a (ctxt:new-field nil int-type "a"))
  (local field-b (ctxt:new-field nil int-type "b"))
  (local pair-struct (ctxt:new-struct-type nil "pair" [field-a field-b]))
  (local pair-type (pair-struct:as-type))

  (local calc (ctxt:new-function nil (. gccjit.FunctionKind "exported") int-type "struct_sum" [] false))
  (local calc-entry (calc:new-block "entry"))
  (local pair-local (calc:new-local nil pair-type "p"))
  (local a-slot (pair-local:access-field nil field-a))
  (local b-slot (pair-local:access-field nil field-b))
  (calc-entry:add-assignment nil a-slot (ctxt:new-rvalue-from-int int-type 11))
  (calc-entry:add-assignment nil b-slot (ctxt:new-rvalue-from-int int-type 9))
  (local pair-sum (ctxt:new-binary-op nil (. gccjit.BinaryOp "plus") int-type
                                      (a-slot:as-rvalue)
                                      (b-slot:as-rvalue)))
  (calc-entry:end-with-return nil pair-sum)

  (local x (ctxt:new-param nil int-type "x"))
  (local abs-fn (ctxt:new-function nil (. gccjit.FunctionKind "exported") int-type "abs_i32" [x] false))
  (local abs-entry (abs-fn:new-block "entry"))
  (local neg-block (abs-fn:new-block "neg"))
  (local keep-block (abs-fn:new-block "keep"))

  (local cond (ctxt:new-comparison nil (. gccjit.Comparison "lt")
                                   (x:as-rvalue)
                                   (ctxt:new-rvalue-from-int int-type 0)))
  (abs-entry:end-with-conditional nil cond neg-block keep-block)
  (neg-block:end-with-return nil
    (ctxt:new-unary-op nil (. gccjit.UnaryOp "minus") int-type (x:as-rvalue)))
  (keep-block:end-with-return nil (x:as-rvalue))

  (local result (ctxt:compile))
  (assert (= (result:call-i32 "struct_sum") 20) "struct local/field operations should work")
  (assert (= (result:call-i32 "abs_i32" [-15]) 15) "conditional branch should work")
  (assert (= (result:call-i32 "abs_i32" [6]) 6) "conditional else branch should work")

  (result:drop)
  (ctxt:drop))

(fn test-switch-and-global-export []
  (local ctxt (gccjit.Context))
  (local int-type (i32 ctxt))

  (local g (ctxt:new-global nil (. gccjit.GlobalKind "exported") int-type "g_counter"))

  (local classify-param (ctxt:new-param nil int-type "x"))
  (local classify (ctxt:new-function nil (. gccjit.FunctionKind "exported") int-type "classify" [classify-param] false))
  (local entry (classify:new-block "entry"))
  (local on-one (classify:new-block "on_one"))
  (local on-two (classify:new-block "on_two"))
  (local on-default (classify:new-block "on_default"))

  (local one (ctxt:new-rvalue-from-int int-type 1))
  (local two (ctxt:new-rvalue-from-int int-type 2))
  (local case-one (ctxt:new-case one one on-one))
  (local case-two (ctxt:new-case two two on-two))

  (entry:end-with-switch nil (classify-param:as-rvalue) on-default [case-one case-two])
  (on-one:end-with-return nil (ctxt:new-rvalue-from-int int-type 101))
  (on-two:end-with-return nil (ctxt:new-rvalue-from-int int-type 202))
  (on-default:end-with-return nil (ctxt:new-rvalue-from-int int-type 303))

  (local read-global (ctxt:new-function nil (. gccjit.FunctionKind "exported") int-type "read_global" [] false))
  (local global-entry (read-global:new-block "entry"))
  (global-entry:end-with-return nil (g:as-rvalue))
  (local write-global (ctxt:new-function nil (. gccjit.FunctionKind "exported") int-type "write_global" [] false))
  (local write-entry (write-global:new-block "entry"))
  (write-entry:add-assignment nil g (ctxt:new-rvalue-from-int int-type 13))
  (write-entry:end-with-return nil (g:as-rvalue))

  (local result (ctxt:compile))
  (assert (= (result:call-i32 "classify" [1]) 101) "switch case one should hit")
  (assert (= (result:call-i32 "classify" [2]) 202) "switch case two should hit")
  (assert (= (result:call-i32 "classify" [8]) 303) "switch default should hit")
  (assert (= (result:call-i32 "read_global") 0) "global default value should be readable")
  (assert (= (result:call-i32 "write_global") 13) "global assignment should be writable")
  (assert (= (result:call-i32 "read_global") 13) "global write should persist")
  (assert (> (result:get-global-address "g_counter") 0) "global address should be non-zero")

  (result:drop)
  (ctxt:drop))

(fn test-compile-to-file-dumps-and-timer []
  (with-temp-dir
    (fn [dir]
      (local ctxt (gccjit.Context))
      (ctxt:set-str-option (. gccjit.StrOption "progname") "space-test-gccjit")
      (ctxt:set-int-option (. gccjit.IntOption "optimization-level") 1)
      (ctxt:set-bool-option (. gccjit.BoolOption "dump-summary") false)

      (local timer (gccjit.Timer))
      (ctxt:set-timer timer)

      (local int-type (i32 ctxt))
      (local forty-two-fn (ctxt:new-function nil (. gccjit.FunctionKind "exported") int-type "forty_two" [] false))
      (local entry (forty-two-fn:new-block "entry"))
      (entry:end-with-return nil (ctxt:new-rvalue-from-int int-type 42))

      (local c-dump (fs.join-path dir "jit-dump.c"))
      (local repro (fs.join-path dir "jit-reproducer.c"))
      (local out-obj (fs.join-path dir "jit-output.o"))
      (local timer-out (fs.join-path dir "timer.txt"))
      (local log-out (fs.join-path dir "gccjit.log"))

      (ctxt:set-logfile log-out)
      (ctxt:dump-to-file c-dump true)
      (ctxt:dump-reproducer-to-file repro)
      (ctxt:compile-to-file (. gccjit.OutputKind "object-file") out-obj)
      (local borrowed-timer (ctxt:get-timer))
      (borrowed-timer:push "phase")
      (borrowed-timer:pop "phase")
      (timer:print-to-path timer-out)
      (ctxt:clear-logfile)

      (assert (fs.exists c-dump) "dump-to-file output should exist")
      (assert (fs.exists repro) "reproducer output should exist")
      (assert (fs.exists out-obj) "compile-to-file output should exist")
      (assert (fs.exists timer-out) "timer output should exist")
      (assert (fs.exists log-out) "log output should exist")

      (timer:drop)
      (ctxt:drop))))

(fn test-child-context-and-vector []
  (local parent (gccjit.Context))
  (local int-type (i32 parent))
  (local vec-type (int-type:get-vector 4))
  (assert vec-type "vector type should be created")
  (local aligned-int (int-type:get-aligned 8))
  (assert aligned-int "aligned type should be created")
  (local lane0 (parent:new-rvalue-from-int int-type 1))
  (local lane1 (parent:new-rvalue-from-int int-type 2))
  (local lane2 (parent:new-rvalue-from-int int-type 3))
  (local lane3 (parent:new-rvalue-from-int int-type 4))
  (local _vec (parent:new-rvalue-from-vector nil vec-type [lane0 lane1 lane2 lane3]))

  (local child (parent:new-child-context))
  (local child-fn (child:new-function nil (. gccjit.FunctionKind "exported") int-type "child_value" [] false))
  (local child-entry (child-fn:new-block "entry"))
  (child-entry:end-with-return nil (child:new-rvalue-from-int int-type 42))
  (local child-result (child:compile))
  (assert (= (child-result:call-i32 "child_value") 42) "child context compile should work")

  (child-result:drop)
  (child:drop)
  (parent:drop))

(fn test-error-paths []
  (local ctxt (gccjit.Context))
  (local int-type (i32 ctxt))
  (local bad (ctxt:new-function nil (. gccjit.FunctionKind "exported") int-type "bad" [] false))
  (bad:new-block "entry")
  (assert-error "compiling function with unterminated block must throw"
    (fn [] (ctxt:compile)))
  (ctxt:drop))

(table.insert tests {:name "gccjit version/enums" :fn test-version-and-enums})
(table.insert tests {:name "gccjit compile/call i32" :fn test-compile-and-call-i32})
(table.insert tests {:name "gccjit compile/call i64 and double" :fn test-compile-and-call-i64-and-double})
(table.insert tests {:name "gccjit struct fields and conditional" :fn test-struct-fields-and-conditional})
(table.insert tests {:name "gccjit switch and globals" :fn test-switch-and-global-export})
(table.insert tests {:name "gccjit compile-to-file dumps timer" :fn test-compile-to-file-dumps-and-timer})

(when (os.getenv "GCCJIT_STRESS")
  (table.insert tests {:name "gccjit child context and vector" :fn test-child-context-and-vector})
  (table.insert tests {:name "gccjit error paths" :fn test-error-paths}))

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "gccjit"
                       :tests tests})))

{:name "gccjit"
 :tests tests
 :main main}
