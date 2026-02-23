(local tests [])
(local fs (require :fs))
(local c-ir (require :c-ir))
(local native-build (require :native-build))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "c-ir-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "c-ir-" (os.time) "-" temp-counter)))
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

(fn assert-error [label f]
  (local (ok _err) (pcall f))
  (assert (not ok) label))

(fn build-shared-integration-program []
  (local IR (c-ir.Factory))
  (local int-t (IR.Type "int"))
  (local double-t (IR.Type "double"))
  (IR.Program
    {:functions
     [(IR.Function "inc1" int-t
                   [(IR.Param "x" int-t)]
                   [(IR.Return (IR.Binary "+" (IR.Var "x") (IR.Int 1)))])
      (IR.Function "inc2" int-t
                   [(IR.Param "x" int-t)]
                   [(IR.Return (IR.Binary "+"
                                        (IR.Call "inc1" [(IR.Var "x")])
                                        (IR.Int 1)))])
      (IR.Function "classify" int-t
                   [(IR.Param "x" int-t)]
                   [(IR.If (IR.Compare "<" (IR.Var "x") (IR.Int 0))
                           [(IR.If (IR.Compare "<" (IR.Var "x") (IR.Int -10))
                                   [(IR.Return (IR.Int 2))]
                                   [(IR.Return (IR.Int 1))])]
                           [(IR.Return (IR.Int 0))])])
      (IR.Function "blend" double-t
                   [(IR.Param "a" double-t) (IR.Param "b" double-t)]
                   [(IR.Declare "sum" double-t (IR.Binary "+" (IR.Var "a") (IR.Var "b")))
                    (IR.If (IR.Compare ">" (IR.Var "sum") (IR.Double 10.0))
                           [(IR.Return (IR.Binary "/" (IR.Var "sum") (IR.Double 2.0)))]
                           [(IR.Return (IR.Binary "+" (IR.Var "sum") (IR.Double 0.5)))])])
      (IR.Function "abs_val" int-t
                   [(IR.Param "x" int-t)]
                   [(IR.If (IR.Compare "<" (IR.Var "x") (IR.Int 0))
                           [(IR.Return (IR.Binary "-" (IR.Int 0) (IR.Var "x")))]
                           nil)
                    (IR.Return (IR.Var "x"))])
      (IR.Function "main" int-t []
                   [(IR.Return
                      (IR.Binary "+"
                                 (IR.Binary "-"
                                            (IR.Call "inc2" [(IR.Int 40)])
                                            (IR.Int 42))
                                 (IR.Binary "-"
                                            (IR.Call "classify" [(IR.Int -12)])
                                            (IR.Int 2))))])]}))

