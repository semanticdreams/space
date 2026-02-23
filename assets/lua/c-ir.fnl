(local c-builder (require :c-builder))
(local gccjit (require :gccjit))

(fn assert-string [name value]
  (when (not (= (type value) :string))
    (error (.. "c-ir " name " must be a string"))))

(fn is-array? [value]
  (if (not (= (type value) :table))
      false
      (do
        (var max 0)
        (var count 0)
        (each [k _ (pairs value)]
          (if (or (not (= (type k) :number))
                  (not (= k (math.floor k)))
                  (< k 1))
              (lua "return false")
              (do
                (set count (+ count 1))
                (when (> k max)
                  (set max k)))))
        (= count max))))

(fn assert-array [name value]
  (when (not (is-array? value))
    (error (.. "c-ir " name " must be an array"))))

(fn assert-kind [name expected value]
  (when (or (not (= (type value) :table)) (not (= value.kind expected)))
    (error (.. "c-ir " name " must be " expected))))

(fn quote-c-string [value]
  (local escaped (string.gsub value "\\" "\\\\"))
  (local escaped2 (string.gsub escaped "\"" "\\\""))
  (string.gsub escaped2 "\n" "\\n"))

(var Type nil)
(var infer-expr-type! nil)
(var expr->gccjit nil)
(var type-equals? nil)
(var infer-lvalue-type! nil)

(fn pointer-depth [t]
  (if (= (type t.pointer) :number)
      t.pointer
      (if t.pointer 1 0)))

(fn with-pointer-depth [t depth]
  (Type t.name {:pointer depth
                :const t.const
                :volatile t.volatile
                :struct-name t.struct-name
                :union-name t.union-name
                :enum-name t.enum-name}))

(set Type (fn [name opts]
  (local options (or opts {}))
  (assert-string "type name" name)
  {:kind :type
   :name name
   :pointer (or options.pointer false)
   :const (or options.const false)
   :volatile (or options.volatile false)
   :struct-name options.struct-name
   :union-name options.union-name
   :enum-name options.enum-name}))

(fn StructType [name opts]
  (local options (or opts {}))
  (assert-string "struct type name" name)
  (Type name {:pointer options.pointer
              :const options.const
              :volatile options.volatile
              :struct-name name}))

(fn UnionType [name opts]
  (local options (or opts {}))
  (assert-string "union type name" name)
  (Type name {:pointer options.pointer
              :const options.const
              :volatile options.volatile
              :union-name name}))

(fn EnumType [name opts]
  (local options (or opts {}))
  (assert-string "enum type name" name)
  (Type "int" {:pointer options.pointer
               :const options.const
               :volatile options.volatile
               :enum-name name}))

(fn Param [name type]
  (assert-string "param name" name)
  (assert-kind "param type" :type type)
  {:kind :param :name name :type type})

(fn StructField [name type]
  (assert-string "struct-field name" name)
  (assert-kind "struct-field type" :type type)
  {:kind :struct-field :name name :type type})

(fn EnumItem [name value]
  (assert-string "enum-item name" name)
  {:kind :enum-item :name name :value value})

(fn Struct [name fields]
  (assert-string "struct name" name)
  (local fs (or fields []))
  (assert-array "struct fields" fs)
  {:kind :struct
   :name name
   :fields fs})

(fn Union [name fields]
  (assert-string "union name" name)
  (local fs (or fields []))
  (assert-array "union fields" fs)
  {:kind :union
   :name name
   :fields fs})

(fn Enum [name items]
  (assert-string "enum name" name)
  (local it (or items []))
  (assert-array "enum items" it)
  {:kind :enum
   :name name
   :items it})

(fn Global [name type init opts]
  (local options (or opts {}))
  (assert-string "global name" name)
  (assert-kind "global type" :type type)
  {:kind :global
   :name name
   :type type
   :init init
   :internal (or options.internal false)
   :imported (or options.imported false)})

(fn Int [value]
  (when (not (= (type value) :number))
    (error "c-ir int value must be number"))
  {:kind :int :value value})

(fn Double [value]
  (when (not (= (type value) :number))
    (error "c-ir double value must be number"))
  {:kind :double :value value})

(fn StringLiteral [value]
  (assert-string "string literal value" value)
  {:kind :string-literal :value value})

(fn InitList [items]
  (local vs (or items []))
  (assert-array "init-list values" vs)
  {:kind :init-list :values vs})

(fn DesignatedInit [field expr]
  (assert-string "designated-init field" field)
  {:kind :designated-init
   :field field
   :expr expr})

(fn Null [type]
  (assert-kind "null type" :type type)
  {:kind :null :type type})

(fn Var [name]
  (assert-string "var name" name)
  {:kind :var :name name})

(fn Binary [op lhs rhs opts]
  (local options (or opts {}))
  (assert-string "binary op" op)
  {:kind :binary
   :op op
   :lhs lhs
   :rhs rhs
   :result-type options.result-type})

(fn Unary [op expr opts]
  (local options (or opts {}))
  (assert-string "unary op" op)
  {:kind :unary
   :op op
   :expr expr
   :result-type options.result-type})

(fn Compare [op lhs rhs]
  (assert-string "compare op" op)
  {:kind :compare
   :op op
   :lhs lhs
   :rhs rhs})

(fn Cast [type expr]
  (assert-kind "cast type" :type type)
  {:kind :cast
   :type type
   :expr expr})

(fn AddressOf [expr]
  {:kind :address-of
   :expr expr})

(fn Deref [expr]
  {:kind :deref
   :expr expr})

(fn Field [base field-name opts]
  (local options (or opts {}))
  (assert-string "field name" field-name)
  {:kind :field
   :base base
   :field field-name
   :pointer (or options.pointer false)})

(fn Index [base index]
  {:kind :index
   :base base
   :index index})

(fn Call [name args]
  (assert-string "call name" name)
  (local call-args (or args []))
  (assert-array "call args" call-args)
  {:kind :call
   :name name
   :args call-args})

(fn FunctionRef [name]
  (assert-string "function-ref name" name)
  {:kind :function-ref
   :name name})

(fn CallPtr [fn-expr args opts]
  (local options (or opts {}))
  (local call-args (or args []))
  (assert-array "call-ptr args" call-args)
  (assert-kind "call-ptr return-type" :type options.return-type)
  (assert-array "call-ptr param-types" (or options.param-types []))
  {:kind :call-ptr
   :fn-expr fn-expr
   :args call-args
   :return-type options.return-type
   :param-types (or options.param-types [])
   :variadic (or options.variadic false)})

(fn Return [expr]
  {:kind :return :expr expr})

(fn Declare [name type init]
  (assert-string "declare name" name)
  (assert-kind "declare type" :type type)
  {:kind :declare
   :name name
   :type type
   :init init})

(fn Assign [target expr]
  (if (= (type target) :string)
      {:kind :assign
       :target (Var target)
       :expr expr}
      {:kind :assign
       :target target
       :expr expr}))

(fn Expr [expr]
  {:kind :expr :expr expr})

(fn Break []
  {:kind :break})

(fn Continue []
  {:kind :continue})

(fn Block [body]
  (local b (or body []))
  (assert-array "block body" b)
  {:kind :block
   :body b})

(fn If [condition then-body else-body]
  (assert-array "if then-body" (or then-body []))
  (when (not (= else-body nil))
    (assert-array "if else-body" else-body))
  {:kind :if
   :condition condition
   :then-body (or then-body [])
   :else-body else-body})

(fn While [condition body]
  (assert-array "while body" (or body []))
  {:kind :while
   :condition condition
   :body (or body [])})

(fn DoWhile [body condition]
  (assert-array "do-while body" (or body []))
  {:kind :do-while
   :body (or body [])
   :condition condition})

(fn For [init condition post body]
  (assert-array "for body" (or body []))
  {:kind :for
   :init init
   :condition condition
   :post post
   :body (or body [])})

(fn SwitchCase [value body]
  {:kind :switch-case
   :value value
   :body (or body [])})

(fn Switch [expr cases default-body]
  (local cs (or cases []))
  (assert-array "switch cases" cs)
  (when (not (= default-body nil))
    (assert-array "switch default body" default-body))
  {:kind :switch
   :expr expr
   :cases cs
   :default-body (or default-body [])})

(fn Function [name return-type params body opts]
  (local options (or opts {}))
  (assert-string "function name" name)
  (assert-kind "function return-type" :type return-type)
  (local fn-params (or params []))
  (local fn-body (or body []))
  (assert-array "function params" fn-params)
  (assert-array "function body" fn-body)
  {:kind :function
   :name name
   :return-type return-type
   :params fn-params
   :body fn-body
   :imported (or options.imported false)
   :internal (or options.internal false)
   :always-inline (or options.always-inline false)
   :variadic (or options.variadic false)})

(fn Program [opts]
  (local options (or opts {}))
  {:kind :program
   :includes (or options.includes [])
   :enums (or options.enums [])
   :structs (or options.structs [])
   :unions (or options.unions [])
   :globals (or options.globals [])
   :functions (or options.functions [])})

(var validate-program nil)

