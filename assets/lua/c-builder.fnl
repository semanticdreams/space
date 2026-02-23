(local fs (require :fs))

(local BraceStyle {:allman :allman
                   :attach :attach
                   :linux :linux})

(local PointerAlignment {:left :left
                         :right :right
                         :middle :middle})

(local ShortFunctionStyle {:never :never
                           :empty :empty
                           :inline :inline})

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
    (error (.. "c-builder " name " must be an array"))))

(fn assert-string [name value]
  (when (not (= (type value) :string))
    (error (.. "c-builder " name " must be a string"))))

(fn assert-kind [name value]
  (when (or (not (= (type value) :table)) (= value.kind nil))
    (error (.. "c-builder " name " must be a c-builder element"))))

(fn normalize-expr [value]
  (if (= (type value) :boolean)
      (if value "true" "false")
      (= (type value) :number)
      (tostring value)
      (= (type value) :string)
      value
      (do
        (assert-kind "expression" value)
        value)))

(fn quote-string [value]
  (local escaped (string.gsub value "\\" "\\\\"))
  (local escaped2 (string.gsub escaped "\"" "\\\""))
  (string.gsub escaped2 "\n" "\\n"))

(fn make-sequence [kind]
  (local self
    {:kind kind
     :elements []
     :append (fn [self elem]
               (table.insert self.elements elem)
               self)
     :extend (fn [self seq]
               (assert-kind "sequence.extend" seq)
               (when (not (or (= seq.kind :sequence) (= seq.kind :block)))
                 (error "c-builder sequence.extend expects sequence or block"))
               (each [_ elem (ipairs seq.elements)]
                 (table.insert self.elements elem))
               self)})
  self)

(fn sequence []
  (make-sequence :sequence))

(fn block []
  (make-sequence :block))

(fn blank []
  {:kind :blank})

(fn whitespace [width]
  (when (or (not (= (type width) :number))
            (not (= width (math.floor width)))
            (< width 0))
    (error "c-builder whitespace width must be an integer >= 0"))
  {:kind :whitespace
   :width width})

(fn line-comment [text opts]
  (local options (or opts {}))
  (assert-string "line-comment text" text)
  {:kind :line-comment
   :text text
   :adjust (or options.adjust 1)})

(fn block-comment [text opts]
  (local options (or opts {}))
  (when (not (or (= (type text) :string) (is-array? text)))
    (error "c-builder block-comment text must be string or array of strings"))
  (when (is-array? text)
    (each [_ line (ipairs text)]
      (assert-string "block-comment text line" line)))
  {:kind :block-comment
   :text text
   :adjust (or options.adjust 1)
   :width (or options.width 0)
   :line-start (or options.line-start "")})

(fn line [parts]
  (local normalized
    (if (or (= (type parts) :string)
            (and (= (type parts) :table) (not (is-array? parts)) (not (= parts.kind nil))))
        [parts]
        (do
          (assert-array "line parts" parts)
          parts)))
  {:kind :line
   :parts normalized})

(fn include-file [path opts]
  (local options (or opts {}))
  (assert-string "include path" path)
  {:kind :include-directive
   :path path
   :system (or options.system false)
   :adjust (or options.adjust 0)})

(fn sysinclude [path opts]
  (local options (or opts {}))
  (include-file path {:system true :adjust options.adjust}))

(fn ifdef [identifier opts]
  (local options (or opts {}))
  (assert-string "ifdef identifier" identifier)
  {:kind :ifdef-directive
   :identifier identifier
   :adjust (or options.adjust 0)})

(fn ifndef [identifier opts]
  (local options (or opts {}))
  (assert-string "ifndef identifier" identifier)
  {:kind :ifndef-directive
   :identifier identifier
   :adjust (or options.adjust 0)})

(fn endif [opts]
  (local options (or opts {}))
  {:kind :endif-directive
   :adjust (or options.adjust 0)})

(fn define [lhs rhs opts]
  (local options (or opts {}))
  (assert-string "define lhs" lhs)
  (when (and (not (= rhs nil)) (not (= (type rhs) :string)))
    (error "c-builder define rhs must be string when provided"))
  {:kind :define-directive
   :lhs lhs
   :rhs rhs
   :adjust (or options.adjust 0)})

(fn extern [language]
  (assert-string "extern language" language)
  {:kind :extern
   :language language})