(fn build-general-program []
  (local IR (c-ir.Factory))
  (local int-t (IR.Type "int"))
  (local int-ptr-t (IR.Type "int" {:pointer 1}))
  (local pair-t (IR.StructType "pair"))
  (local pair-ptr-t (IR.StructType "pair" {:pointer 1}))
  (IR.Program
    {:structs
     [(IR.Struct "pair"
                 [(IR.StructField "a" int-t)
                  (IR.StructField "b" int-t)])]
     :globals
     [(IR.Global "g_counter" int-t (IR.Int 0))]
     :functions
     [(IR.Function "bump_ptr" int-t
                   [(IR.Param "p" int-ptr-t)]
                   [(IR.Assign (IR.Deref (IR.Var "p"))
                               (IR.Binary "+"
                                          (IR.Deref (IR.Var "p"))
                                          (IR.Int 5)))
                    (IR.Return (IR.Index (IR.Var "p") (IR.Int 0)))])
      (IR.Function "pair_sum" int-t
                   [(IR.Param "p" pair-ptr-t)]
                   [(IR.Return (IR.Binary "+"
                                        (IR.Field (IR.Var "p") "a" {:pointer true})
                                        (IR.Field (IR.Var "p") "b" {:pointer true})))])
      (IR.Function "dispatch" int-t
                   [(IR.Param "n" int-t)]
                   [(IR.Declare "i" int-t (IR.Int 0))
                    (IR.Declare "acc" int-t (IR.Int 0))
                    (IR.While (IR.Compare "<" (IR.Var "i") (IR.Var "n"))
                              [(IR.Assign "g_counter" (IR.Binary "+" (IR.Var "g_counter") (IR.Int 1)))
                               (IR.If (IR.Compare "==" (IR.Var "i") (IR.Int 5))
                                      [(IR.Assign "i" (IR.Binary "+" (IR.Var "i") (IR.Int 1)))
                                       (IR.Continue)]
                                      nil)
                               (IR.If (IR.Compare "==" (IR.Var "i") (IR.Int 8))
                                      [(IR.Break)]
                                      nil)
                               (IR.Assign "acc" (IR.Binary "+" (IR.Var "acc") (IR.Var "i")))
                               (IR.Assign "i" (IR.Binary "+" (IR.Var "i") (IR.Int 1)))])
                    (IR.Switch (IR.Var "n")
                               [(IR.SwitchCase (IR.Int 0) [(IR.Return (IR.Int 100))])
                                (IR.SwitchCase (IR.Int 10) [(IR.Return (IR.Var "acc"))])]
                               [(IR.Return (IR.Binary "+" (IR.Var "acc") (IR.Int 1)))])])
      (IR.Function "to_int" int-t
                   [(IR.Param "x" int-t)]
                   [(IR.Return (IR.Cast int-t (IR.Cast (IR.Type "double") (IR.Var "x"))))])
      (IR.Function "main" int-t []
                   [(IR.Declare "x" int-t (IR.Int 10))
                    (IR.Declare "p" pair-t nil)
                    (IR.Assign (IR.Field (IR.Var "p") "a") (IR.Int 7))
                    (IR.Assign (IR.Field (IR.Var "p") "b") (IR.Int 9))
                    (IR.Declare "bumped" int-t (IR.Call "bump_ptr" [(IR.AddressOf (IR.Var "x"))]))
                    (IR.Declare "psum" int-t (IR.Call "pair_sum" [(IR.AddressOf (IR.Var "p"))]))
                    (IR.Declare "disp" int-t (IR.Call "dispatch" [(IR.Int 10)]))
                    (IR.Declare "extra" int-t (IR.Call "to_int" [(IR.Unary "-" (IR.Int -3))]))
                    (IR.Return (IR.Binary "-"
                                        (IR.Binary "+"
                                                   (IR.Binary "+"
                                                              (IR.Binary "+"
                                                                         (IR.Var "bumped")
                                                                         (IR.Var "psum"))
                                                              (IR.Var "disp"))
                                                   (IR.Binary "+"
                                                              (IR.Var "g_counter")
                                                              (IR.Var "extra")))
                                        (IR.Int 66)))])]}))

(fn build-extended-control-and-adt-program []
  (local IR (c-ir.Factory))
  (local int-t (IR.Type "int"))
  (local union-num-t (IR.UnionType "num"))
  (IR.Program
    {:enums
     [(IR.Enum "color"
               [(IR.EnumItem "COLOR_RED" (IR.Int 1))
                (IR.EnumItem "COLOR_GREEN" (IR.Int 2))
                (IR.EnumItem "COLOR_BLUE" (IR.Int 4))])]
     :unions
     [(IR.Union "num"
                [(IR.StructField "i" int-t)
                 (IR.StructField "j" int-t)])]
     :functions
     [(IR.Function "for_and_do" int-t []
                   [(IR.Declare "acc" int-t (IR.Int 0))
                    (IR.For (IR.Declare "i" int-t (IR.Int 0))
                            (IR.Compare "<" (IR.Var "i") (IR.Int 6))
                            (IR.Assign "i" (IR.Binary "+" (IR.Var "i") (IR.Int 1)))
                            [(IR.If (IR.Compare "==" (IR.Var "i") (IR.Int 3))
                                    [(IR.Continue)]
                                    nil)
                             (IR.Assign "acc" (IR.Binary "+" (IR.Var "acc") (IR.Var "i")))])
                    (IR.Declare "k" int-t (IR.Int 0))
                    (IR.DoWhile
                      [(IR.Assign "acc" (IR.Binary "+" (IR.Var "acc") (IR.Int 1)))
                       (IR.Assign "k" (IR.Binary "+" (IR.Var "k") (IR.Int 1)))]
                      (IR.Compare "<" (IR.Var "k") (IR.Int 2)))
                    (IR.Return (IR.Var "acc"))])
      (IR.Function "union_init" int-t []
                   [(IR.Declare "u" union-num-t (IR.InitList [(IR.Int 9)]))
                    (IR.Return (IR.Field (IR.Var "u") "i"))])
      (IR.Function "main" int-t []
                   [(IR.Return (IR.Binary "-"
                                        (IR.Binary "+"
                                                   (IR.Call "for_and_do" [])
                                                   (IR.Call "union_init" []))
                                        (IR.Int 23)))])]}))