(fn type->c-source [t]
  (assert-kind "type" :type t)
  (local base
    (if t.struct-name
        (.. "struct " t.struct-name)
        t.union-name
        (.. "union " t.union-name)
        t.enum-name
        (.. "enum " t.enum-name)
        t.name))
  (local cv1 (if t.const "const " ""))
  (local cv2 (if t.volatile "volatile " ""))
  (local stars (string.rep "*" (pointer-depth t)))
  (if (> (# stars) 0)
      (.. cv1 cv2 base " " stars)
      (.. cv1 cv2 base)))

(fn c-source-expr [expr]
  (if (= expr nil)
      ""
      (= (type expr) :string)
      expr
      (= (type expr) :number)
      (tostring expr)
      (= expr.kind :int)
      (tostring expr.value)
      (= expr.kind :double)
      (tostring expr.value)
      (= expr.kind :string-literal)
      (.. "\"" (quote-c-string expr.value) "\"")
      (= expr.kind :init-list)
      (.. "{"
          (table.concat
            (icollect [_ v (ipairs expr.values)]
              (if (and (= (type v) :table) (= v.kind :designated-init))
                  (.. "." v.field " = " (c-source-expr v.expr))
                  (c-source-expr v)))
            ", ")
          "}")
      (= expr.kind :null)
      "NULL"
      (= expr.kind :var)
      expr.name
      (= expr.kind :call)
      (.. expr.name "(" (table.concat (icollect [_ a (ipairs expr.args)] (c-source-expr a)) ", ") ")")
      (= expr.kind :function-ref)
      expr.name
      (= expr.kind :call-ptr)
      (.. "((" (c-source-expr expr.fn-expr) ")("
          (table.concat (icollect [_ a (ipairs expr.args)] (c-source-expr a)) ", ")
          "))")
      (= expr.kind :binary)
      (.. "(" (c-source-expr expr.lhs) " " expr.op " " (c-source-expr expr.rhs) ")")
      (= expr.kind :unary)
      (.. "(" expr.op "(" (c-source-expr expr.expr) "))")
      (= expr.kind :compare)
      (.. "(" (c-source-expr expr.lhs) " " expr.op " " (c-source-expr expr.rhs) ")")
      (= expr.kind :cast)
      (.. "((" (type->c-source expr.type) ")" (c-source-expr expr.expr) ")")
      (= expr.kind :address-of)
      (.. "(&" (c-source-expr expr.expr) ")")
      (= expr.kind :deref)
      (.. "(*" (c-source-expr expr.expr) ")")
      (= expr.kind :field)
      (if expr.pointer
          (.. "(" (c-source-expr expr.base) "->" expr.field ")")
          (.. "(" (c-source-expr expr.base) "." expr.field ")"))
      (= expr.kind :index)
      (.. "(" (c-source-expr expr.base) "[" (c-source-expr expr.index) "])")
      (error (.. "c-ir unsupported expression kind: " (tostring expr.kind)))))

(fn type->cbuilder [C t]
  (assert-kind "type" :type t)
  (local pd (pointer-depth t))
  (C.type (if t.struct-name
              (.. "struct " t.struct-name)
              t.union-name
              (.. "union " t.union-name)
              t.enum-name
              (.. "enum " t.enum-name)
              t.name)
          {:pointer (if (> pd 0) pd false)
           :const t.const
           :volatile t.volatile}))

(fn param->cbuilder [C p]
  (C.variable p.name (type->cbuilder C p.type)))

(fn expr->cbuilder [expr]
  (c-source-expr expr))

(fn c-source-for-clause [part]
  (if (= part nil)
      ""
      (= part.kind :declare)
      (.. (type->c-source part.type) " " part.name
          (if part.init (.. " = " (c-source-expr part.init)) ""))
      (= part.kind :assign)
      (.. (c-source-expr part.target) " = " (c-source-expr part.expr))
      (= part.kind :expr)
      (c-source-expr part.expr)
      (c-source-expr part)))

(fn append-stmt->cbuilder! [C container stmt]
  (if (= stmt.kind :if)
      (do
        (container:append (C.line (.. "if (" (c-source-expr stmt.condition) ")")))
        (local then-block (C.block))
        (each [_ inner (ipairs stmt.then-body)]
          (append-stmt->cbuilder! C then-block inner))
        (container:append then-block)
        (when (and stmt.else-body (> (# stmt.else-body) 0))
          (container:append (C.line "else"))
          (local else-block (C.block))
          (each [_ inner (ipairs stmt.else-body)]
            (append-stmt->cbuilder! C else-block inner))
          (container:append else-block)))
      (= stmt.kind :while)
      (do
        (container:append (C.line (.. "while (" (c-source-expr stmt.condition) ")")))
        (local body (C.block))
        (each [_ inner (ipairs stmt.body)]
          (append-stmt->cbuilder! C body inner))
        (container:append body))
      (= stmt.kind :do-while)
      (do
        (container:append (C.line "do"))
        (local body (C.block))
        (each [_ inner (ipairs stmt.body)]
          (append-stmt->cbuilder! C body inner))
        (container:append body)
        (container:append (C.statement (.. "while (" (c-source-expr stmt.condition) ")"))))
      (= stmt.kind :for)
      (do
        (container:append (C.line (.. "for ("
                                   (c-source-for-clause stmt.init)
                                   "; "
                                   (if stmt.condition (c-source-expr stmt.condition) "")
                                   "; "
                                   (c-source-for-clause stmt.post)
                                   ")")))
        (local body (C.block))
        (each [_ inner (ipairs stmt.body)]
          (append-stmt->cbuilder! C body inner))
        (container:append body))
      (= stmt.kind :switch)
      (do
        (container:append (C.line (.. "switch (" (c-source-expr stmt.expr) ")")))
        (local sb (C.block))
        (each [_ sc (ipairs stmt.cases)]
          (sb:append (C.line (.. "case " (c-source-expr sc.value) ":")))
          (local cb (C.block))
          (each [_ inner (ipairs sc.body)]
            (append-stmt->cbuilder! C cb inner))
          (sb:append cb))
        (when (> (# stmt.default-body) 0)
          (sb:append (C.line "default:"))
          (local db (C.block))
          (each [_ inner (ipairs stmt.default-body)]
            (append-stmt->cbuilder! C db inner))
          (sb:append db))
        (container:append sb))
      (= stmt.kind :block)
      (do
        (local b (C.block))
        (each [_ inner (ipairs stmt.body)]
          (append-stmt->cbuilder! C b inner))
        (container:append b))
      (= stmt.kind :declare)
      (do
        (if (and stmt.init (= stmt.init.kind :init-list))
            (container:append
              (C.line (.. (type->c-source stmt.type)
                          " "
                          stmt.name
                          " = "
                          (c-source-expr stmt.init)
                          ";")))
            (do
              (container:append (C.statement (C.declaration (C.variable stmt.name (type->cbuilder C stmt.type)))))
              (when (not (= stmt.init nil))
                (container:append (C.statement (C.assignment stmt.name (expr->cbuilder stmt.init))))))))
      (= stmt.kind :assign)
      (container:append (C.statement (C.assignment (expr->cbuilder stmt.target) (expr->cbuilder stmt.expr))))
      (= stmt.kind :return)
      (container:append (C.statement (C.func-return (expr->cbuilder stmt.expr))))
      (= stmt.kind :expr)
      (container:append (C.statement (expr->cbuilder stmt.expr)))
      (= stmt.kind :break)
      (container:append (C.statement "break"))
      (= stmt.kind :continue)
      (container:append (C.statement "continue"))
      (error (.. "c-ir unsupported c-builder statement kind: " (tostring stmt.kind)))))

(fn struct->cbuilder! [C seq struct-node]
  (local members
    (icollect [_ f (ipairs struct-node.fields)]
      (C.struct-member f.name (type->cbuilder C f.type))))
  (seq:append (C.declaration (C.struct struct-node.name members)))
  (seq:append (C.line ";")))

(fn union->cbuilder! [C seq union-node]
  (seq:append (C.line (.. "union " union-node.name " {")))
  (each [_ f (ipairs union-node.fields)]
    (seq:append (C.line (.. "    " (type->c-source f.type) " " f.name ";"))))
  (seq:append (C.line "};")))

(fn enum->cbuilder! [C seq enum-node]
  (seq:append (C.line (.. "enum " enum-node.name " {")))
  (each [i item (ipairs enum-node.items)]
    (seq:append
      (C.line
        (.. "    "
            item.name
            (if (= item.value nil) "" (.. " = " (c-source-expr item.value)))
            (if (< i (# enum-node.items)) "," "")))))
  (seq:append (C.line "};")))

(fn global->cbuilder! [C seq g]
  (if g.imported
      (seq:append (C.line (.. "extern " (type->c-source g.type) " " g.name ";")))
      (if (= g.init nil)
          (seq:append (C.line (.. (if g.internal "static " "")
                                   (type->c-source g.type)
                                   " "
                                   g.name
                                   ";")))
          (seq:append (C.line (.. (if g.internal "static " "")
                                   (type->c-source g.type)
                                   " "
                                   g.name
                                   " = "
                                   (c-source-expr g.init)
                                   ";"))))))

(fn function->cbuilder! [C seq fn-node]
  (local decl
    (C.declaration
      (C.function fn-node.name
                  (type->cbuilder C fn-node.return-type)
                  {:params (icollect [_ p (ipairs fn-node.params)] (param->cbuilder C p))
                   :static fn-node.internal})))
  (seq:append decl)
  (when (not fn-node.imported)
    (local body (C.block))
    (each [_ stmt (ipairs fn-node.body)]
      (append-stmt->cbuilder! C body stmt))
    (seq:append body)))

(fn to-c-builder [program]
  (assert-kind "program" :program program)
  (validate-program program :c-builder)
  (local C (c-builder.Factory))
  (local seq (C.sequence))
  (each [_ inc (ipairs program.includes)]
    (seq:append (C.sysinclude inc)))
  (when (> (# program.includes) 0)
    (seq:append (C.blank)))

  (each [_ struct-node (ipairs program.structs)]
    (struct->cbuilder! C seq struct-node)
    (seq:append (C.blank)))

  (each [_ union-node (ipairs program.unions)]
    (union->cbuilder! C seq union-node)
    (seq:append (C.blank)))

  (each [_ enum-node (ipairs program.enums)]
    (enum->cbuilder! C seq enum-node)
    (seq:append (C.blank)))

  (each [_ g (ipairs program.globals)]
    (global->cbuilder! C seq g)
    (seq:append (C.blank)))

  (each [i fn-node (ipairs program.functions)]
    (function->cbuilder! C seq fn-node)
    (when (< i (# program.functions))
      (seq:append (C.blank))))
  seq)

(fn write-file [program path opts]
  (local options (or opts {}))
  (local style (or options.style (c-builder.Style)))
  (local writer (c-builder.Writer style))
  (writer:write-file (to-c-builder program) path)
  path)

(fn builtin-type->gccjit [ctxt name]
  (if (= name "void") (ctxt:get-type (. gccjit.Types "void"))
      (= name "bool") (ctxt:get-type (. gccjit.Types "bool"))
      (= name "char") (ctxt:get-type (. gccjit.Types "char"))
      (= name "signed char") (ctxt:get-type (. gccjit.Types "signed-char"))
      (= name "unsigned char") (ctxt:get-type (. gccjit.Types "unsigned-char"))
      (= name "short") (ctxt:get-type (. gccjit.Types "short"))
      (= name "unsigned short") (ctxt:get-type (. gccjit.Types "unsigned-short"))
      (= name "int") (ctxt:get-type (. gccjit.Types "int"))
      (= name "unsigned int") (ctxt:get-type (. gccjit.Types "unsigned-int"))
      (= name "long") (ctxt:get-type (. gccjit.Types "long"))
      (= name "unsigned long") (ctxt:get-type (. gccjit.Types "unsigned-long"))
      (= name "long long") (ctxt:get-type (. gccjit.Types "long-long"))
      (= name "unsigned long long") (ctxt:get-type (. gccjit.Types "unsigned-long-long"))
      (= name "float") (ctxt:get-type (. gccjit.Types "float"))
      (= name "double") (ctxt:get-type (. gccjit.Types "double"))
      (= name "long double") (ctxt:get-type (. gccjit.Types "long-double"))
      (= name "size_t") (ctxt:get-type (. gccjit.Types "size-t"))
      (= name "const char *") (ctxt:get-type (. gccjit.Types "const-char-ptr"))
      (error (.. "c-ir unsupported gccjit builtin type: " name))))

(fn type->gccjit [ctxt t state]
  (local base
    (if t.struct-name
        (do
          (local st (. state.struct-types t.struct-name))
          (if st st (error (.. "c-ir unknown struct type: " t.struct-name))))
        t.union-name
        (do
          (local ut (. state.union-types t.union-name))
          (if ut ut (error (.. "c-ir unknown union type: " t.union-name))))
        t.enum-name
        (builtin-type->gccjit ctxt "int")
        (builtin-type->gccjit ctxt t.name)))
  (var result base)
  (when t.const
    (set result (result:get-const)))
  (when t.volatile
    (set result (result:get-volatile)))
  (for [i 1 (pointer-depth t)]
    (set result (result:get-pointer)))
  result)

(fn resolve-function-kind [fn-node]
  (if fn-node.imported
      (. gccjit.FunctionKind "imported")
      fn-node.always-inline
      (. gccjit.FunctionKind "always-inline")
      fn-node.internal
      (. gccjit.FunctionKind "internal")
      (. gccjit.FunctionKind "exported")))

(fn binary-op->gccjit [op]
  (if (= op "+") (. gccjit.BinaryOp "plus")
      (= op "-") (. gccjit.BinaryOp "minus")
      (= op "*") (. gccjit.BinaryOp "mult")
      (= op "/") (. gccjit.BinaryOp "divide")
      (= op "%") (. gccjit.BinaryOp "modulo")
      (= op "&") (. gccjit.BinaryOp "bitwise-and")
      (= op "|") (. gccjit.BinaryOp "bitwise-or")
      (= op "^") (. gccjit.BinaryOp "bitwise-xor")
      (= op "<<") (. gccjit.BinaryOp "lshift")
      (= op ">>") (. gccjit.BinaryOp "rshift")
      (= op "&&") (. gccjit.BinaryOp "logical-and")
      (= op "||") (. gccjit.BinaryOp "logical-or")
      (error (.. "c-ir unsupported binary op for gccjit: " op))))

(fn unary-op->gccjit [op]
  (if (= op "-") (. gccjit.UnaryOp "minus")
      (= op "~") (. gccjit.UnaryOp "bitwise-negate")
      (= op "!") (. gccjit.UnaryOp "logical-negate")
      (= op "abs") (. gccjit.UnaryOp "abs")
      (error (.. "c-ir unsupported unary op for gccjit: " op))))

(fn comparison-op->gccjit [op]
  (if (= op "==") (. gccjit.Comparison "eq")
      (= op "!=") (. gccjit.Comparison "ne")
      (= op "<") (. gccjit.Comparison "lt")
      (= op "<=") (. gccjit.Comparison "le")
      (= op ">") (. gccjit.Comparison "gt")
      (= op ">=") (. gccjit.Comparison "ge")
      (error (.. "c-ir unsupported comparison op for gccjit: " op))))

(fn expr->lvalue-gccjit [state expr]
  (if (= expr.kind :var)
      (do
        (local lv (. state.locals expr.name))
      (if lv
          lv
          (do
            (local gv (. state.globals expr.name))
            (if gv gv (error (.. "c-ir unknown lvalue variable: " expr.name))))))
      (= expr.kind :deref)
      (do
        (local rv (expr->gccjit state expr.expr))
        (rv:dereference nil))
      (= expr.kind :index)
      (state.ctxt:new-array-access nil
                                   (expr->gccjit state expr.base)
                                   (expr->gccjit state expr.index))
      (= expr.kind :field)
      (do
        (local base-type (infer-expr-type! expr.base state.validator-functions state.validator-vars :gccjit state.type-map))
        (local container-name (if base-type.struct-name base-type.struct-name base-type.union-name))
        (local field-ref (. (. state.container-fields container-name) expr.field))
        (when (not field-ref)
          (error (.. "c-ir unknown field in gccjit lowering: " container-name "." expr.field)))
        (if expr.pointer
            (do
              (local base-rv (expr->gccjit state expr.base))
              (base-rv:dereference-field nil field-ref))
            (do
              (local base-lv (expr->lvalue-gccjit state expr.base))
              (base-lv:access-field nil field-ref))))
      (error (.. "c-ir expression is not assignable: " (tostring expr.kind)))))

(fn infer-binary-result-type [state expr]
  (local t
    (if expr.result-type
        expr.result-type
        (infer-expr-type! expr state.validator-functions state.validator-vars :gccjit state.type-map)))
  (type->gccjit state.ctxt t state))

(set expr->gccjit (fn [state expr]
  (if (= expr nil)
      nil
      (= (type expr) :number)
      (state.ctxt:new-rvalue-from-int (type->gccjit state.ctxt (Type "int") state) expr)
      (= expr.kind :int)
      (state.ctxt:new-rvalue-from-int (type->gccjit state.ctxt (Type "int") state) expr.value)
      (= expr.kind :double)
      (state.ctxt:new-rvalue-from-double (type->gccjit state.ctxt (Type "double") state) expr.value)
      (= expr.kind :string-literal)
      (state.ctxt:new-string-literal expr.value)
      (= expr.kind :null)
      (state.ctxt:null (type->gccjit state.ctxt expr.type state))
      (= expr.kind :var)
      (do
        (local lv (expr->lvalue-gccjit state expr))
        (lv:as-rvalue))
      (= expr.kind :call)
      (do
        (local fn-ref (. state.functions expr.name))
        (if fn-ref
            (do
              (local fn-node (. state.validator-functions expr.name))
              (local lowered-args [])
              (each [i a (ipairs expr.args)]
                (local rv (expr->gccjit state a))
                (if fn-node
                    (do
                      (local param-type (. (. fn-node.params i) :type))
                      (local arg-type (infer-expr-type! a state.validator-functions state.validator-vars :gccjit state.type-map))
                      (if (type-equals? param-type arg-type)
                          (table.insert lowered-args rv)
                          (table.insert lowered-args
                                        (state.ctxt:new-cast nil rv (type->gccjit state.ctxt param-type state)))))
                    (table.insert lowered-args rv)))
              (state.ctxt:new-call nil fn-ref lowered-args))
            (error (.. "c-ir unknown function in gccjit lowering: " expr.name))))
      (= expr.kind :function-ref)
      (do
        (local fn-ref (. state.functions expr.name))
        (if fn-ref
            (fn-ref:get-address nil)
            (error (.. "c-ir unknown function ref in gccjit lowering: " expr.name))))
      (= expr.kind :call-ptr)
      (do
        (local fn-ptr (expr->gccjit state expr.fn-expr))
        (local lowered-args [])
        (each [i a (ipairs expr.args)]
          (local rv (expr->gccjit state a))
          (if (<= i (# expr.param-types))
              (do
                (local expected-type (. expr.param-types i))
                (local arg-type (infer-expr-type! a state.validator-functions state.validator-vars :gccjit state.type-map))
                (if (type-equals? expected-type arg-type)
                    (table.insert lowered-args rv)
                    (table.insert lowered-args
                                  (state.ctxt:new-cast nil rv (type->gccjit state.ctxt expected-type state)))))
              (table.insert lowered-args rv)))
        (state.ctxt:new-call-through-ptr nil fn-ptr lowered-args))
      (= expr.kind :binary)
      (state.ctxt:new-binary-op nil
                                (binary-op->gccjit expr.op)
                                (infer-binary-result-type state expr)
                                (expr->gccjit state expr.lhs)
                                (expr->gccjit state expr.rhs))
      (= expr.kind :unary)
      (state.ctxt:new-unary-op nil
                               (unary-op->gccjit expr.op)
                               (if expr.result-type
                                   (type->gccjit state.ctxt expr.result-type state)
                                   (do
                                     (local rv (expr->gccjit state expr.expr))
                                     (rv:get-type)))
                               (expr->gccjit state expr.expr))
      (= expr.kind :compare)
      (state.ctxt:new-comparison nil
                                 (comparison-op->gccjit expr.op)
                                 (expr->gccjit state expr.lhs)
                                 (expr->gccjit state expr.rhs))
      (= expr.kind :cast)
      (state.ctxt:new-cast nil (expr->gccjit state expr.expr) (type->gccjit state.ctxt expr.type state))
      (= expr.kind :address-of)
      (do
        (local lv (expr->lvalue-gccjit state expr.expr))
        (lv:get-address nil))
      (= expr.kind :deref)
      (do
        (local lv (expr->lvalue-gccjit state expr))
        (lv:as-rvalue))
      (= expr.kind :field)
      (do
        (local base-type (infer-expr-type! expr.base state.validator-functions state.validator-vars :gccjit state.type-map))
        (local container-name (if base-type.struct-name base-type.struct-name base-type.union-name))
        (local field-ref (. (. state.container-fields container-name) expr.field))
        (when (not field-ref)
          (error (.. "c-ir unknown field in gccjit lowering: " container-name "." expr.field)))
        (if expr.pointer
            (do
              (local base-rv (expr->gccjit state expr.base))
              (local field-lv (base-rv:dereference-field nil field-ref))
              (field-lv:as-rvalue))
            (do
              (local base-lv (expr->lvalue-gccjit state expr.base))
              (local field-lv (base-lv:access-field nil field-ref))
              (field-lv:as-rvalue)))
      )
      (= expr.kind :index)
      (do
        (local index-lv (state.ctxt:new-array-access nil (expr->gccjit state expr.base) (expr->gccjit state expr.index)))
        (index-lv:as-rvalue))
      (error (.. "c-ir unsupported gccjit expression kind: " (tostring expr.kind))))))

(fn copy-table [src]
  (local out {})
  (each [k v (pairs src)]
    (set (. out k) v))
  out)

(fn stmt-list-has-break? [stmts]
  (var found false)
  (fn walk [items]
    (each [_ s (ipairs items)]
      (if (= s.kind :break)
          (set found true)
          (= s.kind :if)
          (do
            (walk s.then-body)
            (when s.else-body
              (walk s.else-body)))
          (= s.kind :while)
          (walk s.body)
          (= s.kind :do-while)
          (walk s.body)
          (= s.kind :for)
          (do
            (when s.init
              (walk [s.init]))
            (when s.post
              (walk [s.post]))
            (walk s.body))
          (= s.kind :switch)
          (do
            (each [_ c (ipairs s.cases)]
              (walk c.body))
            (walk s.default-body))
          (= s.kind :block)
          (walk s.body)
          nil)))
  (walk stmts)
  found)

(fn switch-has-break? [stmt]
  (if (stmt-list-has-break? stmt.default-body)
      true
      (do
        (var found false)
        (each [_ c (ipairs stmt.cases)]
          (when (stmt-list-has-break? c.body)
            (set found true)))
        found)))

(fn lower-init-list-into-lvalue! [state block target-lvalue target-type init-list]
  (if target-type.struct-name
      (do
        (local s (. state.type-map target-type.struct-name))
        (var next-index 1)
        (each [_ v (ipairs init-list.values)]
          (if (and (= (type v) :table) (= v.kind :designated-init))
              (do
                (var f nil)
                (each [_ sf (ipairs s.fields)]
                  (when (= sf.name v.field)
                    (set f sf)))
                (when (not f)
                  (error (.. "c-ir unknown designated init field for lowering: "
                             target-type.struct-name "." v.field)))
                (local fr (. (. state.container-fields target-type.struct-name) f.name))
                (local slot (target-lvalue:access-field nil fr))
                (if (and (= (type v.expr) :table) (= v.expr.kind :init-list))
                    (lower-init-list-into-lvalue! state block slot f.type v.expr)
                    (block:add-assignment nil slot (expr->gccjit state v.expr))))
              (do
                (local f (. s.fields next-index))
                (local fr (. (. state.container-fields target-type.struct-name) f.name))
                (local slot (target-lvalue:access-field nil fr))
                (if (and (= (type v) :table) (= v.kind :init-list))
                    (lower-init-list-into-lvalue! state block slot f.type v)
                    (block:add-assignment nil slot (expr->gccjit state v)))
                (set next-index (+ next-index 1))))))
      target-type.union-name
      (do
        (when (= (# init-list.values) 1)
          (local u (. state.type-map target-type.union-name))
          (local f (. u.fields 1))
          (local fr (. (. state.container-fields target-type.union-name) f.name))
          (local slot (target-lvalue:access-field nil fr))
          (local v (. init-list.values 1))
          (if (and (= (type v) :table) (= v.kind :designated-init))
              (if (and (= (type v.expr) :table) (= v.expr.kind :init-list))
                  (lower-init-list-into-lvalue! state block slot f.type v.expr)
                  (block:add-assignment nil slot (expr->gccjit state v.expr)))
              (if (and (= (type v) :table) (= v.kind :init-list))
                  (lower-init-list-into-lvalue! state block slot f.type v)
                  (block:add-assignment nil slot (expr->gccjit state v))))))
      (error "c-ir init-list lowering requires struct/union type")))

(fn lower-stmt-list [state start-block stmts flow]
  (var current-block start-block)
  (var terminated false)
  (each [_ stmt (ipairs stmts)]
    (when terminated
      (error "c-ir unreachable statement after terminator"))
    (if (= stmt.kind :return)
        (do
          (if (= stmt.expr nil)
              (current-block:end-with-void-return nil)
              (do
                (local rv (expr->gccjit state stmt.expr))
                (local actual-type (infer-expr-type! stmt.expr state.validator-functions state.validator-vars :gccjit state.type-map))
                (local expected-type state.return-type)
                (if (type-equals? actual-type expected-type)
                    (current-block:end-with-return nil rv)
                    (current-block:end-with-return nil
                      (state.ctxt:new-cast nil rv (type->gccjit state.ctxt expected-type state))))))
          (set terminated true))
        (= stmt.kind :declare)
        (do
          (local t (type->gccjit state.ctxt stmt.type state))
          (local lv (state.function:new-local nil t stmt.name))
          (set (. state.locals stmt.name) lv)
          (set (. state.local-types stmt.name) stmt.type)
          (set (. state.validator-vars stmt.name) stmt.type)
          (when (not (= stmt.init nil))
            (if (and (= (type stmt.init) :table) (= stmt.init.kind :init-list))
                (lower-init-list-into-lvalue! state current-block lv stmt.type stmt.init)
                (do
                  (local rv (expr->gccjit state stmt.init))
                  (local init-type (infer-expr-type! stmt.init state.validator-functions state.validator-vars :gccjit state.type-map))
                  (if (type-equals? init-type stmt.type)
                      (current-block:add-assignment nil lv rv)
                      (current-block:add-assignment nil lv
                        (state.ctxt:new-cast nil rv (type->gccjit state.ctxt stmt.type state))))))))
        (= stmt.kind :assign)
        (do
          (local lv (expr->lvalue-gccjit state stmt.target))
          (local target-type (infer-lvalue-type! stmt.target state.validator-functions state.validator-vars :gccjit state.type-map))
          (local rv (expr->gccjit state stmt.expr))
          (local expr-type (infer-expr-type! stmt.expr state.validator-functions state.validator-vars :gccjit state.type-map))
          (if (type-equals? target-type expr-type)
              (current-block:add-assignment nil lv rv)
              (current-block:add-assignment nil lv
                (state.ctxt:new-cast nil rv (type->gccjit state.ctxt target-type state)))))
        (= stmt.kind :expr)
        (current-block:add-eval nil (expr->gccjit state stmt.expr))
        (= stmt.kind :break)
        (do
          (when (not flow.break-target)
            (error "c-ir break used outside loop/switch"))
          (current-block:end-with-jump nil flow.break-target)
          (set terminated true))
        (= stmt.kind :continue)
        (do
          (when (not flow.continue-target)
            (error "c-ir continue used outside loop"))
          (current-block:end-with-jump nil flow.continue-target)
          (set terminated true))
        (= stmt.kind :block)
        (do
          (local nested-vars (copy-table state.validator-vars))
          (local nested-state (copy-table state))
          (set nested-state.validator-vars nested-vars)
          (local block-result (lower-stmt-list nested-state current-block stmt.body flow))
          (set current-block block-result.block)
          (set terminated block-result.terminated))
        (= stmt.kind :if)
        (do
          (set state.block-counter (+ state.block-counter 1))
          (local id state.block-counter)
          (local then-block (state.function:new-block (.. "if_then_" id)))
          (local else-block (state.function:new-block (.. "if_else_" id)))
          (current-block:end-with-conditional nil (expr->gccjit state stmt.condition) then-block else-block)

          (local then-state (copy-table state))
          (set then-state.validator-vars (copy-table state.validator-vars))
          (local then-result (lower-stmt-list then-state then-block stmt.then-body flow))

          (local else-state (copy-table state))
          (set else-state.validator-vars (copy-table state.validator-vars))
          (local else-result
            (if stmt.else-body
                (lower-stmt-list else-state else-block stmt.else-body flow)
                {:terminated false :block else-block}))

          (if (and then-result.terminated else-result.terminated)
              (set terminated true)
              (do
                (local merge (state.function:new-block (.. "if_merge_" id)))
                (when (not then-result.terminated)
                  (then-result.block:end-with-jump nil merge))
                (when (not else-result.terminated)
                  (else-result.block:end-with-jump nil merge))
                (set current-block merge))))
        (= stmt.kind :while)
        (do
          (set state.block-counter (+ state.block-counter 1))
          (local id state.block-counter)
          (local cond-block (state.function:new-block (.. "while_cond_" id)))
          (local body-block (state.function:new-block (.. "while_body_" id)))
          (local exit-block (state.function:new-block (.. "while_exit_" id)))
          (current-block:end-with-jump nil cond-block)
          (cond-block:end-with-conditional nil (expr->gccjit state stmt.condition) body-block exit-block)

          (local body-state (copy-table state))
          (set body-state.validator-vars (copy-table state.validator-vars))
          (local body-result (lower-stmt-list body-state body-block stmt.body
                                              {:break-target exit-block
                                               :continue-target cond-block}))
          (when (not body-result.terminated)
            (body-result.block:end-with-jump nil cond-block))
          (set current-block exit-block))
        (= stmt.kind :do-while)
        (do
          (set state.block-counter (+ state.block-counter 1))
          (local id state.block-counter)
          (local body-block (state.function:new-block (.. "do_body_" id)))
          (local cond-block (state.function:new-block (.. "do_cond_" id)))
          (local exit-block (state.function:new-block (.. "do_exit_" id)))
          (current-block:end-with-jump nil body-block)
          (local body-state (copy-table state))
          (set body-state.validator-vars (copy-table state.validator-vars))
          (local body-result (lower-stmt-list body-state body-block stmt.body
                                              {:break-target exit-block
                                               :continue-target cond-block}))
          (when (not body-result.terminated)
            (body-result.block:end-with-jump nil cond-block))
          (cond-block:end-with-conditional nil (expr->gccjit state stmt.condition) body-block exit-block)
          (set current-block exit-block))
        (= stmt.kind :for)
        (do
          (local for-state (copy-table state))
          (set for-state.validator-vars (copy-table state.validator-vars))
          (when stmt.init
            (local init-result (lower-stmt-list for-state current-block [stmt.init] flow))
            (set current-block init-result.block)
            (when init-result.terminated
              (set terminated true)))
          (when (not terminated)
            (set for-state.block-counter (+ for-state.block-counter 1))
            (local id for-state.block-counter)
            (local cond-block (for-state.function:new-block (.. "for_cond_" id)))
            (local body-block (for-state.function:new-block (.. "for_body_" id)))
            (local post-block (for-state.function:new-block (.. "for_post_" id)))
            (local exit-block (for-state.function:new-block (.. "for_exit_" id)))
            (current-block:end-with-jump nil cond-block)
            (if stmt.condition
                (cond-block:end-with-conditional nil (expr->gccjit for-state stmt.condition) body-block exit-block)
                (cond-block:end-with-jump nil body-block))
            (local body-result (lower-stmt-list for-state body-block stmt.body
                                                {:break-target exit-block
                                                 :continue-target post-block}))
            (when (not body-result.terminated)
              (body-result.block:end-with-jump nil post-block))
            (if stmt.post
                (do
                  (local post-result (lower-stmt-list for-state post-block [stmt.post] flow))
                  (when (not post-result.terminated)
                    (post-result.block:end-with-jump nil cond-block)))
                (post-block:end-with-jump nil cond-block))
            (set current-block exit-block)))
        (= stmt.kind :switch)
        (do
          (set state.block-counter (+ state.block-counter 1))
          (local id state.block-counter)
          (local needs-break-target (switch-has-break? stmt))
          (var merge (if needs-break-target (state.function:new-block (.. "switch_merge_" id)) nil))
          (local default-block (state.function:new-block (.. "switch_default_" id)))
          (local case-refs [])
          (local case-blocks [])
          (var any-fallthrough false)

          (each [i sc (ipairs stmt.cases)]
            (local cb (state.function:new-block (.. "switch_case_" id "_" i)))
            (table.insert case-blocks cb)
            (table.insert case-refs (state.ctxt:new-case (expr->gccjit state sc.value)
                                                         (expr->gccjit state sc.value)
                                                         cb)))

          (current-block:end-with-switch nil (expr->gccjit state stmt.expr) default-block case-refs)

          (each [i sc (ipairs stmt.cases)]
            (local cs (copy-table state))
            (set cs.validator-vars (copy-table state.validator-vars))
            (local cr (lower-stmt-list cs (. case-blocks i) sc.body
                                       {:break-target merge
                                        :continue-target flow.continue-target}))
            (if cr.terminated
                nil
                (do
                  (when (not merge)
                    (set merge (state.function:new-block (.. "switch_merge_" id))))
                  (set any-fallthrough true)
                  (cr.block:end-with-jump nil merge))))

          (local ds (copy-table state))
          (set ds.validator-vars (copy-table state.validator-vars))
          (local dr (lower-stmt-list ds default-block stmt.default-body
                                     {:break-target merge
                                      :continue-target flow.continue-target}))
          (if dr.terminated
              nil
              (do
                (when (not merge)
                  (set merge (state.function:new-block (.. "switch_merge_" id))))
                (set any-fallthrough true)
                (dr.block:end-with-jump nil merge)))
          (if merge
              (set current-block merge)
              (set terminated true)))
        (error (.. "c-ir unsupported gccjit statement kind: " (tostring stmt.kind)))))
  {:terminated terminated :block current-block})

(fn lower-function! [ctxt fn-node fn-ref state]
  (if fn-node.imported
      nil
      (do
        (local entry (fn-ref:new-block "entry"))
        (local local-values {})
        (local local-types {})
        (local validator-vars (copy-table state.globals-types))
        (each [idx p (ipairs fn-node.params)]
          (local jp (fn-ref:get-param (- idx 1)))
          (set (. local-values p.name) (jp:as-lvalue))
          (set (. local-types p.name) p.type)
          (set (. validator-vars p.name) p.type))

        (local fn-state {:ctxt ctxt
                         :function fn-ref
                         :functions state.functions
                         :globals state.globals
                         :globals-types state.globals-types
                         :locals local-values
                         :local-types local-types
                         :struct-types state.struct-types
                         :union-types state.union-types
                         :container-fields state.container-fields
                         :block-counter 0
                         :validator-vars validator-vars
                         :validator-functions state.validator-functions
                         :type-map state.type-map
                         :return-type fn-node.return-type})
        (local result (lower-stmt-list fn-state entry fn-node.body {:break-target nil :continue-target nil}))
        (when (not result.terminated)
          (if (= fn-node.return-type.name "void")
              (result.block:end-with-void-return nil)
              (error (.. "c-ir function missing return: " fn-node.name)))))))

(fn compile-jit [program opts]
  (local options (or opts {}))
  (assert-kind "program" :program program)
  (validate-program program :gccjit)
  (local ctxt (gccjit.Context))
  (ctxt:set-int-option (. gccjit.IntOption "optimization-level") (or options.optimization-level 0))

  (local struct-types {})
  (local union-types {})
  (local container-fields {})
  (local opaque-structs {})
  (local type-map {})
  (each [_ s (ipairs program.structs)]
    (local opaque (ctxt:new-opaque-struct nil s.name))
    (set (. opaque-structs s.name) opaque)
    (set (. struct-types s.name) (opaque:as-type))
    (set (. type-map s.name) s))

  (each [_ u (ipairs program.unions)]
    (set (. type-map u.name) u))

  (each [_ s (ipairs program.structs)]
    (local opaque (. opaque-structs s.name))
    (local fields [])
    (local field-map {})
    (each [_ f (ipairs s.fields)]
      (local fr (ctxt:new-field nil (type->gccjit ctxt f.type {:struct-types struct-types :union-types union-types}) f.name))
      (table.insert fields fr)
      (set (. field-map f.name) fr))
    (opaque:set-fields nil fields)
    (set (. struct-types s.name) (opaque:as-type))
    (set (. container-fields s.name) field-map))

  (each [_ u (ipairs program.unions)]
    (local fields [])
    (local field-map {})
    (each [_ f (ipairs u.fields)]
      (local fr (ctxt:new-field nil (type->gccjit ctxt f.type {:struct-types struct-types :union-types union-types}) f.name))
      (table.insert fields fr)
      (set (. field-map f.name) fr))
    (local ut (ctxt:new-union-type nil u.name fields))
    (set (. union-types u.name) ut)
    (set (. container-fields u.name) field-map))

  (local globals {})
  (local globals-types {})
  (each [_ g (ipairs program.globals)]
    (local kind (if g.imported (. gccjit.GlobalKind "imported")
                    (if g.internal (. gccjit.GlobalKind "internal") (. gccjit.GlobalKind "exported"))))
    (local gv (ctxt:new-global nil kind (type->gccjit ctxt g.type {:struct-types struct-types :union-types union-types}) g.name))
    (set (. globals g.name) gv)
    (set (. globals-types g.name) g.type))

  (local functions {})
  (each [_ fn-node (ipairs program.functions)]
    (local param-refs [])
    (each [_ p (ipairs fn-node.params)]
      (table.insert param-refs (ctxt:new-param nil (type->gccjit ctxt p.type {:struct-types struct-types :union-types union-types}) p.name)))
    (local fn-ref
      (ctxt:new-function nil
                         (resolve-function-kind fn-node)
                         (type->gccjit ctxt fn-node.return-type {:struct-types struct-types :union-types union-types})
                         fn-node.name
                         param-refs
                         fn-node.variadic))
    (set (. functions fn-node.name) fn-ref))

  (local fn-map {})
  (each [_ fn-node (ipairs program.functions)]
    (set (. fn-map fn-node.name) fn-node))

  (local state {:functions functions
                :globals globals
                :globals-types globals-types
                :struct-types struct-types
                :union-types union-types
                :container-fields container-fields
                :validator-functions fn-map
                :type-map type-map})

  (each [_ fn-node (ipairs program.functions)]
    (lower-function! ctxt fn-node (. functions fn-node.name) state))

  (local result (ctxt:compile))
  {:kind :jit-program
   :context ctxt
   :result result
   :call-i32 (fn [self name args] (self.result:call-i32 name args))
   :call-i64 (fn [self name args] (self.result:call-i64 name args))
   :call-double (fn [self name args] (self.result:call-double name args))
   :call-word (fn [self name args] (self.result:call-word name args))
   :call-pointer (fn [self name args] (self.result:call-pointer name args))
   :drop (fn [self]
           (when self.result
             (self.result:drop)
             (set self.result nil))
           (when self.context
             (self.context:drop)
             (set self.context nil)))})

(set type-equals? (fn [a b]
  (and a b
       (= a.kind :type)
       (= b.kind :type)
       (= a.name b.name)
       (= a.struct-name b.struct-name)
       (= a.union-name b.union-name)
       (= a.enum-name b.enum-name)
       (= (pointer-depth a) (pointer-depth b))
       (= (or a.const false) (or b.const false))
       (= (or a.volatile false) (or b.volatile false)))))

(fn is-integral-type? [t]
  (and t (= t.kind :type)
       (= (pointer-depth t) 0)
       (or t.enum-name
           (= t.name "bool")
           (= t.name "char")
           (= t.name "signed char")
           (= t.name "unsigned char")
           (= t.name "short")
           (= t.name "unsigned short")
           (= t.name "int")
           (= t.name "unsigned int")
           (= t.name "long")
           (= t.name "unsigned long")
           (= t.name "long long")
           (= t.name "unsigned long long")
           (= t.name "size_t"))))

(fn is-floating-type? [t]
  (and t (= t.kind :type)
       (= (pointer-depth t) 0)
       (or (= t.name "float") (= t.name "double") (= t.name "long double"))))

(fn is-numeric-type? [t]
  (or (is-integral-type? t) (is-floating-type? t)))

(fn is-pointer-type? [t]
  (and t (= t.kind :type) (> (pointer-depth t) 0)))

(fn unqualified-type [t]
  (if (not t)
      nil
      (Type t.name {:pointer (pointer-depth t)
                    :struct-name t.struct-name
                    :union-name t.union-name
                    :enum-name t.enum-name})))

(fn pointer-compatible? [a b]
  (or (type-equals? a b)
      (and (is-pointer-type? a)
           (is-pointer-type? b)
           (or (and (= (pointer-depth a) 1) (= a.name "void"))
               (and (= (pointer-depth b) 1) (= b.name "void"))
               (type-equals? (unqualified-type a) (unqualified-type b))))))

(fn type-assignable? [expected actual]
  (or (type-equals? expected actual)
      (and (is-numeric-type? expected) (is-numeric-type? actual))
      (pointer-compatible? expected actual)))

(fn integral-rank [t]
  (if t.enum-name 40
      (= t.name "bool") 10
      (= t.name "char") 15
      (= t.name "signed char") 15
      (= t.name "unsigned char") 15
      (= t.name "short") 20
      (= t.name "unsigned short") 20
      (= t.name "int") 30
      (= t.name "unsigned int") 30
      (= t.name "long") 35
      (= t.name "unsigned long") 35
      (= t.name "long long") 40
      (= t.name "unsigned long long") 40
      (= t.name "size_t") 45
      0))

(fn floating-rank [t]
  (if (= t.name "float") 10
      (= t.name "double") 20
      (= t.name "long double") 30
      0))

(fn common-arithmetic-type [lhs rhs]
  (if (or (not lhs) (not rhs))
      (Type "int")
      (and (is-floating-type? lhs) (or (> (floating-rank lhs) (floating-rank rhs))
                                       (not (is-floating-type? rhs))))
      lhs
      (and (is-floating-type? rhs) (or (> (floating-rank rhs) (floating-rank lhs))
                                       (not (is-floating-type? lhs))))
      rhs
      (>= (integral-rank lhs) (integral-rank rhs))
      lhs
      rhs))

(fn assert-type-compatible! [context expected actual]
  (when (not (type-assignable? expected actual))
    (local expected-name (if (and expected expected.name) expected.name "<nil>"))
    (local actual-name (if (and actual actual.name) actual.name "<nil>"))
    (error (.. "c-ir type mismatch in " context ": expected " expected-name ", got " actual-name))))

(fn validate-type! [t backend type-map]
  (assert-kind "type" :type t)
  (local pd (pointer-depth t))
  (when (or (not (= (type pd) :number)) (< pd 0))
    (error "c-ir type pointer depth must be integer >= 0"))
  (when t.struct-name
    (when (not (. type-map t.struct-name))
      (error (.. "c-ir unknown struct type: " t.struct-name))))
  (when t.union-name
    (when (not (. type-map t.union-name))
      (error (.. "c-ir unknown union type: " t.union-name))))
  (when t.enum-name
    (when (not (. type-map t.enum-name))
      (error (.. "c-ir unknown enum type: " t.enum-name))))
  (when (= backend :gccjit)
    (when (and (not t.struct-name)
               (not t.union-name)
               (not t.enum-name)
               (not (or (= t.name "void")
                        (= t.name "bool")
                        (= t.name "char")
                        (= t.name "signed char")
                        (= t.name "unsigned char")
                        (= t.name "short")
                        (= t.name "unsigned short")
                        (= t.name "int")
                        (= t.name "unsigned int")
                        (= t.name "long")
                        (= t.name "unsigned long")
                        (= t.name "long long")
                        (= t.name "unsigned long long")
                        (= t.name "float")
                        (= t.name "double")
                        (= t.name "long double")
                        (= t.name "size_t")
                        (= t.name "const char *"))))
      (error (.. "c-ir unsupported gccjit type name: " t.name)))))

(set infer-lvalue-type! (fn [expr functions vars backend type-map]
  (if (= expr.kind :var)
      (do
        (local t (. vars expr.name))
        (if t t (error (.. "c-ir assign target not declared: " expr.name))))
      (= expr.kind :deref)
      (do
        (local pt (infer-expr-type! expr.expr functions vars backend type-map))
        (when (<= (pointer-depth pt) 0)
          (error "c-ir deref target must be pointer"))
        (with-pointer-depth pt (- (pointer-depth pt) 1)))
      (= expr.kind :field)
      (do
        (var bt (infer-expr-type! expr.base functions vars backend type-map))
        (if expr.pointer
            (do
              (when (<= (pointer-depth bt) 0)
                (error "c-ir field pointer access requires pointer base"))
              (set bt (with-pointer-depth bt (- (pointer-depth bt) 1))))
            nil)
        (local container-name (if bt.struct-name bt.struct-name bt.union-name))
        (when (not container-name)
          (error "c-ir field access base must be struct/union type"))
        (local s (. type-map container-name))
        (var f nil)
        (each [_ sf (ipairs (or s.fields []))]
          (when (= sf.name expr.field)
            (set f sf)))
        (if f f.type (error (.. "c-ir unknown field: " container-name "." expr.field))))
      (= expr.kind :index)
      (do
        (local bt (infer-expr-type! expr.base functions vars backend type-map))
        (when (<= (pointer-depth bt) 0)
          (error "c-ir index base must be pointer"))
        (with-pointer-depth bt (- (pointer-depth bt) 1)))
      (error (.. "c-ir expression not assignable: " (tostring expr.kind))))))

(set infer-expr-type! (fn [expr functions vars backend struct-map]
  (if (= expr nil)
      nil
      (= (type expr) :number)
      (Type "int")
      (= (type expr) :string)
      (error "c-ir raw string expressions are not supported in validated IR")
      (= expr.kind :int)
      (Type "int")
      (= expr.kind :double)
      (Type "double")
      (= expr.kind :string-literal)
      (Type "const char *")
      (= expr.kind :init-list)
      (error "c-ir init-list type is context-dependent")
      (= expr.kind :null)
      expr.type
      (= expr.kind :var)
      (do
        (local t (. vars expr.name))
        (if t t (error (.. "c-ir variable not declared in scope: " expr.name))))
      (= expr.kind :call)
      (do
        (local fn-node (. functions expr.name))
        (when (not fn-node)
          (error (.. "c-ir call target not found: " expr.name)))
        (when (not (= (# expr.args) (# fn-node.params)))
          (error (.. "c-ir call arg count mismatch for " expr.name
                     ": expected " (# fn-node.params)
                     ", got " (# expr.args))))
        (each [i arg (ipairs expr.args)]
          (local actual-type (infer-expr-type! arg functions vars backend struct-map))
          (local expected-type (. (. fn-node.params i) :type))
          (assert-type-compatible! (.. "call arg " i " for " expr.name) expected-type actual-type))
        fn-node.return-type)
      (= expr.kind :function-ref)
      (do
        (local fn-node (. functions expr.name))
        (when (not fn-node)
          (error (.. "c-ir function ref target not found: " expr.name)))
        (Type "void" {:pointer 1}))
      (= expr.kind :call-ptr)
      (do
        (local fn-type (infer-expr-type! expr.fn-expr functions vars backend struct-map))
        (when (not (is-pointer-type? fn-type))
          (error "c-ir call-ptr function expression must be pointer"))
        (when (not (= (# expr.args) (# expr.param-types)))
          (if expr.variadic
              (when (< (# expr.args) (# expr.param-types))
                (error (.. "c-ir call-ptr requires at least " (# expr.param-types) " args")))
              (error (.. "c-ir call-ptr arg count mismatch: expected "
                         (# expr.param-types) ", got " (# expr.args)))))
        (each [i arg (ipairs expr.args)]
          (if (<= i (# expr.param-types))
              (do
                (local actual-type (infer-expr-type! arg functions vars backend struct-map))
                (local expected-type (. expr.param-types i))
                (assert-type-compatible! (.. "call-ptr arg " i) expected-type actual-type))
              (when (not expr.variadic)
                (error "c-ir non-variadic call-ptr has extra args"))))
        expr.return-type)
      (= expr.kind :binary)
      (do
        (when (not (or (= expr.op "+") (= expr.op "-") (= expr.op "*") (= expr.op "/")
                       (= expr.op "%") (= expr.op "&") (= expr.op "|") (= expr.op "^")
                       (= expr.op "<<") (= expr.op ">>") (= expr.op "&&") (= expr.op "||")))
          (error (.. "c-ir unsupported binary op: " expr.op)))
        (local lhs-type (infer-expr-type! expr.lhs functions vars backend struct-map))
        (local rhs-type (infer-expr-type! expr.rhs functions vars backend struct-map))
        (if (or (= expr.op "&&") (= expr.op "||"))
            (do
              (when (not (or (is-numeric-type? lhs-type) (is-pointer-type? lhs-type)))
                (error (.. "c-ir logical binary lhs must be scalar: " expr.op)))
              (when (not (or (is-numeric-type? rhs-type) (is-pointer-type? rhs-type)))
                (error (.. "c-ir logical binary rhs must be scalar: " expr.op)))
              (Type "int"))
            (do
              (when (and (or (= expr.op "%") (= expr.op "&") (= expr.op "|") (= expr.op "^")
                             (= expr.op "<<") (= expr.op ">>"))
                         (or (not (is-integral-type? lhs-type))
                             (not (is-integral-type? rhs-type))))
                (error (.. "c-ir binary op requires integral operands: " expr.op)))
              (when (and (or (= expr.op "+") (= expr.op "-") (= expr.op "*") (= expr.op "/"))
                         (or (not (is-numeric-type? lhs-type))
                             (not (is-numeric-type? rhs-type))))
                (error (.. "c-ir binary op requires numeric operands: " expr.op)))
              (local common-type (common-arithmetic-type lhs-type rhs-type))
              (if expr.result-type
                  (do
                    (validate-type! expr.result-type backend struct-map)
                    (assert-type-compatible! (.. "binary result-type for op " expr.op) expr.result-type common-type)
                    expr.result-type)
                  common-type))))
      (= expr.kind :unary)
      (do
        (when (not (or (= expr.op "-") (= expr.op "~") (= expr.op "!") (= expr.op "abs")))
          (error (.. "c-ir unsupported unary op: " expr.op)))
        (local t (infer-expr-type! expr.expr functions vars backend struct-map))
        (if (= expr.op "!")
            (Type "int")
            (do
              (when (and (= expr.op "~") (not (is-integral-type? t)))
                (error "c-ir unary bitwise negate requires integral operand"))
              (when (and (or (= expr.op "-") (= expr.op "abs")) (not (is-numeric-type? t)))
                (error "c-ir unary numeric op requires numeric operand"))
              (if expr.result-type
                  (do
                    (validate-type! expr.result-type backend struct-map)
                    expr.result-type)
                  t))))
      (= expr.kind :compare)
      (do
        (when (not (or (= expr.op "==") (= expr.op "!=") (= expr.op "<") (= expr.op "<=")
                       (= expr.op ">") (= expr.op ">=")))
          (error (.. "c-ir unsupported comparison op: " expr.op)))
        (local lhs-type (infer-expr-type! expr.lhs functions vars backend struct-map))
        (local rhs-type (infer-expr-type! expr.rhs functions vars backend struct-map))
        (when (not (or (and (is-numeric-type? lhs-type) (is-numeric-type? rhs-type))
                       (pointer-compatible? lhs-type rhs-type)))
          (error (.. "c-ir comparison operands incompatible for op " expr.op)))
        (Type "int"))
      (= expr.kind :cast)
      (do
        (validate-type! expr.type backend struct-map)
        (infer-expr-type! expr.expr functions vars backend struct-map)
        expr.type)
      (= expr.kind :address-of)
      (do
        (local t (infer-lvalue-type! expr.expr functions vars backend struct-map))
        (with-pointer-depth t (+ (pointer-depth t) 1)))
      (= expr.kind :deref)
      (do
        (local t (infer-expr-type! expr.expr functions vars backend struct-map))
        (when (<= (pointer-depth t) 0)
          (error "c-ir dereference requires pointer expression"))
        (with-pointer-depth t (- (pointer-depth t) 1)))
      (= expr.kind :field)
      (infer-lvalue-type! expr functions vars backend struct-map)
      (= expr.kind :index)
      (infer-lvalue-type! expr functions vars backend struct-map)
      (error (.. "c-ir unsupported expression in validator: " (tostring expr.kind))))))

(fn validate-init-list! [init-list expected-type functions vars backend type-map]
  (when (not (= init-list.kind :init-list))
    (error "c-ir expected init-list"))
  (if expected-type.struct-name
      (do
        (local s (. type-map expected-type.struct-name))
        (var positional-count 0)
        (each [_ item (ipairs init-list.values)]
          (if (and (= (type item) :table) (= item.kind :designated-init))
              nil
              (set positional-count (+ positional-count 1))))
        (when (> positional-count (# s.fields))
          (error (.. "c-ir too many initializer values for struct " expected-type.struct-name)))
        (var next-index 1)
        (each [i v (ipairs init-list.values)]
          (if (and (= (type v) :table) (= v.kind :designated-init))
              (do
                (var sf nil)
                (each [_ f (ipairs s.fields)]
                  (when (= f.name v.field)
                    (set sf f)))
                (when (not sf)
                  (error (.. "c-ir unknown designated init field: " expected-type.struct-name "." v.field)))
                (if (and (= (type v.expr) :table) (= v.expr.kind :init-list))
                    (validate-init-list! v.expr sf.type functions vars backend type-map)
                    (do
                      (local vt (infer-expr-type! v.expr functions vars backend type-map))
                      (assert-type-compatible! (.. "struct designated initializer field " v.field) sf.type vt))))
              (do
                (local sf (. s.fields next-index))
                (local ft sf.type)
                (if (and (= (type v) :table) (= v.kind :init-list))
                    (validate-init-list! v ft functions vars backend type-map)
                    (do
                      (local vt (infer-expr-type! v functions vars backend type-map))
                      (assert-type-compatible! (.. "struct initializer field " i) ft vt)))
                (set next-index (+ next-index 1))))))
      expected-type.union-name
      (do
        (local u (. type-map expected-type.union-name))
        (when (> (# init-list.values) 1)
          (error (.. "c-ir union initializer supports at most one value: " expected-type.union-name)))
        (when (= (# init-list.values) 1)
          (local uf (. u.fields 1))
          (local ft uf.type)
          (local v (. init-list.values 1))
          (if (and (= (type v) :table) (= v.kind :designated-init))
              (do
                (when (not (= v.field uf.name))
                  (error "c-ir union designated initializer must target first field"))
                (if (and (= (type v.expr) :table) (= v.expr.kind :init-list))
                    (validate-init-list! v.expr ft functions vars backend type-map)
                    (do
                      (local vt (infer-expr-type! v.expr functions vars backend type-map))
                      (assert-type-compatible! "union designated initializer" ft vt))))
              (if (and (= (type v) :table) (= v.kind :init-list))
                  (validate-init-list! v ft functions vars backend type-map)
                  (do
                    (local vt (infer-expr-type! v functions vars backend type-map))
                    (assert-type-compatible! "union initializer" ft vt))))))
      (error "c-ir init-list requires struct/union destination type")))

(fn validate-stmt-list! [stmts functions vars return-type backend struct-map flow]
  (var has-terminator false)
  (each [_ stmt (ipairs stmts)]
    (when has-terminator
      (error "c-ir unreachable statement after terminator"))
    (if (= stmt.kind :return)
        (do
          (if (= return-type.name "void")
              (when (not (= stmt.expr nil))
                (error "c-ir void function return must not include expression"))
              (do
                (when (= stmt.expr nil)
                  (error "c-ir non-void function return requires expression"))
                (local expr-type (infer-expr-type! stmt.expr functions vars backend struct-map))
                (assert-type-compatible! "return expression" return-type expr-type)))
          (set has-terminator true))
        (= stmt.kind :declare)
        (do
          (validate-type! stmt.type backend struct-map)
          (set (. vars stmt.name) stmt.type)
          (when (not (= stmt.init nil))
            (if (and (= (type stmt.init) :table) (= stmt.init.kind :init-list))
                (validate-init-list! stmt.init stmt.type functions vars backend struct-map)
                (do
                  (local init-type (infer-expr-type! stmt.init functions vars backend struct-map))
                  (assert-type-compatible! (.. "initializer for " stmt.name) stmt.type init-type))))
            (when (and (= backend :gccjit)
                       (= (type stmt.init) :table)
                       (= stmt.init.kind :init-list)
                       (not (or stmt.type.struct-name stmt.type.union-name)))
              (error "c-ir gccjit init-list currently supports struct/union only")))
        (= stmt.kind :assign)
        (do
          (local target-type (infer-lvalue-type! stmt.target functions vars backend struct-map))
          (local expr-type (infer-expr-type! stmt.expr functions vars backend struct-map))
          (assert-type-compatible! "assignment" target-type expr-type))
        (= stmt.kind :expr)
        (infer-expr-type! stmt.expr functions vars backend struct-map)
        (= stmt.kind :break)
        (when (not flow.breakable)
          (error "c-ir break used outside loop/switch"))
        (= stmt.kind :continue)
        (when (not flow.continuable)
          (error "c-ir continue used outside loop"))
        (= stmt.kind :block)
        (do
          (local nested (copy-table vars))
          (validate-stmt-list! stmt.body functions nested return-type backend struct-map flow))
        (= stmt.kind :if)
        (do
          (local condition-type (infer-expr-type! stmt.condition functions vars backend struct-map))
          (when (not (is-numeric-type? condition-type))
            (error "c-ir if condition must be numeric/int-compatible"))
          (local then-vars (copy-table vars))
          (validate-stmt-list! stmt.then-body functions then-vars return-type backend struct-map flow)
          (when stmt.else-body
            (local else-vars (copy-table vars))
            (validate-stmt-list! stmt.else-body functions else-vars return-type backend struct-map flow)))
        (= stmt.kind :while)
        (do
          (local condition-type (infer-expr-type! stmt.condition functions vars backend struct-map))
          (when (not (is-numeric-type? condition-type))
            (error "c-ir while condition must be numeric/int-compatible"))
          (local body-vars (copy-table vars))
          (validate-stmt-list! stmt.body functions body-vars return-type backend struct-map
                               {:breakable true :continuable true}))
        (= stmt.kind :do-while)
        (do
          (local body-vars (copy-table vars))
          (validate-stmt-list! stmt.body functions body-vars return-type backend struct-map
                               {:breakable true :continuable true})
          (local condition-type (infer-expr-type! stmt.condition functions vars backend struct-map))
          (when (not (is-numeric-type? condition-type))
            (error "c-ir do-while condition must be numeric/int-compatible")))
        (= stmt.kind :for)
        (do
          (local loop-vars (copy-table vars))
          (when stmt.init
            (validate-stmt-list! [stmt.init] functions loop-vars return-type backend struct-map flow))
          (when stmt.condition
            (local condition-type (infer-expr-type! stmt.condition functions loop-vars backend struct-map))
            (when (not (is-numeric-type? condition-type))
              (error "c-ir for condition must be numeric/int-compatible")))
          (local body-vars (copy-table loop-vars))
          (validate-stmt-list! stmt.body functions body-vars return-type backend struct-map
                               {:breakable true :continuable true})
          (when stmt.post
            (validate-stmt-list! [stmt.post] functions body-vars return-type backend struct-map
                                 {:breakable false :continuable false})))
        (= stmt.kind :switch)
        (do
          (local st (infer-expr-type! stmt.expr functions vars backend struct-map))
          (when (not (is-integral-type? st))
            (error "c-ir switch expression must be integral"))
          (each [_ sc (ipairs stmt.cases)]
            (when (not (= sc.kind :switch-case))
              (error "c-ir switch cases must be switch-case"))
            (local vt (infer-expr-type! sc.value functions vars backend struct-map))
            (when (not (is-integral-type? vt))
              (error "c-ir switch case values must be integral"))
            (local case-vars (copy-table vars))
            (validate-stmt-list! sc.body functions case-vars return-type backend struct-map
                                 {:breakable true :continuable flow.continuable}))
          (local default-vars (copy-table vars))
          (validate-stmt-list! stmt.default-body functions default-vars return-type backend struct-map
                               {:breakable true :continuable flow.continuable}))
        (error (.. "c-ir unsupported statement in validator: " (tostring stmt.kind)))))
  has-terminator)

(fn validate-function! [fn-node functions globals struct-map backend]
  (assert-kind "function" :function fn-node)
  (validate-type! fn-node.return-type backend struct-map)
  (local vars (copy-table globals))
  (each [_ p (ipairs fn-node.params)]
    (assert-kind "param" :param p)
    (validate-type! p.type backend struct-map)
    (set (. vars p.name) p.type))
  (when (not fn-node.imported)
    (validate-stmt-list! fn-node.body functions vars fn-node.return-type backend struct-map
                         {:breakable false :continuable false})))

(set validate-program (fn [program backend]
  (assert-kind "program" :program program)

  (local type-map {})
  (each [_ s (ipairs program.structs)]
    (assert-kind "struct" :struct s)
    (when (. type-map s.name)
      (error (.. "c-ir duplicate struct name: " s.name)))
    (set (. type-map s.name) s))
  (each [_ u (ipairs program.unions)]
    (assert-kind "union" :union u)
    (when (. type-map u.name)
      (error (.. "c-ir duplicate union name: " u.name)))
    (set (. type-map u.name) u))
  (each [_ e (ipairs program.enums)]
    (assert-kind "enum" :enum e)
    (when (. type-map e.name)
      (error (.. "c-ir duplicate enum name: " e.name)))
    (set (. type-map e.name) e))

  (each [_ s (ipairs program.structs)]
    (each [_ f (ipairs s.fields)]
      (assert-kind "struct field" :struct-field f)
      (validate-type! f.type backend type-map)))
  (each [_ u (ipairs program.unions)]
    (each [_ f (ipairs u.fields)]
      (assert-kind "union field" :struct-field f)
      (validate-type! f.type backend type-map)))
  (each [_ e (ipairs program.enums)]
    (var next-value 0)
    (each [_ item (ipairs e.items)]
      (assert-kind "enum item" :enum-item item)
      (when (not (= item.value nil))
        (local vtype (infer-expr-type! item.value {} {} backend type-map))
        (when (not (is-integral-type? vtype))
          (error (.. "c-ir enum value must be integral: " item.name)))
        (set next-value 0))
      (set next-value (+ next-value 1))))

  (local globals {})
  (each [_ g (ipairs program.globals)]
    (assert-kind "global" :global g)
    (when (. globals g.name)
      (error (.. "c-ir duplicate global name: " g.name)))
    (validate-type! g.type backend type-map)
    (set (. globals g.name) g.type)
    (when (not (= g.init nil))
      (local fake-functions {})
      (if (and (= (type g.init) :table) (= g.init.kind :init-list))
          (do
            (when (= backend :gccjit)
              (error "c-ir gccjit global init-list is not supported"))
            (validate-init-list! g.init g.type fake-functions globals backend type-map))
          (do
            (local init-type (infer-expr-type! g.init fake-functions globals backend type-map))
            (assert-type-compatible! (.. "global initializer " g.name) g.type init-type)))))

  (local functions {})
  (each [_ fn-node (ipairs program.functions)]
    (assert-kind "program function" :function fn-node)
    (when (. functions fn-node.name)
      (error (.. "c-ir duplicate function name: " fn-node.name)))
    (set (. functions fn-node.name) fn-node))

  (each [_ fn-node (ipairs program.functions)]
    (validate-function! fn-node functions globals type-map backend))
  true))

(local Factory
  (fn []
    {:Type Type
     :StructType StructType
     :UnionType UnionType
     :EnumType EnumType
     :Param Param
     :StructField StructField
     :EnumItem EnumItem
     :Struct Struct
     :Union Union
     :Enum Enum
     :Global Global
     :Int Int
     :Double Double
     :StringLiteral StringLiteral
     :InitList InitList
     :DesignatedInit DesignatedInit
     :Null Null
     :Var Var
     :Binary Binary
     :Unary Unary
     :Compare Compare
     :Cast Cast
     :AddressOf AddressOf
     :Deref Deref
     :Field Field
     :Index Index
     :Call Call
     :FunctionRef FunctionRef
     :CallPtr CallPtr
     :Return Return
     :Declare Declare
     :Assign Assign
     :Expr Expr
     :Break Break
     :Continue Continue
     :Block Block
     :If If
     :While While
     :DoWhile DoWhile
     :For For
     :SwitchCase SwitchCase
     :Switch Switch
     :Function Function
     :Program Program}))

{:Factory Factory
 :Type Type
 :StructType StructType
 :UnionType UnionType
 :EnumType EnumType
 :Param Param
 :StructField StructField
 :EnumItem EnumItem
 :Struct Struct
 :Union Union
 :Enum Enum
 :Global Global
 :Int Int
 :Double Double
 :StringLiteral StringLiteral
 :InitList InitList
 :DesignatedInit DesignatedInit
 :Null Null
 :Var Var
 :Binary Binary
 :Unary Unary
 :Compare Compare
 :Cast Cast
 :AddressOf AddressOf
 :Deref Deref
 :Field Field
 :Index Index
 :Call Call
 :FunctionRef FunctionRef
 :CallPtr CallPtr
 :Return Return
 :Declare Declare
 :Assign Assign
 :Expr Expr
 :Break Break
 :Continue Continue
 :Block Block
 :If If
 :While While
 :DoWhile DoWhile
 :For For
 :SwitchCase SwitchCase
 :Switch Switch
 :Function Function
 :Program Program
 :validate-program validate-program
 :to-c-builder to-c-builder
 :write-file write-file
 :compile-jit compile-jit}