(fn type* [base-type opts]
  (local options (or opts {}))
  (when (not (or (= (type base-type) :string)
                 (and (= (type base-type) :table)
                      (or (= base-type.kind :type)
                          (= base-type.kind :typedef)
                          (= base-type.kind :struct)))))
    (error "c-builder type base-type must be string/type/typedef/struct"))
  {:kind :type
   :base-type base-type
   :const (or options.const false)
   :volatile (or options.volatile false)
   :pointer (or options.pointer false)
   :array options.array})

(fn struct-member [name data-type opts]
  (local options (or opts {}))
  (assert-string "struct-member name" name)
  (when (not (or (= (type data-type) :string)
                 (and (= (type data-type) :table)
                      (or (= data-type.kind :type)
                          (= data-type.kind :typedef)
                          (= data-type.kind :struct)))))
    (error "c-builder struct-member data-type must be string/type/typedef/struct"))
  {:kind :struct-member
   :name name
   :data-type (if (= (type data-type) :string) (type* data-type) data-type)
   :const (or options.const false)
   :pointer (or options.pointer false)
   :array options.array})

(fn struct* [name members]
  (assert-string "struct name" name)
  (local self
    {:kind :struct
     :name name
     :members []
     :append (fn [self member]
               (when (or (not (= (type member) :table)) (not (= member.kind :struct-member)))
                 (error "c-builder struct.append expects struct-member"))
               (table.insert self.members member)
               self)
     :make-member (fn [self member-name data-type opts]
                    (local member (struct-member member-name data-type opts))
                    (table.insert self.members member)
                    member)})
  (when members
    (assert-array "struct members" members)
    (each [_ member (ipairs members)]
      (self:append member)))
  self)

(fn variable [name data-type opts]
  (local options (or opts {}))
  (assert-string "variable name" name)
  (when (not (or (= (type data-type) :string)
                 (and (= (type data-type) :table)
                      (or (= data-type.kind :type)
                          (= data-type.kind :typedef)
                          (= data-type.kind :struct)
                          (= data-type.kind :declaration)))))
    (error "c-builder variable data-type must be string/type/typedef/struct/declaration"))
  {:kind :variable
   :name name
   :data-type (if (= (type data-type) :string) (type* data-type) data-type)
   :const (or options.const false)
   :pointer (or options.pointer false)
   :extern (or options.extern false)
   :static (or options.static false)
   :array options.array})

(fn function [name return-type opts]
  (local options (or opts {}))
  (assert-string "function name" name)
  (when (and (not (= return-type nil))
             (not (or (= (type return-type) :string)
                      (and (= (type return-type) :table)
                           (or (= return-type.kind :type)
                               (= return-type.kind :typedef)
                               (= return-type.kind :struct))))))
    (error "c-builder function return-type must be string/type/typedef/struct when provided"))
  (local self
    {:kind :function
     :name name
     :return-type (if (= return-type nil)
                      (type* "void")
                      (if (= (type return-type) :string)
                          (type* return-type)
                          return-type))
     :static (or options.static false)
     :extern (or options.extern false)
     :const (or options.const false)
     :params []
     :append (fn [self param]
               (when (or (not (= (type param) :table)) (not (= param.kind :variable)))
                 (error "c-builder function.append expects variable"))
               (table.insert self.params param)
               self)
     :make-param (fn [self param-name data-type param-opts]
                   (local param (variable param-name data-type param-opts))
                   (table.insert self.params param)
                   param)})
  (when options.params
    (assert-array "function params" options.params)
    (each [_ param (ipairs options.params)]
      (self:append param)))
  self)

(fn declaration [element init-value]
  (when (or (not (= (type element) :table))
            (not (or (= element.kind :variable)
                     (= element.kind :function)
                     (= element.kind :type)
                     (= element.kind :typedef)
                     (= element.kind :struct))))
    (error "c-builder declaration element must be variable/function/type/typedef/struct"))
  (when (and (not (= init-value nil)) (not (= element.kind :variable)))
    (error "c-builder declaration init-value is only valid for variable declarations"))
  {:kind :declaration
   :element element
   :init-value init-value})

(fn typedef [name base-type opts]
  (local options (or opts {}))
  (assert-string "typedef name" name)
  (when (not (or (= (type base-type) :string)
                 (and (= (type base-type) :table)
                      (or (= base-type.kind :type)
                          (= base-type.kind :typedef)
                          (= base-type.kind :struct)
                          (= base-type.kind :declaration)))))
    (error "c-builder typedef base-type must be string/type/typedef/struct/declaration"))
  {:kind :typedef
   :name name
   :base-type (if (= (type base-type) :string) (type* base-type) base-type)
   :const (or options.const false)
   :volatile (or options.volatile false)
   :pointer (or options.pointer false)
   :array options.array})