(fn test-jit-and-native-build-share-ir-extended []
  (with-temp-dir
    (fn [dir]
      (local program (build-shared-integration-program))
      (assert (c-ir.validate-program program :c-builder) "program must validate for c-builder")
      (assert (c-ir.validate-program program :gccjit) "program must validate for gccjit")

      (local jit (c-ir.compile-jit program))
      (assert (= (jit:call-i32 "abs_val" [-42]) 42) "jit backend should execute shared abs IR")
      (assert (= (jit:call-i32 "inc2" [40]) 42) "jit call chain should execute across functions")
      (assert (= (jit:call-i32 "classify" [-12]) 2) "jit nested if should execute selected branch")
      (assert (= (jit:call-double "blend" [8.0 4.0]) 6.0) "jit double math should execute")
      (assert (= (jit:call-i32 "main") 0) "jit backend main should normalize to process success")
      (jit:drop)

      (local src (fs.join-path dir "generated.c"))
      (c-ir.write-file program src)
      (assert (fs.exists src) "generated source file should exist")

      (local gcc (native-build.Gcc {:standard "c11"}))
      (local project (native-build.Project {:name (fs.join-path dir "generated-app")
                                            :compiler gcc
                                            :build-dir (fs.join-path dir "obj")}))
      (project:add-executable src)
      (local binary (project:build))
      (assert (fs.exists binary) "compiled generated executable should exist")
      (local run-result (project:run))
      (assert (= run-result.exit-code 0) "native backend should return process success for equivalent main"))))

(fn test-general-features-jit-and-native []
  (with-temp-dir
    (fn [dir]
      (local program (build-general-program))
      (assert (c-ir.validate-program program :c-builder) "general program must validate for c-builder")
      (assert (c-ir.validate-program program :gccjit) "general program must validate for gccjit")

      (local jit (c-ir.compile-jit program))
      (local jit-main (jit:call-i32 "main"))
      (assert (= jit-main 0) (.. "jit backend should execute full-feature general program, got " jit-main))
      (jit:drop)

      (local src (fs.join-path dir "general.c"))
      (c-ir.write-file program src)
      (assert (fs.exists src) "generated general source file should exist")

      (local gcc (native-build.Gcc {:standard "c11"}))
      (local project (native-build.Project {:name (fs.join-path dir "general-app")
                                            :compiler gcc
                                            :build-dir (fs.join-path dir "obj-general")}))
      (project:add-executable src)
      (local binary (project:build))
      (assert (fs.exists binary) "compiled general executable should exist")
      (local run-result (project:run))
      (assert (= run-result.exit-code 0)
              (.. "native backend should execute full-feature general program, got " run-result.exit-code)))))

(fn test-extended-control-and-adt-features []
  (with-temp-dir
    (fn [dir]
      (local program (build-extended-control-and-adt-program))
      (assert (c-ir.validate-program program :c-builder) "extended program must validate for c-builder")
      (assert (c-ir.validate-program program :gccjit) "extended program must validate for gccjit")

      (local jit (c-ir.compile-jit program))
      (local jit-main (jit:call-i32 "main"))
      (assert (= jit-main 0) (.. "jit backend should execute extended program, got " jit-main))
      (jit:drop)

      (local src (fs.join-path dir "extended.c"))
      (c-ir.write-file program src)
      (assert (fs.exists src) "generated extended source should exist")

      (local gcc (native-build.Gcc {:standard "c11"}))
      (local project (native-build.Project {:name (fs.join-path dir "extended-app")
                                            :compiler gcc
                                            :build-dir (fs.join-path dir "obj-extended")}))
      (project:add-executable src)
      (local binary (project:build))
      (assert (fs.exists binary) "compiled extended executable should exist")
      (local run-result (project:run))
      (assert (= run-result.exit-code 0)
              (.. "native backend should execute extended program, got " run-result.exit-code)))))

(fn test-designated-init-and-implicit-numeric-conversion []
  (with-temp-dir
    (fn [dir]
      (local IR (c-ir.Factory))
      (local int-t (IR.Type "int"))
      (local double-t (IR.Type "double"))
      (local point-t (IR.StructType "point"))
      (local program
        (IR.Program
          {:structs
           [(IR.Struct "point"
                       [(IR.StructField "x" int-t)
                        (IR.StructField "y" int-t)])]
	           :functions
	           [(IR.Function
	              "sum_double"
	              double-t
	              [(IR.Param "a" double-t) (IR.Param "b" double-t)]
	              [(IR.Return (IR.Binary "+" (IR.Var "a") (IR.Var "b")))])
	            (IR.Function "main" int-t []
                         [(IR.Declare "p" point-t
                                      (IR.InitList [(IR.DesignatedInit "y" (IR.Int 4))
                                                    (IR.DesignatedInit "x" (IR.Int 3))]))
                          (IR.Declare "s" double-t (IR.Call "sum_double" [(IR.Int 1) (IR.Double 2.0)]))
                          (IR.Return (IR.Binary "-"
                                              (IR.Binary "+"
                                                         (IR.Binary "+"
                                                                    (IR.Field (IR.Var "p") "x")
                                                                    (IR.Field (IR.Var "p") "y"))
                                                         (IR.Cast int-t (IR.Var "s")))
                                              (IR.Int 10)))])]}))

      (assert (c-ir.validate-program program :c-builder) "designated init program must validate for c-builder")
      (assert (c-ir.validate-program program :gccjit) "designated init program must validate for gccjit")

      (local jit (c-ir.compile-jit program))
      (local jit-main (jit:call-i32 "main"))
      (assert (= jit-main 0) (.. "jit backend should execute designated init program, got " jit-main))
      (jit:drop)

      (local src (fs.join-path dir "designated.c"))
      (c-ir.write-file program src)
      (local gcc (native-build.Gcc {:standard "c11"}))
      (local project (native-build.Project {:name (fs.join-path dir "designated-app")
                                            :compiler gcc
                                            :build-dir (fs.join-path dir "obj-designated")}))
      (project:add-executable src)
      (local _binary (project:build))
      (local run-result (project:run))
      (assert (= run-result.exit-code 0)
              (.. "native backend should execute designated init program, got " run-result.exit-code)))))