(fn assignment [lhs rhs]
  {:kind :assignment
   :lhs (normalize-expr lhs)
   :rhs (normalize-expr rhs)})

(fn str-literal [text]
  (assert-string "str-literal text" text)
  {:kind :string-literal
   :text text})

(fn func-call [name args]
  (assert-string "func-call name" name)
  (local self
    {:kind :function-call
     :name name
     :args []
     :append (fn [self arg]
               (table.insert self.args (normalize-expr arg))
               self)})
  (when (not (= args nil))
    (if (is-array? args)
        (each [_ arg (ipairs args)]
          (self:append arg))
        (self:append args)))
  self)

(fn func-return [value]
  {:kind :function-return
   :value (normalize-expr value)})

(fn statement [expr]
  (local parts
    (if (is-array? expr)
        (do
          (assert-array "statement parts" expr)
          (icollect [_ part (ipairs expr)] (normalize-expr part)))
        (do
          (when (and (= (type expr) :table) (= expr.kind nil))
            (error "c-builder statement table values must be arrays or c-builder elements"))
        [(normalize-expr expr)]
        )))
  {:kind :statement
   :parts parts})

(fn style-defaults [brace-style]
  (if (= brace-style BraceStyle.allman)
      {:after-function true
       :after-struct true}
      (= brace-style BraceStyle.linux)
      {:after-function true
       :after-struct false}
      {:after-function false
       :after-struct false}))

(fn Style [opts]
  (local options (or opts {}))
  (local brace-style (or options.break-before-braces BraceStyle.attach))
  (when (not (or (= brace-style BraceStyle.attach)
                 (= brace-style BraceStyle.allman)
                 (= brace-style BraceStyle.linux)))
    (error "c-builder style break-before-braces must be attach/allman/linux"))
  (local defaults (style-defaults brace-style))
  {:break-before-braces brace-style
   :indent-width (or options.indent-width 4)
   :indent-char (or options.indent-char " ")
   :pointer-alignment (or options.pointer-alignment PointerAlignment.right)
   :short-functions-on-single-line (or options.short-functions-on-single-line ShortFunctionStyle.never)
   :brace-wrapping {:after-function (if (= (. defaults :after-function) nil)
                                        false
                                        (. defaults :after-function))
                    :after-struct (if (= (. defaults :after-struct) nil)
                                      false
                                      (. defaults :after-struct))}
   :type-qualifier-order (or options.type-qualifier-order ["const" "volatile" "type"])
   :storage-class-order (or options.storage-class-order ["static" "extern" "object"])})