(fn test-function-pointer-call []
  (with-temp-dir
    (fn [dir]
      (local IR (c-ir.Factory))
      (local int-t (IR.Type "int"))
      (local program
        (IR.Program
	          {:functions
		           [(IR.Function
		              "add_i32"
		              int-t
		              [(IR.Param "a" int-t) (IR.Param "b" int-t)]
		              [(IR.Return (IR.Binary "+" (IR.Var "a") (IR.Var "b")))])
		            (IR.Function "main" int-t []
                         [(IR.Return
                            (IR.Binary "-"
                                       (IR.CallPtr (IR.FunctionRef "add_i32")
                                                   [(IR.Int 21) (IR.Int 21)]
                                                   {:return-type int-t
                                                    :param-types [int-t int-t]})
                                       (IR.Int 42)))])]}))

      (assert (c-ir.validate-program program :c-builder) "function ptr program must validate for c-builder")
      (assert (c-ir.validate-program program :gccjit) "function ptr program must validate for gccjit")

      (local jit (c-ir.compile-jit program))
      (local jit-main (jit:call-i32 "main"))
      (assert (= jit-main 0) (.. "jit backend should execute function ptr program, got " jit-main))
      (jit:drop)

      (local src (fs.join-path dir "fnptr.c"))
      (c-ir.write-file program src)
      (local gcc (native-build.Gcc {:standard "c11"}))
      (local project (native-build.Project {:name (fs.join-path dir "fnptr-app")
                                            :compiler gcc
                                            :build-dir (fs.join-path dir "obj-fnptr")}))
      (project:add-executable src)
      (local _binary (project:build))
      (local run-result (project:run))
      (assert (= run-result.exit-code 0)
              (.. "native backend should execute function ptr program, got " run-result.exit-code)))))

(fn test-validation-rejects-call-arity-mismatch []
  (local IR (c-ir.Factory))
  (local int-t (IR.Type "int"))
  (local program
    (IR.Program
      {:functions
       [(IR.Function "add2" int-t
                     [(IR.Param "a" int-t) (IR.Param "b" int-t)]
                     [(IR.Return (IR.Binary "+" (IR.Var "a") (IR.Var "b")))])
        (IR.Function "main" int-t []
                     [(IR.Return (IR.Call "add2" [(IR.Int 1)]))])]}))
  (assert-error "validator should reject call arity mismatch"
    (fn []
      (c-ir.validate-program program :gccjit))))

(fn test-validation-rejects-return-type-mismatch []
  (local IR (c-ir.Factory))
  (local int-t (IR.Type "int"))
  (local int-ptr-t (IR.Type "int" {:pointer 1}))
  (local program
    (IR.Program
      {:functions
       [(IR.Function "bad" int-t []
                     [(IR.Return (IR.Null int-ptr-t))])]}))
  (assert-error "validator should reject function return type mismatch"
    (fn []
      (c-ir.validate-program program :gccjit))))

(fn test-validation-rejects-assignment-type-mismatch []
  (local IR (c-ir.Factory))
  (local int-t (IR.Type "int"))
  (local int-ptr-t (IR.Type "int" {:pointer 1}))
  (local double-t (IR.Type "double"))
  (local program
    (IR.Program
      {:functions
       [(IR.Function "bad_assign" int-t []
                     [(IR.Declare "x" int-t (IR.Int 3))
                      (IR.Assign "x" (IR.Null int-ptr-t))
                      (IR.Return (IR.Int 0))])]}))
  (assert-error "validator should reject assignment type mismatch"
    (fn []
      (c-ir.validate-program program :c-builder)))

  (local program2
    (IR.Program
      {:functions
       [(IR.Function "bad_decl" double-t []
                     [(IR.Declare "x" int-t (IR.Null int-ptr-t))
                      (IR.Return (IR.Double 0.0))])]}))
  (assert-error "validator should reject declaration initializer type mismatch"
    (fn []
      (c-ir.validate-program program2 :gccjit))))

(fn test-validation-rejects-callptr-shape-errors []
  (local IR (c-ir.Factory))
  (local int-t (IR.Type "int"))
  (local int-ptr-t (IR.Type "int" {:pointer 1}))

  (local bad-non-pointer
    (IR.Program
      {:functions
       [(IR.Function "id" int-t [(IR.Param "x" int-t)]
                     [(IR.Return (IR.Var "x"))])
        (IR.Function "main" int-t []
                     [(IR.Return (IR.CallPtr (IR.Int 123)
                                             [(IR.Int 1)]
                                             {:return-type int-t
                                              :param-types [int-t]}))])]}))
  (assert-error "validator should reject call-ptr with non-pointer function expression"
    (fn []
      (c-ir.validate-program bad-non-pointer :gccjit)))

  (local bad-arity
    (IR.Program
      {:functions
       [(IR.Function "id" int-t [(IR.Param "x" int-t)]
                     [(IR.Return (IR.Var "x"))])
        (IR.Function "main" int-t []
                     [(IR.Return (IR.CallPtr (IR.FunctionRef "id")
                                             []
                                             {:return-type int-t
                                              :param-types [int-t]}))])]}))
  (assert-error "validator should reject call-ptr arity mismatch"
    (fn []
      (c-ir.validate-program bad-arity :c-builder)))

  (local bad-type
    (IR.Program
      {:functions
       [(IR.Function "takes_ptr" int-t [(IR.Param "p" int-ptr-t)]
                     [(IR.Return (IR.Int 0))])
        (IR.Function "main" int-t []
                     [(IR.Return (IR.CallPtr (IR.FunctionRef "takes_ptr")
                                             [(IR.Int 1)]
                                             {:return-type int-t
                                              :param-types [int-ptr-t]}))])]}))
  (assert-error "validator should reject call-ptr argument type mismatch"
    (fn []
      (c-ir.validate-program bad-type :gccjit))))

(fn test-validation-rejects-designated-init-errors []
  (local IR (c-ir.Factory))
  (local int-t (IR.Type "int"))
  (local point-t (IR.StructType "point"))
  (local union-num-t (IR.UnionType "num"))

  (local bad-struct-field
    (IR.Program
      {:structs
       [(IR.Struct "point"
                   [(IR.StructField "x" int-t)
                    (IR.StructField "y" int-t)])]
       :functions
       [(IR.Function "main" int-t []
                     [(IR.Declare "p" point-t
                                  (IR.InitList [(IR.DesignatedInit "z" (IR.Int 1))]))
                      (IR.Return (IR.Int 0))])]}))
  (assert-error "validator should reject unknown designated field on struct init"
    (fn []
      (c-ir.validate-program bad-struct-field :c-builder)))

  (local bad-union-field
    (IR.Program
      {:unions
       [(IR.Union "num"
                  [(IR.StructField "i" int-t)
                   (IR.StructField "j" int-t)])]
       :functions
       [(IR.Function "main" int-t []
                     [(IR.Declare "u" union-num-t
                                  (IR.InitList [(IR.DesignatedInit "j" (IR.Int 1))]))
                      (IR.Return (IR.Int 0))])]}))
  (assert-error "validator should reject union designated init on non-first field"
    (fn []
      (c-ir.validate-program bad-union-field :gccjit))))

(table.insert tests {:name "c-ir shared abstraction jit and native extended" :fn test-jit-and-native-build-share-ir-extended})
(table.insert tests {:name "c-ir general features jit and native" :fn test-general-features-jit-and-native})
(table.insert tests {:name "c-ir extended control and adt features" :fn test-extended-control-and-adt-features})
(table.insert tests {:name "c-ir designated init and numeric conversion" :fn test-designated-init-and-implicit-numeric-conversion})
(table.insert tests {:name "c-ir function pointer call" :fn test-function-pointer-call})
(table.insert tests {:name "c-ir validator rejects call arity mismatch" :fn test-validation-rejects-call-arity-mismatch})
(table.insert tests {:name "c-ir validator rejects return type mismatch" :fn test-validation-rejects-return-type-mismatch})
(table.insert tests {:name "c-ir validator rejects assignment type mismatch" :fn test-validation-rejects-assignment-type-mismatch})
(table.insert tests {:name "c-ir validator rejects call-ptr shape errors" :fn test-validation-rejects-callptr-shape-errors})
(table.insert tests {:name "c-ir validator rejects designated init errors" :fn test-validation-rejects-designated-init-errors})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "c-ir"
                       :tests tests})))

{:name "c-ir"
 :tests tests
 :main main}