(fn Writer [style-opts]
  (local style (or style-opts (Style)))
  (local state {:chunks []
                :line-start true
                :indent-level 0
                :last-element :none})
  (var write-element nil)
  (var write-sequence nil)
  (var format-type-part nil)
  (var write-declaration nil)
  (var write-initializer nil)
  (var write-initializer-member nil)

  (fn push [text]
    (table.insert state.chunks text))

  (fn indent-string []
    (string.rep style.indent-char (* style.indent-width state.indent-level)))

  (fn emit [text]
    (when state.line-start
      (push (indent-string))
      (set state.line-start false))
    (push text))

  (fn eol []
    (push "\n")
    (set state.line-start true))

  (fn write-expression [expr]
    (if (= (type expr) :string)
        (emit expr)
        (write-element expr)))

  (fn pointer-joiner [base-has-pointer]
    (if (= style.pointer-alignment PointerAlignment.left)
        "*"
        (= style.pointer-alignment PointerAlignment.middle)
        " * "
        (if base-has-pointer "*" " *")))

  (fn format-type [t]
    (when (not (= t.kind :type))
      (error "c-builder internal: format-type expects :type"))
    (local parts [])
    (each [_ key (ipairs style.type-qualifier-order)]
      (if (= key "const")
          (when t.const
            (table.insert parts "const"))
          (= key "volatile")
          (when t.volatile
            (table.insert parts "volatile"))
          (= key "type")
          (table.insert parts (format-type-part t))
          (error (.. "c-builder unknown type qualifier key: " key))))
    (table.concat parts " "))

  (set format-type-part (fn [t]
    (local base
      (if (= (type t.base-type) :string)
          t.base-type
          (= t.base-type.kind :type)
          (format-type t.base-type)
          (= t.base-type.kind :typedef)
          t.base-type.name
          (= t.base-type.kind :struct)
          (.. "struct " t.base-type.name)
          (error "c-builder unsupported base type in type part")))
    (if t.pointer
        (if (= style.pointer-alignment PointerAlignment.left)
            (.. base "*")
            (.. base " *"))
        base)))

  (fn write-variable-usage [v]
    (emit v.name)
    (set state.last-element :variable-usage))

  (fn write-pointer-suffix [pointer pointer-const name base-is-pointer]
    (if pointer
        (if pointer-const
            (if (= style.pointer-alignment PointerAlignment.left)
                (emit (.. "* const " name))
                (= style.pointer-alignment PointerAlignment.middle)
                (emit (.. " * const " name))
                (emit (.. "*const " name)))
            (if (= style.pointer-alignment PointerAlignment.left)
                (emit (.. "* " name))
                (= style.pointer-alignment PointerAlignment.middle)
                (emit (.. " * " name))
                (emit (.. (pointer-joiner base-is-pointer) name))))
        (emit (.. " " name))))

  (fn write-type-usage [value]
    (if (= value.kind :type)
        (emit (format-type value))
        (= value.kind :typedef)
        (emit value.name)
        (= value.kind :struct)
        (emit (.. "struct " value.name))
        (= value.kind :declaration)
        (write-declaration value)
        (error "c-builder unsupported type usage")))

  (fn write-struct-member [member]
    (write-type-usage member.data-type)
    (local base-is-pointer (and (= member.data-type.kind :type) member.data-type.pointer))
    (write-pointer-suffix member.pointer member.const member.name base-is-pointer)
    (when member.array
      (emit (.. "[" member.array "]"))))

  (fn write-variable-declaration [value]
    (each [_ key (ipairs style.storage-class-order)]
      (if (= key "static")
          (when value.static
            (emit "static "))
          (= key "extern")
          (when value.extern
            (emit "extern "))
          (= key "object")
          nil
          (error (.. "c-builder unknown storage class key: " key))))
    (write-type-usage value.data-type)
    (local base-is-pointer (and (= value.data-type.kind :type) value.data-type.pointer))
    (write-pointer-suffix value.pointer value.const value.name base-is-pointer)
    (when value.array
      (emit (.. "[" value.array "]")))
    (set state.last-element :variable-declaration))

  (fn write-function-declaration [value]
    (when value.extern
      (emit "extern "))
    (when value.static
      (emit "static "))
    (write-type-usage value.return-type)
    (emit (.. " " value.name "("))
    (if (> (# value.params) 0)
        (each [i param (ipairs value.params)]
          (when (> i 1)
            (emit ", "))
          (write-variable-declaration param))
        (emit "void"))
    (emit ")")
    (when value.const
      (emit " const"))
    (set state.last-element :function-declaration))

  (fn write-struct-declaration [value]
    (emit (.. "struct " value.name))
    (if style.brace-wrapping.after-struct
        (do
          (eol)
          (emit "{")
          (eol))
        (do
          (emit " {")
          (eol)))
    (when (> (# value.members) 0)
      (set state.indent-level (+ state.indent-level 1))
      (each [_ member (ipairs value.members)]
        (emit "")
        (write-struct-member member)
        (emit ";")
        (eol))
      (set state.indent-level (- state.indent-level 1)))
    (emit "}")
    (set state.last-element :struct-declaration))

  (fn write-typedef-declaration [value]
    (emit "typedef ")
    (when (and value.const (not value.pointer))
      (emit "const "))
    (write-type-usage value.base-type)
    (local base-is-pointer (and (= value.base-type.kind :type) value.base-type.pointer))
    (write-pointer-suffix value.pointer value.const value.name base-is-pointer)
    (when value.array
      (emit (.. "[" value.array "]")))
    (set state.last-element :typedef-declaration))

  (set write-initializer-member (fn [member]
    (if (= (type member) :number)
        (emit (tostring member))
        (= (type member) :boolean)
        (emit (if member "true" "false"))
        (= (type member) :string)
        (emit (.. "\"" (quote-string member) "\""))
        (and (= (type member) :table) (is-array? member))
        (write-initializer member)
        (and (= (type member) :table) (not (is-array? member)) (= member.kind nil))
        (do
          (emit "{")
          (var first true)
          (each [k v (pairs member)]
            (when (not first)
              (emit ", "))
            (set first false)
            (emit (.. "." k " = "))
            (write-initializer-member v))
          (emit "}"))
        (and (= (type member) :table) (not (= member.kind nil)))
        (write-element member)
        (error (.. "c-builder unsupported initializer member: " (type member))))))

  (set write-initializer (fn [value]
    (if (and (= (type value) :table) (is-array? value))
        (do
          (emit "{")
          (each [i member (ipairs value)]
            (when (> i 1)
              (emit ", "))
            (write-initializer-member member))
          (emit "}"))
        (write-initializer-member value))))

  (set write-declaration (fn [value]
    (if (= value.element.kind :type)
        (emit (format-type value.element))
        (= value.element.kind :typedef)
        (write-typedef-declaration value.element)
        (= value.element.kind :struct)
        (write-struct-declaration value.element)
        (= value.element.kind :variable)
        (write-variable-declaration value.element)
        (= value.element.kind :function)
        (write-function-declaration value.element)
        (error "c-builder unsupported declaration element"))
    (when (not (= value.init-value nil))
      (emit " = ")
      (write-initializer value.init-value))))

  (fn write-string-literal [value]
    (emit (.. "\"" (quote-string value.text) "\"")))

  (fn write-function-call [value]
    (emit (.. value.name "("))
    (each [i arg (ipairs value.args)]
      (when (> i 1)
        (emit ", "))
      (write-expression arg))
    (emit ")")
    (set state.last-element :function-call))

  (fn write-function-return [value]
    (emit "return ")
    (write-expression value.value))

  (fn write-assignment [value]
    (write-expression value.lhs)
    (emit " = ")
    (write-expression value.rhs))

  (fn write-whitespace [value]
    (emit (string.rep " " value.width)))

  (fn write-line-comment [value]
    (emit (.. "//" value.text))
    (set state.last-element :comment))

  (fn write-block-comment [value]
    (local lines
      (if (= (type value.text) :string)
          [value.text]
          value.text))
    (if (> value.width 0)
        (do
          (emit (.. "/" (string.rep "*" value.width)))
          (eol)
          (each [_ comment-line (ipairs lines)]
            (emit (.. value.line-start comment-line))
            (eol))
          (emit (.. (string.rep "*" (+ value.width 1)) "/")))
        (do
          (emit "/*")
          (if (> (# lines) 1)
              (do
                (each [i comment-line (ipairs lines)]
                  (emit comment-line)
                  (if (< i (# lines))
                      (eol)
                      (emit "*/"))))
              (emit (.. (. lines 1) "*/")))))
    (set state.last-element :comment))

  (fn write-line [value]
    (each [i part (ipairs value.parts)]
      (when (> i 1)
        (if (and (= (type part) :table) (= part.kind :line-comment))
            (emit (string.rep " " (or part.adjust 1)))
            (emit " ")))
      (if (= (type part) :string)
          (emit part)
          (write-element part)))
    (eol))

  (fn write-statement [value]
    (each [i part (ipairs value.parts)]
      (when (> i 1)
        (emit " "))
      (write-expression part))
    (emit ";")
    (set state.last-element :statement))

  (fn write-start-brace []
    (if (= state.last-element :function-declaration)
        (if style.brace-wrapping.after-function
            (do
              (eol)
              (emit "{")
              (eol))
            (do
              (emit " {")
              (eol)))
        (do
          (emit "{")
          (eol))))

  (fn write-end-brace []
    (emit "}")
    (eol))

  (fn write-block [value]
    (write-start-brace)
    (if (> (# value.elements) 0)
        (do
          (set state.indent-level (+ state.indent-level 1))
          (write-sequence value)
          (set state.indent-level (- state.indent-level 1))
          (write-end-brace))
        (if (or (= style.short-functions-on-single-line ShortFunctionStyle.empty)
                (= style.short-functions-on-single-line ShortFunctionStyle.inline))
            (do
              (emit "}")
              (eol))
            (write-end-brace))))

  (fn write-include [value]
    (if value.system
        (emit (.. "#include <" value.path ">"))
        (emit (.. "#include \"" value.path "\"")))
    (set state.last-element :directive))

  (fn write-define [value]
    (if value.rhs
        (emit (.. "#" (string.rep " " value.adjust) "define " value.lhs " " value.rhs))
        (emit (.. "#" (string.rep " " value.adjust) "define " value.lhs)))
    (set state.last-element :directive))

  (fn write-ifdef [value]
    (emit (.. "#" (string.rep " " value.adjust) "ifdef " value.identifier))
    (set state.last-element :directive))

  (fn write-ifndef [value]
    (emit (.. "#" (string.rep " " value.adjust) "ifndef " value.identifier))
    (set state.last-element :directive))

  (fn write-endif [value]
    (emit (.. "#" (string.rep " " value.adjust) "endif"))
    (set state.last-element :directive))

  (fn write-extern [value]
    (emit (.. "extern \"" value.language "\""))
    (set state.last-element :directive))

  (set write-element (fn [elem]
    (when (not (= (type elem) :table))
      (error (.. "c-builder writer unsupported element type: " (type elem))))
    (if (= elem.kind :type)
        (emit (format-type elem))
        (= elem.kind :typedef)
        (emit elem.name)
        (= elem.kind :struct)
        (emit (.. "struct " elem.name))
        (= elem.kind :variable)
        (write-variable-usage elem)
        (= elem.kind :function)
        (emit elem.name)
        (= elem.kind :declaration)
        (write-declaration elem)
        (= elem.kind :assignment)
        (write-assignment elem)
        (= elem.kind :string-literal)
        (write-string-literal elem)
        (= elem.kind :function-return)
        (write-function-return elem)
        (= elem.kind :function-call)
        (write-function-call elem)
        (= elem.kind :blank)
        (do
          (emit "")
          (eol))
        (= elem.kind :whitespace)
        (write-whitespace elem)
        (= elem.kind :line-comment)
        (write-line-comment elem)
        (= elem.kind :block-comment)
        (write-block-comment elem)
        (= elem.kind :block)
        (write-block elem)
        (= elem.kind :statement)
        (write-statement elem)
        (= elem.kind :line)
        (write-line elem)
        (= elem.kind :include-directive)
        (write-include elem)
        (= elem.kind :define-directive)
        (write-define elem)
        (= elem.kind :ifdef-directive)
        (write-ifdef elem)
        (= elem.kind :ifndef-directive)
        (write-ifndef elem)
        (= elem.kind :endif-directive)
        (write-endif elem)
        (= elem.kind :extern)
        (write-extern elem)
        (error (.. "c-builder writer unsupported kind: " (or elem.kind "<none>"))))))

  (set write-sequence (fn [seq]
    (each [_ elem (ipairs seq.elements)]
      (if (is-array? elem)
          (do
            (local line-elem (line elem))
            (write-line line-elem))
          (= elem.kind :statement)
          (do
            (write-statement elem)
            (eol))
          (= elem.kind :line-comment)
          (do
            (write-line-comment elem)
            (eol))
          (= elem.kind :block)
          (write-block elem)
          (= elem.kind :line)
          (write-line elem)
          (do
            (write-element elem)
            (when (or (= elem.kind :include-directive)
                      (= elem.kind :define-directive)
                      (= elem.kind :ifdef-directive)
                      (= elem.kind :ifndef-directive)
                      (= elem.kind :endif-directive))
              (eol)))))))

  (local self
    {:style style
     :write-str (fn [self seq]
                  (when (not (and (= (type seq) :table)
                                  (or (= seq.kind :sequence) (= seq.kind :block))))
                    (error "c-builder writer.write-str expects sequence or block"))
                  (set state.chunks [])
                  (set state.line-start true)
                  (set state.indent-level 0)
                  (set state.last-element :none)
                  (write-sequence seq)
                  (table.concat state.chunks ""))
     :write-str-elem (fn [self elem opts]
                       (local options (or opts {}))
                       (set state.chunks [])
                       (set state.line-start true)
                       (set state.indent-level 0)
                       (set state.last-element :none)
                       (write-element elem)
                       (local out (table.concat state.chunks ""))
                       (if (or (= options.trim-end nil) options.trim-end)
                           (string.gsub out "\n$" "")
                           out))
     :write-file (fn [self seq path]
                   (assert-string "writer.write-file path" path)
                   (fs.write-file path (self:write-str seq))
                   path)})
  self)

(fn Factory []
  {:blank blank
   :line line
   :whitespace whitespace
   :line-comment line-comment
   :block-comment block-comment
   :sequence sequence
   :block block
   :include include-file
   :sysinclude sysinclude
   :ifdef ifdef
   :ifndef ifndef
   :endif endif
   :define define
   :extern extern
   :function function
   :type type*
   :struct-member struct-member
   :struct struct*
   :variable variable
   :typedef typedef
   :statement statement
   :assignment assignment
   :str-literal str-literal
   :func-call func-call
   :func-return func-return
   :declaration declaration})

{:BraceStyle BraceStyle
 :PointerAlignment PointerAlignment
 :ShortFunctionStyle ShortFunctionStyle
 :Style Style
 :Writer Writer
 :Factory Factory}
