#include "lua_gccjit.h"

#if defined(__linux__)

#include <libgccjit.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>

#include <memory>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

struct GccJitContext;
struct GccJitResult;
struct GccJitObject;
struct GccJitLocation;
struct GccJitType;
struct GccJitField;
struct GccJitStruct;
struct GccJitFunction;
struct GccJitBlock;
struct GccJitRValue;
struct GccJitLValue;
struct GccJitParam;
struct GccJitCase;
struct GccJitExtendedAsm;
struct GccJitTimer;
struct GccJitBorrowedTimer;

struct DumpCapture
{
    std::string name;
    char* data { nullptr };
};

struct GccJitContext
{
    gcc_jit_context* ptr { nullptr };
    bool owns_ptr { true };
    std::vector<std::unique_ptr<DumpCapture>> dumps;

    void require_alive() const
    {
        if (!ptr) {
            throw sol::error("gccjit context is released");
        }
    }

    void release()
    {
        if (ptr) {
            // Detach logfile from context first. Do not fclose here: libgccjit may
            // still own/close the FILE*, and double-close is undefined.
            gcc_jit_context_set_logfile(ptr, nullptr, 0, 0);
            for (const auto& item : dumps) {
                if (item && item->data) {
                    free(item->data);
                    item->data = nullptr;
                }
            }
            if (owns_ptr) {
                gcc_jit_context_release(ptr);
            }
            ptr = nullptr;
            owns_ptr = false;
        }
    }
};

struct GccJitResult
{
    gcc_jit_result* ptr { nullptr };
    bool owns_ptr { true };

    void require_alive() const
    {
        if (!ptr) {
            throw sol::error("gccjit result is released");
        }
    }

    void release()
    {
        if (ptr) {
            if (owns_ptr) {
                gcc_jit_result_release(ptr);
            }
            ptr = nullptr;
            owns_ptr = false;
        }
    }
};

struct GccJitTimer
{
    gcc_jit_timer* ptr { nullptr };
    bool owns_ptr { true };

    void require_alive() const
    {
        if (!ptr) {
            throw sol::error("gccjit timer is released");
        }
    }

    void release()
    {
        if (ptr) {
            if (owns_ptr) {
                gcc_jit_timer_release(ptr);
            }
            ptr = nullptr;
            owns_ptr = false;
        }
    }
};

struct GccJitBorrowedTimer
{
    gcc_jit_timer* ptr { nullptr };

    void require_alive() const
    {
        if (!ptr) {
            throw sol::error("gccjit borrowed timer is null");
        }
    }
};

struct GccJitObject { gcc_jit_object* ptr { nullptr }; };
struct GccJitLocation { gcc_jit_location* ptr { nullptr }; };
struct GccJitType { gcc_jit_type* ptr { nullptr }; };
struct GccJitField { gcc_jit_field* ptr { nullptr }; };
struct GccJitStruct { gcc_jit_struct* ptr { nullptr }; };
struct GccJitFunction { gcc_jit_function* ptr { nullptr }; };
struct GccJitBlock { gcc_jit_block* ptr { nullptr }; };
struct GccJitRValue { gcc_jit_rvalue* ptr { nullptr }; };
struct GccJitLValue { gcc_jit_lvalue* ptr { nullptr }; };
struct GccJitParam { gcc_jit_param* ptr { nullptr }; };
struct GccJitCase { gcc_jit_case* ptr { nullptr }; };
struct GccJitExtendedAsm { gcc_jit_extended_asm* ptr { nullptr }; };

void require_not_null(const void* ptr, const char* what)
{
    if (!ptr) {
        throw sol::error(std::string("gccjit returned null: ") + what);
    }
}

void throw_with_context_error(gcc_jit_context* ctxt, const char* op)
{
    const char* err = gcc_jit_context_get_last_error(ctxt);
    if (err) {
        throw sol::error(std::string("gccjit error during ") + op + ": " + err);
    }
}

void check_context(gcc_jit_context* ctxt, const char* op)
{
    if (!ctxt) {
        throw sol::error(std::string("gccjit null context in ") + op);
    }
    throw_with_context_error(ctxt, op);
}

template <typename T>
T expect_object(sol::object obj, const char* name)
{
    if (!obj.is<T>()) {
        throw sol::error(std::string("expected ") + name);
    }
    return obj.as<T>();
}

gcc_jit_location* optional_location(const sol::optional<GccJitLocation&>& loc)
{
    if (loc) {
        return loc->ptr;
    }
    return nullptr;
}

std::vector<gcc_jit_field*> table_to_fields(sol::table fields)
{
    std::size_t n = fields.size();
    std::vector<gcc_jit_field*> out;
    out.reserve(n);
    for (std::size_t i = 1; i <= n; ++i) {
        sol::object obj = fields[i];
        GccJitField field = expect_object<GccJitField>(obj, "gccjit.Field");
        require_not_null(field.ptr, "field");
        out.push_back(field.ptr);
    }
    return out;
}

std::vector<gcc_jit_param*> table_to_params(sol::table params)
{
    std::size_t n = params.size();
    std::vector<gcc_jit_param*> out;
    out.reserve(n);
    for (std::size_t i = 1; i <= n; ++i) {
        sol::object obj = params[i];
        GccJitParam param = expect_object<GccJitParam>(obj, "gccjit.Param");
        require_not_null(param.ptr, "param");
        out.push_back(param.ptr);
    }
    return out;
}

std::vector<gcc_jit_type*> table_to_types(sol::table types)
{
    std::size_t n = types.size();
    std::vector<gcc_jit_type*> out;
    out.reserve(n);
    for (std::size_t i = 1; i <= n; ++i) {
        sol::object obj = types[i];
        GccJitType type = expect_object<GccJitType>(obj, "gccjit.Type");
        require_not_null(type.ptr, "type");
        out.push_back(type.ptr);
    }
    return out;
}

std::vector<gcc_jit_rvalue*> table_to_rvalues(sol::table values)
{
    std::size_t n = values.size();
    std::vector<gcc_jit_rvalue*> out;
    out.reserve(n);
    for (std::size_t i = 1; i <= n; ++i) {
        sol::object obj = values[i];
        GccJitRValue value = expect_object<GccJitRValue>(obj, "gccjit.RValue");
        require_not_null(value.ptr, "rvalue");
        out.push_back(value.ptr);
    }
    return out;
}

std::vector<gcc_jit_case*> table_to_cases(sol::table cases)
{
    std::size_t n = cases.size();
    std::vector<gcc_jit_case*> out;
    out.reserve(n);
    for (std::size_t i = 1; i <= n; ++i) {
        sol::object obj = cases[i];
        GccJitCase c = expect_object<GccJitCase>(obj, "gccjit.Case");
        require_not_null(c.ptr, "case");
        out.push_back(c.ptr);
    }
    return out;
}

std::vector<gcc_jit_block*> table_to_blocks(sol::table blocks)
{
    std::size_t n = blocks.size();
    std::vector<gcc_jit_block*> out;
    out.reserve(n);
    for (std::size_t i = 1; i <= n; ++i) {
        sol::object obj = blocks[i];
        GccJitBlock b = expect_object<GccJitBlock>(obj, "gccjit.Block");
        require_not_null(b.ptr, "block");
        out.push_back(b.ptr);
    }
    return out;
}

std::vector<int> table_to_ints(sol::table args)
{
    std::size_t n = args.size();
    std::vector<int> out;
    out.reserve(n);
    for (std::size_t i = 1; i <= n; ++i) {
        sol::object obj = args[i];
        if (obj.is<int>()) {
            out.push_back(obj.as<int>());
        } else if (obj.is<int64_t>()) {
            out.push_back(static_cast<int>(obj.as<int64_t>()));
        } else {
            throw sol::error("expected integer arguments table");
        }
    }
    return out;
}

std::vector<double> table_to_doubles(sol::table args)
{
    std::size_t n = args.size();
    std::vector<double> out;
    out.reserve(n);
    for (std::size_t i = 1; i <= n; ++i) {
        sol::object obj = args[i];
        if (obj.is<double>()) {
            out.push_back(obj.as<double>());
        } else if (obj.is<int>()) {
            out.push_back(static_cast<double>(obj.as<int>()));
        } else if (obj.is<int64_t>()) {
            out.push_back(static_cast<double>(obj.as<int64_t>()));
        } else {
            throw sol::error("expected numeric arguments table");
        }
    }
    return out;
}

std::vector<uintptr_t> table_to_words(sol::table args)
{
    std::size_t n = args.size();
    std::vector<uintptr_t> out;
    out.reserve(n);
    for (std::size_t i = 1; i <= n; ++i) {
        sol::object obj = args[i];
        if (obj.is<int>()) {
            out.push_back(static_cast<uintptr_t>(obj.as<int>()));
        } else if (obj.is<int64_t>()) {
            out.push_back(static_cast<uintptr_t>(obj.as<int64_t>()));
        } else if (obj.is<uint64_t>()) {
            out.push_back(static_cast<uintptr_t>(obj.as<uint64_t>()));
        } else {
            throw sol::error("expected integer/pointer arguments table");
        }
    }
    return out;
}

int call_i32_impl(void* code, const std::vector<int>& args)
{
    switch (args.size()) {
        case 0: return (reinterpret_cast<int (*)()>(code))();
        case 1: return (reinterpret_cast<int (*)(int)>(code))(args[0]);
        case 2: return (reinterpret_cast<int (*)(int, int)>(code))(args[0], args[1]);
        case 3: return (reinterpret_cast<int (*)(int, int, int)>(code))(args[0], args[1], args[2]);
        case 4: return (reinterpret_cast<int (*)(int, int, int, int)>(code))(args[0], args[1], args[2], args[3]);
        case 5: return (reinterpret_cast<int (*)(int, int, int, int, int)>(code))(args[0], args[1], args[2], args[3], args[4]);
        case 6:
            return (reinterpret_cast<int (*)(int, int, int, int, int, int)>(code))
                (args[0], args[1], args[2], args[3], args[4], args[5]);
        default:
            throw sol::error("call-i32 supports up to 6 arguments");
    }
}

int64_t call_i64_impl(void* code, const std::vector<int>& args)
{
    switch (args.size()) {
        case 0: return (reinterpret_cast<int64_t (*)()>(code))();
        case 1: return (reinterpret_cast<int64_t (*)(int)>(code))(args[0]);
        case 2: return (reinterpret_cast<int64_t (*)(int, int)>(code))(args[0], args[1]);
        case 3: return (reinterpret_cast<int64_t (*)(int, int, int)>(code))(args[0], args[1], args[2]);
        case 4: return (reinterpret_cast<int64_t (*)(int, int, int, int)>(code))(args[0], args[1], args[2], args[3]);
        default:
            throw sol::error("call-i64 supports up to 4 arguments");
    }
}

double call_double_impl(void* code, const std::vector<double>& args)
{
    switch (args.size()) {
        case 0: return (reinterpret_cast<double (*)()>(code))();
        case 1: return (reinterpret_cast<double (*)(double)>(code))(args[0]);
        case 2: return (reinterpret_cast<double (*)(double, double)>(code))(args[0], args[1]);
        case 3: return (reinterpret_cast<double (*)(double, double, double)>(code))(args[0], args[1], args[2]);
        case 4: return (reinterpret_cast<double (*)(double, double, double, double)>(code))(args[0], args[1], args[2], args[3]);
        case 5: return (reinterpret_cast<double (*)(double, double, double, double, double)>(code))(args[0], args[1], args[2], args[3], args[4]);
        case 6: return (reinterpret_cast<double (*)(double, double, double, double, double, double)>(code))(args[0], args[1], args[2], args[3], args[4], args[5]);
        case 7: return (reinterpret_cast<double (*)(double, double, double, double, double, double, double)>(code))(args[0], args[1], args[2], args[3], args[4], args[5], args[6]);
        case 8:
            return (reinterpret_cast<double (*)(double, double, double, double, double, double, double, double)>(code))
                (args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]);
        default:
            throw sol::error("call-double supports up to 8 arguments");
    }
}

void call_void_impl(void* code, const std::vector<int>& args)
{
    switch (args.size()) {
        case 0:
            (reinterpret_cast<void (*)()>(code))();
            return;
        case 1:
            (reinterpret_cast<void (*)(int)>(code))(args[0]);
            return;
        case 2:
            (reinterpret_cast<void (*)(int, int)>(code))(args[0], args[1]);
            return;
        default:
            throw sol::error("call-void supports up to 2 integer arguments");
    }
}

uintptr_t call_word_impl(void* code, const std::vector<uintptr_t>& args)
{
    switch (args.size()) {
        case 0: return (reinterpret_cast<uintptr_t (*)()>(code))();
        case 1: return (reinterpret_cast<uintptr_t (*)(uintptr_t)>(code))(args[0]);
        case 2: return (reinterpret_cast<uintptr_t (*)(uintptr_t, uintptr_t)>(code))(args[0], args[1]);
        case 3: return (reinterpret_cast<uintptr_t (*)(uintptr_t, uintptr_t, uintptr_t)>(code))(args[0], args[1], args[2]);
        case 4: return (reinterpret_cast<uintptr_t (*)(uintptr_t, uintptr_t, uintptr_t, uintptr_t)>(code))(args[0], args[1], args[2], args[3]);
        case 5:
            return (reinterpret_cast<uintptr_t (*)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t)>(code))
                (args[0], args[1], args[2], args[3], args[4]);
        case 6:
            return (reinterpret_cast<uintptr_t (*)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t)>(code))
                (args[0], args[1], args[2], args[3], args[4], args[5]);
        case 7:
            return (reinterpret_cast<uintptr_t (*)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t)>(code))
                (args[0], args[1], args[2], args[3], args[4], args[5], args[6]);
        case 8:
            return (reinterpret_cast<uintptr_t (*)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t)>(code))
                (args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]);
        default:
            throw sol::error("call-word supports up to 8 word arguments");
    }
}

void call_void_word_impl(void* code, const std::vector<uintptr_t>& args)
{
    switch (args.size()) {
        case 0:
            (reinterpret_cast<void (*)()>(code))();
            return;
        case 1:
            (reinterpret_cast<void (*)(uintptr_t)>(code))(args[0]);
            return;
        case 2:
            (reinterpret_cast<void (*)(uintptr_t, uintptr_t)>(code))(args[0], args[1]);
            return;
        case 3:
            (reinterpret_cast<void (*)(uintptr_t, uintptr_t, uintptr_t)>(code))(args[0], args[1], args[2]);
            return;
        case 4:
            (reinterpret_cast<void (*)(uintptr_t, uintptr_t, uintptr_t, uintptr_t)>(code))(args[0], args[1], args[2], args[3]);
            return;
        default:
            throw sol::error("call-void-word supports up to 4 word arguments");
    }
}

sol::table create_gccjit_table(sol::state_view lua)
{
    sol::table module = lua.create_table();

    module.new_usertype<GccJitContext>("ContextRef",
        sol::no_constructor,
        "release", &GccJitContext::release,
        "drop", &GccJitContext::release,
        "set-str-option", [](GccJitContext& self, int option, const std::string& value) {
            self.require_alive();
            gcc_jit_context_set_str_option(self.ptr, static_cast<gcc_jit_str_option>(option), value.c_str());
            check_context(self.ptr, "set-str-option");
        },
        "set-int-option", [](GccJitContext& self, int option, int value) {
            self.require_alive();
            gcc_jit_context_set_int_option(self.ptr, static_cast<gcc_jit_int_option>(option), value);
            check_context(self.ptr, "set-int-option");
        },
        "set-bool-option", [](GccJitContext& self, int option, bool value) {
            self.require_alive();
            gcc_jit_context_set_bool_option(self.ptr, static_cast<gcc_jit_bool_option>(option), value ? 1 : 0);
            check_context(self.ptr, "set-bool-option");
        },
        "set-bool-allow-unreachable-blocks", [](GccJitContext& self, bool value) {
            self.require_alive();
            gcc_jit_context_set_bool_allow_unreachable_blocks(self.ptr, value ? 1 : 0);
            check_context(self.ptr, "set-bool-allow-unreachable-blocks");
        },
        "set-bool-use-external-driver", [](GccJitContext& self, bool value) {
            self.require_alive();
            gcc_jit_context_set_bool_use_external_driver(self.ptr, value ? 1 : 0);
            check_context(self.ptr, "set-bool-use-external-driver");
        },
        "add-command-line-option", [](GccJitContext& self, const std::string& option) {
            self.require_alive();
            gcc_jit_context_add_command_line_option(self.ptr, option.c_str());
            check_context(self.ptr, "add-command-line-option");
        },
        "add-driver-option", [](GccJitContext& self, const std::string& option) {
            self.require_alive();
            gcc_jit_context_add_driver_option(self.ptr, option.c_str());
            check_context(self.ptr, "add-driver-option");
        },
        "compile", [](GccJitContext& self) {
            self.require_alive();
            gcc_jit_result* result = gcc_jit_context_compile(self.ptr);
            if (!result) {
                throw_with_context_error(self.ptr, "compile");
                throw sol::error("gccjit compile failed");
            }
            check_context(self.ptr, "compile");
            GccJitResult out;
            out.ptr = result;
            out.owns_ptr = true;
            return out;
        },
        "compile-to-file", [](GccJitContext& self, int output_kind, const std::string& output_path) {
            self.require_alive();
            gcc_jit_context_compile_to_file(self.ptr,
                static_cast<gcc_jit_output_kind>(output_kind),
                output_path.c_str());
            check_context(self.ptr, "compile-to-file");
        },
        "dump-to-file", [](GccJitContext& self, const std::string& path, sol::optional<bool> update_locations) {
            self.require_alive();
            gcc_jit_context_dump_to_file(self.ptr, path.c_str(), update_locations.value_or(false) ? 1 : 0);
            check_context(self.ptr, "dump-to-file");
        },
        "set-logfile", [](GccJitContext& self, const std::string& path, sol::optional<int> flags, sol::optional<int> verbosity) {
            self.require_alive();
            gcc_jit_context_set_logfile(self.ptr, nullptr, 0, 0);
            FILE* f = fopen(path.c_str(), "w");
            if (!f) {
                throw sol::error("failed to open logfile path");
            }
            gcc_jit_context_set_logfile(self.ptr, f, flags.value_or(0), verbosity.value_or(0));
            check_context(self.ptr, "set-logfile");
        },
        "clear-logfile", [](GccJitContext& self) {
            self.require_alive();
            gcc_jit_context_set_logfile(self.ptr, nullptr, 0, 0);
            check_context(self.ptr, "clear-logfile");
        },
        "get-first-error", [lua](GccJitContext& self) -> sol::object {
            self.require_alive();
            const char* err = gcc_jit_context_get_first_error(self.ptr);
            if (!err) {
                return sol::make_object(lua, sol::nil);
            }
            return sol::make_object(lua, std::string(err));
        },
        "get-last-error", [lua](GccJitContext& self) -> sol::object {
            self.require_alive();
            const char* err = gcc_jit_context_get_last_error(self.ptr);
            if (!err) {
                return sol::make_object(lua, sol::nil);
            }
            return sol::make_object(lua, std::string(err));
        },
        "new-location", [](GccJitContext& self, const std::string& filename, int line, int column) {
            self.require_alive();
            GccJitLocation out;
            out.ptr = gcc_jit_context_new_location(self.ptr, filename.c_str(), line, column);
            require_not_null(out.ptr, "new-location");
            check_context(self.ptr, "new-location");
            return out;
        },
        "get-type", [](GccJitContext& self, int type_kind) {
            self.require_alive();
            GccJitType out;
            out.ptr = gcc_jit_context_get_type(self.ptr, static_cast<gcc_jit_types>(type_kind));
            require_not_null(out.ptr, "get-type");
            check_context(self.ptr, "get-type");
            return out;
        },
        "get-int-type", [](GccJitContext& self, int num_bytes, bool is_signed) {
            self.require_alive();
            GccJitType out;
            out.ptr = gcc_jit_context_get_int_type(self.ptr, num_bytes, is_signed ? 1 : 0);
            require_not_null(out.ptr, "get-int-type");
            check_context(self.ptr, "get-int-type");
            return out;
        },
        "new-array-type", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, GccJitType type, int num_elements) {
            self.require_alive();
            require_not_null(type.ptr, "element-type");
            GccJitType out;
            out.ptr = gcc_jit_context_new_array_type(self.ptr, optional_location(loc), type.ptr, num_elements);
            require_not_null(out.ptr, "new-array-type");
            check_context(self.ptr, "new-array-type");
            return out;
        },
        "new-field", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, GccJitType type, const std::string& name) {
            self.require_alive();
            require_not_null(type.ptr, "field-type");
            GccJitField out;
            out.ptr = gcc_jit_context_new_field(self.ptr, optional_location(loc), type.ptr, name.c_str());
            require_not_null(out.ptr, "new-field");
            check_context(self.ptr, "new-field");
            return out;
        },
        "new-bitfield", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, GccJitType type, int width,
                            const std::string& name) {
            self.require_alive();
            require_not_null(type.ptr, "bitfield-type");
            GccJitField out;
            out.ptr = gcc_jit_context_new_bitfield(self.ptr, optional_location(loc), type.ptr, width, name.c_str());
            require_not_null(out.ptr, "new-bitfield");
            check_context(self.ptr, "new-bitfield");
            return out;
        },
        "new-struct-type", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, const std::string& name,
                               sol::table fields) {
            self.require_alive();
            auto field_ptrs = table_to_fields(fields);
            GccJitStruct out;
            out.ptr = gcc_jit_context_new_struct_type(self.ptr, optional_location(loc), name.c_str(),
                static_cast<int>(field_ptrs.size()), field_ptrs.data());
            require_not_null(out.ptr, "new-struct-type");
            check_context(self.ptr, "new-struct-type");
            return out;
        },
        "new-opaque-struct", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, const std::string& name) {
            self.require_alive();
            GccJitStruct out;
            out.ptr = gcc_jit_context_new_opaque_struct(self.ptr, optional_location(loc), name.c_str());
            require_not_null(out.ptr, "new-opaque-struct");
            check_context(self.ptr, "new-opaque-struct");
            return out;
        },
        "new-union-type", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, const std::string& name,
                              sol::table fields) {
            self.require_alive();
            auto field_ptrs = table_to_fields(fields);
            GccJitType out;
            out.ptr = gcc_jit_context_new_union_type(self.ptr, optional_location(loc), name.c_str(),
                static_cast<int>(field_ptrs.size()), field_ptrs.data());
            require_not_null(out.ptr, "new-union-type");
            check_context(self.ptr, "new-union-type");
            return out;
        },
        "new-function-ptr-type", [](GccJitContext& self, sol::optional<GccJitLocation&> loc,
                                     GccJitType return_type, sol::table param_types, sol::optional<bool> is_variadic) {
            self.require_alive();
            require_not_null(return_type.ptr, "return-type");
            auto param_type_ptrs = table_to_types(param_types);
            GccJitType out;
            out.ptr = gcc_jit_context_new_function_ptr_type(self.ptr, optional_location(loc), return_type.ptr,
                static_cast<int>(param_type_ptrs.size()), param_type_ptrs.data(), is_variadic.value_or(false) ? 1 : 0);
            require_not_null(out.ptr, "new-function-ptr-type");
            check_context(self.ptr, "new-function-ptr-type");
            return out;
        },
        "new-param", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, GccJitType type,
                         const std::string& name) {
            self.require_alive();
            require_not_null(type.ptr, "param-type");
            GccJitParam out;
            out.ptr = gcc_jit_context_new_param(self.ptr, optional_location(loc), type.ptr, name.c_str());
            require_not_null(out.ptr, "new-param");
            check_context(self.ptr, "new-param");
            return out;
        },
        "new-function", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, int kind, GccJitType return_type,
                            const std::string& name, sol::table params, sol::optional<bool> is_variadic) {
            self.require_alive();
            require_not_null(return_type.ptr, "return-type");
            auto param_ptrs = table_to_params(params);
            GccJitFunction out;
            out.ptr = gcc_jit_context_new_function(self.ptr, optional_location(loc),
                static_cast<gcc_jit_function_kind>(kind), return_type.ptr, name.c_str(),
                static_cast<int>(param_ptrs.size()), param_ptrs.data(), is_variadic.value_or(false) ? 1 : 0);
            require_not_null(out.ptr, "new-function");
            check_context(self.ptr, "new-function");
            return out;
        },
        "get-builtin-function", [](GccJitContext& self, const std::string& name) {
            self.require_alive();
            GccJitFunction out;
            out.ptr = gcc_jit_context_get_builtin_function(self.ptr, name.c_str());
            require_not_null(out.ptr, "get-builtin-function");
            check_context(self.ptr, "get-builtin-function");
            return out;
        },
        "new-global", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, int kind, GccJitType type,
                          const std::string& name) {
            self.require_alive();
            require_not_null(type.ptr, "global-type");
            GccJitLValue out;
            out.ptr = gcc_jit_context_new_global(self.ptr, optional_location(loc),
                static_cast<gcc_jit_global_kind>(kind), type.ptr, name.c_str());
            require_not_null(out.ptr, "new-global");
            check_context(self.ptr, "new-global");
            return out;
        },
        "new-rvalue-from-int", [](GccJitContext& self, GccJitType type, int value) {
            self.require_alive();
            require_not_null(type.ptr, "numeric-type");
            GccJitRValue out;
            out.ptr = gcc_jit_context_new_rvalue_from_int(self.ptr, type.ptr, value);
            require_not_null(out.ptr, "new-rvalue-from-int");
            check_context(self.ptr, "new-rvalue-from-int");
            return out;
        },
        "new-rvalue-from-long", [](GccJitContext& self, GccJitType type, int64_t value) {
            self.require_alive();
            require_not_null(type.ptr, "numeric-type");
            GccJitRValue out;
            out.ptr = gcc_jit_context_new_rvalue_from_long(self.ptr, type.ptr, static_cast<long>(value));
            require_not_null(out.ptr, "new-rvalue-from-long");
            check_context(self.ptr, "new-rvalue-from-long");
            return out;
        },
        "zero", [](GccJitContext& self, GccJitType type) {
            self.require_alive();
            require_not_null(type.ptr, "numeric-type");
            GccJitRValue out;
            out.ptr = gcc_jit_context_zero(self.ptr, type.ptr);
            require_not_null(out.ptr, "zero");
            check_context(self.ptr, "zero");
            return out;
        },
        "one", [](GccJitContext& self, GccJitType type) {
            self.require_alive();
            require_not_null(type.ptr, "numeric-type");
            GccJitRValue out;
            out.ptr = gcc_jit_context_one(self.ptr, type.ptr);
            require_not_null(out.ptr, "one");
            check_context(self.ptr, "one");
            return out;
        },
        "new-rvalue-from-double", [](GccJitContext& self, GccJitType type, double value) {
            self.require_alive();
            require_not_null(type.ptr, "numeric-type");
            GccJitRValue out;
            out.ptr = gcc_jit_context_new_rvalue_from_double(self.ptr, type.ptr, value);
            require_not_null(out.ptr, "new-rvalue-from-double");
            check_context(self.ptr, "new-rvalue-from-double");
            return out;
        },
        "new-rvalue-from-ptr", [](GccJitContext& self, GccJitType type, uintptr_t value) {
            self.require_alive();
            require_not_null(type.ptr, "pointer-type");
            GccJitRValue out;
            out.ptr = gcc_jit_context_new_rvalue_from_ptr(self.ptr, type.ptr, reinterpret_cast<void*>(value));
            require_not_null(out.ptr, "new-rvalue-from-ptr");
            check_context(self.ptr, "new-rvalue-from-ptr");
            return out;
        },
        "null", [](GccJitContext& self, GccJitType type) {
            self.require_alive();
            require_not_null(type.ptr, "pointer-type");
            GccJitRValue out;
            out.ptr = gcc_jit_context_null(self.ptr, type.ptr);
            require_not_null(out.ptr, "null");
            check_context(self.ptr, "null");
            return out;
        },
        "new-string-literal", [](GccJitContext& self, const std::string& value) {
            self.require_alive();
            GccJitRValue out;
            out.ptr = gcc_jit_context_new_string_literal(self.ptr, value.c_str());
            require_not_null(out.ptr, "new-string-literal");
            check_context(self.ptr, "new-string-literal");
            return out;
        },
        "new-unary-op", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, int op,
                            GccJitType result_type, GccJitRValue value) {
            self.require_alive();
            require_not_null(result_type.ptr, "result-type");
            require_not_null(value.ptr, "rvalue");
            GccJitRValue out;
            out.ptr = gcc_jit_context_new_unary_op(self.ptr, optional_location(loc),
                static_cast<gcc_jit_unary_op>(op), result_type.ptr, value.ptr);
            require_not_null(out.ptr, "new-unary-op");
            check_context(self.ptr, "new-unary-op");
            return out;
        },
        "new-binary-op", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, int op,
                             GccJitType result_type, GccJitRValue a, GccJitRValue b) {
            self.require_alive();
            require_not_null(result_type.ptr, "result-type");
            require_not_null(a.ptr, "rvalue-a");
            require_not_null(b.ptr, "rvalue-b");
            GccJitRValue out;
            out.ptr = gcc_jit_context_new_binary_op(self.ptr, optional_location(loc),
                static_cast<gcc_jit_binary_op>(op), result_type.ptr, a.ptr, b.ptr);
            require_not_null(out.ptr, "new-binary-op");
            check_context(self.ptr, "new-binary-op");
            return out;
        },
        "new-comparison", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, int op,
                              GccJitRValue a, GccJitRValue b) {
            self.require_alive();
            require_not_null(a.ptr, "rvalue-a");
            require_not_null(b.ptr, "rvalue-b");
            GccJitRValue out;
            out.ptr = gcc_jit_context_new_comparison(self.ptr, optional_location(loc),
                static_cast<gcc_jit_comparison>(op), a.ptr, b.ptr);
            require_not_null(out.ptr, "new-comparison");
            check_context(self.ptr, "new-comparison");
            return out;
        },
        "new-call", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, GccJitFunction func,
                        sol::table args) {
            self.require_alive();
            require_not_null(func.ptr, "function");
            auto arg_ptrs = table_to_rvalues(args);
            GccJitRValue out;
            out.ptr = gcc_jit_context_new_call(self.ptr, optional_location(loc), func.ptr,
                static_cast<int>(arg_ptrs.size()), arg_ptrs.data());
            require_not_null(out.ptr, "new-call");
            check_context(self.ptr, "new-call");
            return out;
        },
        "new-call-through-ptr", [](GccJitContext& self, sol::optional<GccJitLocation&> loc,
                                    GccJitRValue fn_ptr, sol::table args) {
            self.require_alive();
            require_not_null(fn_ptr.ptr, "fn-ptr");
            auto arg_ptrs = table_to_rvalues(args);
            GccJitRValue out;
            out.ptr = gcc_jit_context_new_call_through_ptr(self.ptr, optional_location(loc), fn_ptr.ptr,
                static_cast<int>(arg_ptrs.size()), arg_ptrs.data());
            require_not_null(out.ptr, "new-call-through-ptr");
            check_context(self.ptr, "new-call-through-ptr");
            return out;
        },
        "new-cast", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, GccJitRValue value,
                        GccJitType type) {
            self.require_alive();
            require_not_null(value.ptr, "rvalue");
            require_not_null(type.ptr, "type");
            GccJitRValue out;
            out.ptr = gcc_jit_context_new_cast(self.ptr, optional_location(loc), value.ptr, type.ptr);
            require_not_null(out.ptr, "new-cast");
            check_context(self.ptr, "new-cast");
            return out;
        },
        "new-array-access", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, GccJitRValue ptr,
                                GccJitRValue index) {
            self.require_alive();
            require_not_null(ptr.ptr, "ptr");
            require_not_null(index.ptr, "index");
            GccJitLValue out;
            out.ptr = gcc_jit_context_new_array_access(self.ptr, optional_location(loc), ptr.ptr, index.ptr);
            require_not_null(out.ptr, "new-array-access");
            check_context(self.ptr, "new-array-access");
            return out;
        },
        "new-case", [](GccJitContext& self, GccJitRValue min_value, GccJitRValue max_value,
                        GccJitBlock dest_block) {
            self.require_alive();
            require_not_null(min_value.ptr, "case-min");
            require_not_null(max_value.ptr, "case-max");
            require_not_null(dest_block.ptr, "case-block");
            GccJitCase out;
            out.ptr = gcc_jit_context_new_case(self.ptr, min_value.ptr, max_value.ptr, dest_block.ptr);
            require_not_null(out.ptr, "new-case");
            check_context(self.ptr, "new-case");
            return out;
        },
        "new-child-context", [](GccJitContext& self) {
            self.require_alive();
            GccJitContext out;
            out.ptr = gcc_jit_context_new_child_context(self.ptr);
            out.owns_ptr = true;
            require_not_null(out.ptr, "new-child-context");
            check_context(self.ptr, "new-child-context");
            return out;
        },
        "dump-reproducer-to-file", [](GccJitContext& self, const std::string& path) {
            self.require_alive();
            gcc_jit_context_dump_reproducer_to_file(self.ptr, path.c_str());
            check_context(self.ptr, "dump-reproducer-to-file");
        },
        "enable-dump", [](GccJitContext& self, const std::string& name) {
            self.require_alive();
            auto capture = std::make_unique<DumpCapture>();
            capture->name = name;
            capture->data = nullptr;
            DumpCapture* raw = capture.get();
            self.dumps.push_back(std::move(capture));
            gcc_jit_context_enable_dump(self.ptr, raw->name.c_str(), &raw->data);
            check_context(self.ptr, "enable-dump");
        },
        "take-dump", [lua](GccJitContext& self, const std::string& name) -> sol::object {
            self.require_alive();
            for (const auto& item : self.dumps) {
                if (item && item->name == name) {
                    if (!item->data) {
                        return sol::make_object(lua, sol::nil);
                    }
                    std::string out(item->data);
                    free(item->data);
                    item->data = nullptr;
                    return sol::make_object(lua, out);
                }
            }
            throw sol::error("unknown dump name");
        },
        "set-timer", [](GccJitContext& self, GccJitTimer& timer) {
            self.require_alive();
            timer.require_alive();
            gcc_jit_context_set_timer(self.ptr, timer.ptr);
            check_context(self.ptr, "set-timer");
        },
        "get-timer", [lua](GccJitContext& self) -> sol::object {
            self.require_alive();
            gcc_jit_timer* timer = gcc_jit_context_get_timer(self.ptr);
            if (!timer) {
                return sol::make_object(lua, sol::nil);
            }
            GccJitBorrowedTimer out;
            out.ptr = timer;
            return sol::make_object(lua, out);
        },
        "new-rvalue-from-vector", [](GccJitContext& self, sol::optional<GccJitLocation&> loc,
                                      GccJitType vec_type, sol::table elements) {
            self.require_alive();
            require_not_null(vec_type.ptr, "vector-type");
            auto values = table_to_rvalues(elements);
            GccJitRValue out;
            out.ptr = gcc_jit_context_new_rvalue_from_vector(self.ptr, optional_location(loc), vec_type.ptr,
                values.size(), values.data());
            require_not_null(out.ptr, "new-rvalue-from-vector");
            check_context(self.ptr, "new-rvalue-from-vector");
            return out;
        },
        "add-top-level-asm", [](GccJitContext& self, sol::optional<GccJitLocation&> loc, const std::string& asm_stmts) {
            self.require_alive();
            gcc_jit_context_add_top_level_asm(self.ptr, optional_location(loc), asm_stmts.c_str());
            check_context(self.ptr, "add-top-level-asm");
        }
    );

    module.new_usertype<GccJitResult>("ResultRef",
        sol::no_constructor,
        "release", &GccJitResult::release,
        "drop", &GccJitResult::release,
        "get-code-address", [](GccJitResult& self, const std::string& name) {
            self.require_alive();
            void* code = gcc_jit_result_get_code(self.ptr, name.c_str());
            require_not_null(code, "get-code-address");
            return reinterpret_cast<uintptr_t>(code);
        },
        "get-global-address", [](GccJitResult& self, const std::string& name) {
            self.require_alive();
            void* ptr = gcc_jit_result_get_global(self.ptr, name.c_str());
            require_not_null(ptr, "get-global-address");
            return reinterpret_cast<uintptr_t>(ptr);
        },
        "call-i32", [](GccJitResult& self, const std::string& name, sol::optional<sol::table> args) {
            self.require_alive();
            void* code = gcc_jit_result_get_code(self.ptr, name.c_str());
            require_not_null(code, "call-i32");
            auto values = args ? table_to_ints(*args) : std::vector<int> {};
            return call_i32_impl(code, values);
        },
        "call-i64", [](GccJitResult& self, const std::string& name, sol::optional<sol::table> args) {
            self.require_alive();
            void* code = gcc_jit_result_get_code(self.ptr, name.c_str());
            require_not_null(code, "call-i64");
            auto values = args ? table_to_ints(*args) : std::vector<int> {};
            return call_i64_impl(code, values);
        },
        "call-double", [](GccJitResult& self, const std::string& name, sol::optional<sol::table> args) {
            self.require_alive();
            void* code = gcc_jit_result_get_code(self.ptr, name.c_str());
            require_not_null(code, "call-double");
            auto values = args ? table_to_doubles(*args) : std::vector<double> {};
            return call_double_impl(code, values);
        },
        "call-void", [](GccJitResult& self, const std::string& name, sol::optional<sol::table> args) {
            self.require_alive();
            void* code = gcc_jit_result_get_code(self.ptr, name.c_str());
            require_not_null(code, "call-void");
            auto values = args ? table_to_ints(*args) : std::vector<int> {};
            call_void_impl(code, values);
        },
        "call-word", [](GccJitResult& self, const std::string& name, sol::optional<sol::table> args) {
            self.require_alive();
            void* code = gcc_jit_result_get_code(self.ptr, name.c_str());
            require_not_null(code, "call-word");
            auto values = args ? table_to_words(*args) : std::vector<uintptr_t> {};
            return static_cast<uint64_t>(call_word_impl(code, values));
        },
        "call-pointer", [](GccJitResult& self, const std::string& name, sol::optional<sol::table> args) {
            self.require_alive();
            void* code = gcc_jit_result_get_code(self.ptr, name.c_str());
            require_not_null(code, "call-pointer");
            auto values = args ? table_to_words(*args) : std::vector<uintptr_t> {};
            return static_cast<uint64_t>(call_word_impl(code, values));
        },
        "call-void-word", [](GccJitResult& self, const std::string& name, sol::optional<sol::table> args) {
            self.require_alive();
            void* code = gcc_jit_result_get_code(self.ptr, name.c_str());
            require_not_null(code, "call-void-word");
            auto values = args ? table_to_words(*args) : std::vector<uintptr_t> {};
            call_void_word_impl(code, values);
        }
    );

    module.new_usertype<GccJitTimer>("TimerRef",
        sol::no_constructor,
        "release", &GccJitTimer::release,
        "drop", &GccJitTimer::release,
        "push", [](GccJitTimer& self, const std::string& item_name) {
            self.require_alive();
            gcc_jit_timer_push(self.ptr, item_name.c_str());
        },
        "pop", [](GccJitTimer& self, const std::string& item_name) {
            self.require_alive();
            gcc_jit_timer_pop(self.ptr, item_name.c_str());
        },
        "print-to-path", [](GccJitTimer& self, const std::string& path) {
            self.require_alive();
            FILE* f = fopen(path.c_str(), "w");
            if (!f) {
                throw sol::error("failed to open timer output file");
            }
            gcc_jit_timer_print(self.ptr, f);
            fflush(f);
            fclose(f);
        }
    );

    module.new_usertype<GccJitBorrowedTimer>("BorrowedTimerRef",
        sol::no_constructor,
        "push", [](GccJitBorrowedTimer& self, const std::string& item_name) {
            self.require_alive();
            gcc_jit_timer_push(self.ptr, item_name.c_str());
        },
        "pop", [](GccJitBorrowedTimer& self, const std::string& item_name) {
            self.require_alive();
            gcc_jit_timer_pop(self.ptr, item_name.c_str());
        },
        "print-to-path", [](GccJitBorrowedTimer& self, const std::string& path) {
            self.require_alive();
            FILE* f = fopen(path.c_str(), "w");
            if (!f) {
                throw sol::error("failed to open timer output file");
            }
            gcc_jit_timer_print(self.ptr, f);
            fflush(f);
            fclose(f);
        }
    );

    module.new_usertype<GccJitObject>("Object", sol::no_constructor,
        "get-context", [](GccJitObject obj) {
            require_not_null(obj.ptr, "object");
            GccJitContext out;
            out.ptr = gcc_jit_object_get_context(obj.ptr);
            out.owns_ptr = false;
            require_not_null(out.ptr, "object-get-context");
            return out;
        },
        "debug-string", [](GccJitObject obj) {
            require_not_null(obj.ptr, "object");
            const char* value = gcc_jit_object_get_debug_string(obj.ptr);
            require_not_null(value, "object-debug-string");
            return std::string(value);
        }
    );

    module.new_usertype<GccJitLocation>("Location", sol::no_constructor,
        "as-object", [](GccJitLocation loc) {
            require_not_null(loc.ptr, "location");
            GccJitObject out;
            out.ptr = gcc_jit_location_as_object(loc.ptr);
            require_not_null(out.ptr, "location-as-object");
            return out;
        }
    );

    module.new_usertype<GccJitType>("Type", sol::no_constructor,
        "as-object", [](GccJitType type) {
            require_not_null(type.ptr, "type");
            GccJitObject out;
            out.ptr = gcc_jit_type_as_object(type.ptr);
            require_not_null(out.ptr, "type-as-object");
            return out;
        },
        "get-pointer", [](GccJitType type) {
            require_not_null(type.ptr, "type");
            GccJitType out;
            out.ptr = gcc_jit_type_get_pointer(type.ptr);
            require_not_null(out.ptr, "type-get-pointer");
            return out;
        },
        "get-const", [](GccJitType type) {
            require_not_null(type.ptr, "type");
            GccJitType out;
            out.ptr = gcc_jit_type_get_const(type.ptr);
            require_not_null(out.ptr, "type-get-const");
            return out;
        },
        "get-volatile", [](GccJitType type) {
            require_not_null(type.ptr, "type");
            GccJitType out;
            out.ptr = gcc_jit_type_get_volatile(type.ptr);
            require_not_null(out.ptr, "type-get-volatile");
            return out;
        },
        "get-aligned", [](GccJitType type, int alignment) {
            require_not_null(type.ptr, "type");
            GccJitType out;
            out.ptr = gcc_jit_type_get_aligned(type.ptr, static_cast<size_t>(alignment));
            require_not_null(out.ptr, "type-get-aligned");
            return out;
        },
        "get-vector", [](GccJitType type, int units) {
            require_not_null(type.ptr, "type");
            GccJitType out;
            out.ptr = gcc_jit_type_get_vector(type.ptr, static_cast<size_t>(units));
            require_not_null(out.ptr, "type-get-vector");
            return out;
        }
    );

    module.new_usertype<GccJitField>("Field", sol::no_constructor,
        "as-object", [](GccJitField field) {
            require_not_null(field.ptr, "field");
            GccJitObject out;
            out.ptr = gcc_jit_field_as_object(field.ptr);
            require_not_null(out.ptr, "field-as-object");
            return out;
        }
    );

    module.new_usertype<GccJitStruct>("Struct", sol::no_constructor,
        "as-type", [](GccJitStruct struct_type) {
            require_not_null(struct_type.ptr, "struct");
            GccJitType out;
            out.ptr = gcc_jit_struct_as_type(struct_type.ptr);
            require_not_null(out.ptr, "struct-as-type");
            return out;
        },
        "set-fields", [](GccJitStruct struct_type, sol::optional<GccJitLocation&> loc, sol::table fields) {
            require_not_null(struct_type.ptr, "struct");
            auto field_ptrs = table_to_fields(fields);
            gcc_jit_struct_set_fields(struct_type.ptr, optional_location(loc), static_cast<int>(field_ptrs.size()), field_ptrs.data());
        }
    );

    module.new_usertype<GccJitParam>("Param", sol::no_constructor,
        "as-object", [](GccJitParam param) {
            require_not_null(param.ptr, "param");
            GccJitObject out;
            out.ptr = gcc_jit_param_as_object(param.ptr);
            require_not_null(out.ptr, "param-as-object");
            return out;
        },
        "as-lvalue", [](GccJitParam param) {
            require_not_null(param.ptr, "param");
            GccJitLValue out;
            out.ptr = gcc_jit_param_as_lvalue(param.ptr);
            require_not_null(out.ptr, "param-as-lvalue");
            return out;
        },
        "as-rvalue", [](GccJitParam param) {
            require_not_null(param.ptr, "param");
            GccJitRValue out;
            out.ptr = gcc_jit_param_as_rvalue(param.ptr);
            require_not_null(out.ptr, "param-as-rvalue");
            return out;
        }
    );

    module.new_usertype<GccJitFunction>("Function", sol::no_constructor,
        "as-object", [](GccJitFunction fn) {
            require_not_null(fn.ptr, "function");
            GccJitObject out;
            out.ptr = gcc_jit_function_as_object(fn.ptr);
            require_not_null(out.ptr, "function-as-object");
            return out;
        },
        "get-param", [](GccJitFunction fn, int index) {
            require_not_null(fn.ptr, "function");
            GccJitParam out;
            out.ptr = gcc_jit_function_get_param(fn.ptr, index);
            require_not_null(out.ptr, "function-get-param");
            return out;
        },
        "dump-to-dot", [](GccJitFunction fn, const std::string& path) {
            require_not_null(fn.ptr, "function");
            gcc_jit_function_dump_to_dot(fn.ptr, path.c_str());
        },
        "new-block", [](GccJitFunction fn, sol::optional<std::string> name) {
            require_not_null(fn.ptr, "function");
            GccJitBlock out;
            out.ptr = gcc_jit_function_new_block(fn.ptr, name ? name->c_str() : nullptr);
            require_not_null(out.ptr, "function-new-block");
            return out;
        },
        "new-local", [](GccJitFunction fn, sol::optional<GccJitLocation&> loc, GccJitType type,
                         const std::string& name) {
            require_not_null(fn.ptr, "function");
            require_not_null(type.ptr, "type");
            GccJitLValue out;
            out.ptr = gcc_jit_function_new_local(fn.ptr, optional_location(loc), type.ptr, name.c_str());
            require_not_null(out.ptr, "function-new-local");
            return out;
        },
        "get-address", [](GccJitFunction fn, sol::optional<GccJitLocation&> loc) {
            require_not_null(fn.ptr, "function");
            GccJitRValue out;
            out.ptr = gcc_jit_function_get_address(fn.ptr, optional_location(loc));
            require_not_null(out.ptr, "function-get-address");
            return out;
        }
    );

    module.new_usertype<GccJitBlock>("Block", sol::no_constructor,
        "as-object", [](GccJitBlock block) {
            require_not_null(block.ptr, "block");
            GccJitObject out;
            out.ptr = gcc_jit_block_as_object(block.ptr);
            require_not_null(out.ptr, "block-as-object");
            return out;
        },
        "get-function", [](GccJitBlock block) {
            require_not_null(block.ptr, "block");
            GccJitFunction out;
            out.ptr = gcc_jit_block_get_function(block.ptr);
            require_not_null(out.ptr, "block-get-function");
            return out;
        },
        "add-eval", [](GccJitBlock block, sol::optional<GccJitLocation&> loc, GccJitRValue value) {
            require_not_null(block.ptr, "block");
            require_not_null(value.ptr, "rvalue");
            gcc_jit_block_add_eval(block.ptr, optional_location(loc), value.ptr);
        },
        "add-assignment", [](GccJitBlock block, sol::optional<GccJitLocation&> loc,
                              GccJitLValue lvalue, GccJitRValue value) {
            require_not_null(block.ptr, "block");
            require_not_null(lvalue.ptr, "lvalue");
            require_not_null(value.ptr, "rvalue");
            gcc_jit_block_add_assignment(block.ptr, optional_location(loc), lvalue.ptr, value.ptr);
        },
        "add-assignment-op", [](GccJitBlock block, sol::optional<GccJitLocation&> loc,
                                 GccJitLValue lvalue, int op, GccJitRValue value) {
            require_not_null(block.ptr, "block");
            require_not_null(lvalue.ptr, "lvalue");
            require_not_null(value.ptr, "rvalue");
            gcc_jit_block_add_assignment_op(block.ptr, optional_location(loc), lvalue.ptr,
                static_cast<gcc_jit_binary_op>(op), value.ptr);
        },
        "add-comment", [](GccJitBlock block, sol::optional<GccJitLocation&> loc, const std::string& text) {
            require_not_null(block.ptr, "block");
            gcc_jit_block_add_comment(block.ptr, optional_location(loc), text.c_str());
        },
        "end-with-conditional", [](GccJitBlock block, sol::optional<GccJitLocation&> loc, GccJitRValue boolval,
                                    GccJitBlock on_true, GccJitBlock on_false) {
            require_not_null(block.ptr, "block");
            require_not_null(boolval.ptr, "boolval");
            require_not_null(on_true.ptr, "on-true");
            require_not_null(on_false.ptr, "on-false");
            gcc_jit_block_end_with_conditional(block.ptr, optional_location(loc), boolval.ptr, on_true.ptr, on_false.ptr);
        },
        "end-with-jump", [](GccJitBlock block, sol::optional<GccJitLocation&> loc, GccJitBlock target) {
            require_not_null(block.ptr, "block");
            require_not_null(target.ptr, "target");
            gcc_jit_block_end_with_jump(block.ptr, optional_location(loc), target.ptr);
        },
        "end-with-return", [](GccJitBlock block, sol::optional<GccJitLocation&> loc, GccJitRValue value) {
            require_not_null(block.ptr, "block");
            require_not_null(value.ptr, "value");
            gcc_jit_block_end_with_return(block.ptr, optional_location(loc), value.ptr);
        },
        "end-with-void-return", [](GccJitBlock block, sol::optional<GccJitLocation&> loc) {
            require_not_null(block.ptr, "block");
            gcc_jit_block_end_with_void_return(block.ptr, optional_location(loc));
        },
        "end-with-switch", [](GccJitBlock block, sol::optional<GccJitLocation&> loc,
                               GccJitRValue expr, GccJitBlock default_block, sol::table cases) {
            require_not_null(block.ptr, "block");
            require_not_null(expr.ptr, "expr");
            require_not_null(default_block.ptr, "default-block");
            auto case_ptrs = table_to_cases(cases);
            gcc_jit_block_end_with_switch(block.ptr, optional_location(loc), expr.ptr,
                default_block.ptr, static_cast<int>(case_ptrs.size()), case_ptrs.data());
        },
        "add-extended-asm", [](GccJitBlock block, sol::optional<GccJitLocation&> loc,
                                const std::string& asm_template) {
            require_not_null(block.ptr, "block");
            GccJitExtendedAsm out;
            out.ptr = gcc_jit_block_add_extended_asm(block.ptr, optional_location(loc), asm_template.c_str());
            require_not_null(out.ptr, "add-extended-asm");
            return out;
        },
        "end-with-extended-asm-goto", [](GccJitBlock block, sol::optional<GccJitLocation&> loc,
                                          const std::string& asm_template, sol::table goto_blocks,
                                          GccJitBlock fallthrough) {
            require_not_null(block.ptr, "block");
            require_not_null(fallthrough.ptr, "fallthrough");
            auto block_ptrs = table_to_blocks(goto_blocks);
            GccJitExtendedAsm out;
            out.ptr = gcc_jit_block_end_with_extended_asm_goto(block.ptr, optional_location(loc), asm_template.c_str(),
                static_cast<int>(block_ptrs.size()), block_ptrs.data(), fallthrough.ptr);
            require_not_null(out.ptr, "end-with-extended-asm-goto");
            return out;
        }
    );

    module.new_usertype<GccJitLValue>("LValue", sol::no_constructor,
        "as-object", [](GccJitLValue value) {
            require_not_null(value.ptr, "lvalue");
            GccJitObject out;
            out.ptr = gcc_jit_lvalue_as_object(value.ptr);
            require_not_null(out.ptr, "lvalue-as-object");
            return out;
        },
        "as-rvalue", [](GccJitLValue value) {
            require_not_null(value.ptr, "lvalue");
            GccJitRValue out;
            out.ptr = gcc_jit_lvalue_as_rvalue(value.ptr);
            require_not_null(out.ptr, "lvalue-as-rvalue");
            return out;
        },
        "access-field", [](GccJitLValue value, sol::optional<GccJitLocation&> loc, GccJitField field) {
            require_not_null(value.ptr, "lvalue");
            require_not_null(field.ptr, "field");
            GccJitLValue out;
            out.ptr = gcc_jit_lvalue_access_field(value.ptr, optional_location(loc), field.ptr);
            require_not_null(out.ptr, "lvalue-access-field");
            return out;
        },
        "get-address", [](GccJitLValue value, sol::optional<GccJitLocation&> loc) {
            require_not_null(value.ptr, "lvalue");
            GccJitRValue out;
            out.ptr = gcc_jit_lvalue_get_address(value.ptr, optional_location(loc));
            require_not_null(out.ptr, "lvalue-get-address");
            return out;
        },
        "set-initializer", [](GccJitLValue value, const std::string& bytes_blob) {
            require_not_null(value.ptr, "lvalue");
            gcc_jit_lvalue* out = gcc_jit_global_set_initializer(value.ptr, bytes_blob.data(), bytes_blob.size());
            require_not_null(out, "global-set-initializer");
            GccJitLValue ret;
            ret.ptr = out;
            return ret;
        }
    );

    module.new_usertype<GccJitRValue>("RValue", sol::no_constructor,
        "as-object", [](GccJitRValue value) {
            require_not_null(value.ptr, "rvalue");
            GccJitObject out;
            out.ptr = gcc_jit_rvalue_as_object(value.ptr);
            require_not_null(out.ptr, "rvalue-as-object");
            return out;
        },
        "get-type", [](GccJitRValue value) {
            require_not_null(value.ptr, "rvalue");
            GccJitType out;
            out.ptr = gcc_jit_rvalue_get_type(value.ptr);
            require_not_null(out.ptr, "rvalue-get-type");
            return out;
        },
        "access-field", [](GccJitRValue value, sol::optional<GccJitLocation&> loc, GccJitField field) {
            require_not_null(value.ptr, "rvalue");
            require_not_null(field.ptr, "field");
            GccJitRValue out;
            out.ptr = gcc_jit_rvalue_access_field(value.ptr, optional_location(loc), field.ptr);
            require_not_null(out.ptr, "rvalue-access-field");
            return out;
        },
        "dereference-field", [](GccJitRValue value, sol::optional<GccJitLocation&> loc, GccJitField field) {
            require_not_null(value.ptr, "rvalue");
            require_not_null(field.ptr, "field");
            GccJitLValue out;
            out.ptr = gcc_jit_rvalue_dereference_field(value.ptr, optional_location(loc), field.ptr);
            require_not_null(out.ptr, "rvalue-dereference-field");
            return out;
        },
        "dereference", [](GccJitRValue value, sol::optional<GccJitLocation&> loc) {
            require_not_null(value.ptr, "rvalue");
            GccJitLValue out;
            out.ptr = gcc_jit_rvalue_dereference(value.ptr, optional_location(loc));
            require_not_null(out.ptr, "rvalue-dereference");
            return out;
        },
        "set-bool-require-tail-call", [](GccJitRValue value, bool require_tail_call) {
            require_not_null(value.ptr, "rvalue");
            gcc_jit_rvalue_set_bool_require_tail_call(value.ptr, require_tail_call ? 1 : 0);
        }
    );

    module.new_usertype<GccJitCase>("Case", sol::no_constructor,
        "as-object", [](GccJitCase value) {
            require_not_null(value.ptr, "case");
            GccJitObject out;
            out.ptr = gcc_jit_case_as_object(value.ptr);
            require_not_null(out.ptr, "case-as-object");
            return out;
        }
    );

    module.new_usertype<GccJitExtendedAsm>("ExtendedAsm", sol::no_constructor,
        "as-object", [](GccJitExtendedAsm value) {
            require_not_null(value.ptr, "extended-asm");
            GccJitObject out;
            out.ptr = gcc_jit_extended_asm_as_object(value.ptr);
            require_not_null(out.ptr, "extended-asm-as-object");
            return out;
        },
        "set-volatile-flag", [](GccJitExtendedAsm value, bool flag) {
            require_not_null(value.ptr, "extended-asm");
            gcc_jit_extended_asm_set_volatile_flag(value.ptr, flag ? 1 : 0);
        },
        "set-inline-flag", [](GccJitExtendedAsm value, bool flag) {
            require_not_null(value.ptr, "extended-asm");
            gcc_jit_extended_asm_set_inline_flag(value.ptr, flag ? 1 : 0);
        },
        "add-output-operand", [](GccJitExtendedAsm value, sol::optional<std::string> symbolic_name,
                                  const std::string& constraint, GccJitLValue dest) {
            require_not_null(value.ptr, "extended-asm");
            require_not_null(dest.ptr, "dest");
            gcc_jit_extended_asm_add_output_operand(value.ptr,
                symbolic_name ? symbolic_name->c_str() : nullptr,
                constraint.c_str(),
                dest.ptr);
        },
        "add-input-operand", [](GccJitExtendedAsm value, sol::optional<std::string> symbolic_name,
                                 const std::string& constraint, GccJitRValue src) {
            require_not_null(value.ptr, "extended-asm");
            require_not_null(src.ptr, "src");
            gcc_jit_extended_asm_add_input_operand(value.ptr,
                symbolic_name ? symbolic_name->c_str() : nullptr,
                constraint.c_str(),
                src.ptr);
        },
        "add-clobber", [](GccJitExtendedAsm value, const std::string& victim) {
            require_not_null(value.ptr, "extended-asm");
            gcc_jit_extended_asm_add_clobber(value.ptr, victim.c_str());
        }
    );

    module.set_function("Context", []() {
        GccJitContext out;
        out.ptr = gcc_jit_context_acquire();
        require_not_null(out.ptr, "context-acquire");
        return out;
    });

    module.set_function("Timer", []() {
        GccJitTimer out;
        out.ptr = gcc_jit_timer_new();
        require_not_null(out.ptr, "timer-new");
        return out;
    });

    module.set_function("version-major", []() { return gcc_jit_version_major(); });
    module.set_function("version-minor", []() { return gcc_jit_version_minor(); });
    module.set_function("version-patchlevel", []() { return gcc_jit_version_patchlevel(); });

    sol::table str_option = lua.create_table();
    str_option["progname"] = GCC_JIT_STR_OPTION_PROGNAME;
    module["StrOption"] = str_option;

    sol::table int_option = lua.create_table();
    int_option["optimization-level"] = GCC_JIT_INT_OPTION_OPTIMIZATION_LEVEL;
    module["IntOption"] = int_option;

    sol::table bool_option = lua.create_table();
    bool_option["debuginfo"] = GCC_JIT_BOOL_OPTION_DEBUGINFO;
    bool_option["dump-initial-tree"] = GCC_JIT_BOOL_OPTION_DUMP_INITIAL_TREE;
    bool_option["dump-initial-gimple"] = GCC_JIT_BOOL_OPTION_DUMP_INITIAL_GIMPLE;
    bool_option["dump-generated-code"] = GCC_JIT_BOOL_OPTION_DUMP_GENERATED_CODE;
    bool_option["dump-summary"] = GCC_JIT_BOOL_OPTION_DUMP_SUMMARY;
    bool_option["dump-everything"] = GCC_JIT_BOOL_OPTION_DUMP_EVERYTHING;
    bool_option["selfcheck-gc"] = GCC_JIT_BOOL_OPTION_SELFCHECK_GC;
    bool_option["keep-intermediates"] = GCC_JIT_BOOL_OPTION_KEEP_INTERMEDIATES;
    module["BoolOption"] = bool_option;

    sol::table output_kind = lua.create_table();
    output_kind["assembler"] = GCC_JIT_OUTPUT_KIND_ASSEMBLER;
    output_kind["object-file"] = GCC_JIT_OUTPUT_KIND_OBJECT_FILE;
    output_kind["dynamic-library"] = GCC_JIT_OUTPUT_KIND_DYNAMIC_LIBRARY;
    output_kind["executable"] = GCC_JIT_OUTPUT_KIND_EXECUTABLE;
    module["OutputKind"] = output_kind;

    sol::table types = lua.create_table();
    types["void"] = GCC_JIT_TYPE_VOID;
    types["void-ptr"] = GCC_JIT_TYPE_VOID_PTR;
    types["bool"] = GCC_JIT_TYPE_BOOL;
    types["char"] = GCC_JIT_TYPE_CHAR;
    types["signed-char"] = GCC_JIT_TYPE_SIGNED_CHAR;
    types["unsigned-char"] = GCC_JIT_TYPE_UNSIGNED_CHAR;
    types["short"] = GCC_JIT_TYPE_SHORT;
    types["unsigned-short"] = GCC_JIT_TYPE_UNSIGNED_SHORT;
    types["int"] = GCC_JIT_TYPE_INT;
    types["unsigned-int"] = GCC_JIT_TYPE_UNSIGNED_INT;
    types["long"] = GCC_JIT_TYPE_LONG;
    types["unsigned-long"] = GCC_JIT_TYPE_UNSIGNED_LONG;
    types["long-long"] = GCC_JIT_TYPE_LONG_LONG;
    types["unsigned-long-long"] = GCC_JIT_TYPE_UNSIGNED_LONG_LONG;
    types["float"] = GCC_JIT_TYPE_FLOAT;
    types["double"] = GCC_JIT_TYPE_DOUBLE;
    types["long-double"] = GCC_JIT_TYPE_LONG_DOUBLE;
    types["const-char-ptr"] = GCC_JIT_TYPE_CONST_CHAR_PTR;
    types["size-t"] = GCC_JIT_TYPE_SIZE_T;
    types["file-ptr"] = GCC_JIT_TYPE_FILE_PTR;
    types["complex-float"] = GCC_JIT_TYPE_COMPLEX_FLOAT;
    types["complex-double"] = GCC_JIT_TYPE_COMPLEX_DOUBLE;
    types["complex-long-double"] = GCC_JIT_TYPE_COMPLEX_LONG_DOUBLE;
    module["Types"] = types;

    sol::table function_kind = lua.create_table();
    function_kind["exported"] = GCC_JIT_FUNCTION_EXPORTED;
    function_kind["internal"] = GCC_JIT_FUNCTION_INTERNAL;
    function_kind["imported"] = GCC_JIT_FUNCTION_IMPORTED;
    function_kind["always-inline"] = GCC_JIT_FUNCTION_ALWAYS_INLINE;
    module["FunctionKind"] = function_kind;

    sol::table global_kind = lua.create_table();
    global_kind["exported"] = GCC_JIT_GLOBAL_EXPORTED;
    global_kind["internal"] = GCC_JIT_GLOBAL_INTERNAL;
    global_kind["imported"] = GCC_JIT_GLOBAL_IMPORTED;
    module["GlobalKind"] = global_kind;

    sol::table unary_op = lua.create_table();
    unary_op["minus"] = GCC_JIT_UNARY_OP_MINUS;
    unary_op["bitwise-negate"] = GCC_JIT_UNARY_OP_BITWISE_NEGATE;
    unary_op["logical-negate"] = GCC_JIT_UNARY_OP_LOGICAL_NEGATE;
    unary_op["abs"] = GCC_JIT_UNARY_OP_ABS;
    module["UnaryOp"] = unary_op;

    sol::table binary_op = lua.create_table();
    binary_op["plus"] = GCC_JIT_BINARY_OP_PLUS;
    binary_op["minus"] = GCC_JIT_BINARY_OP_MINUS;
    binary_op["mult"] = GCC_JIT_BINARY_OP_MULT;
    binary_op["divide"] = GCC_JIT_BINARY_OP_DIVIDE;
    binary_op["modulo"] = GCC_JIT_BINARY_OP_MODULO;
    binary_op["bitwise-and"] = GCC_JIT_BINARY_OP_BITWISE_AND;
    binary_op["bitwise-xor"] = GCC_JIT_BINARY_OP_BITWISE_XOR;
    binary_op["bitwise-or"] = GCC_JIT_BINARY_OP_BITWISE_OR;
    binary_op["logical-and"] = GCC_JIT_BINARY_OP_LOGICAL_AND;
    binary_op["logical-or"] = GCC_JIT_BINARY_OP_LOGICAL_OR;
    binary_op["lshift"] = GCC_JIT_BINARY_OP_LSHIFT;
    binary_op["rshift"] = GCC_JIT_BINARY_OP_RSHIFT;
    module["BinaryOp"] = binary_op;

    sol::table comparison = lua.create_table();
    comparison["eq"] = GCC_JIT_COMPARISON_EQ;
    comparison["ne"] = GCC_JIT_COMPARISON_NE;
    comparison["lt"] = GCC_JIT_COMPARISON_LT;
    comparison["le"] = GCC_JIT_COMPARISON_LE;
    comparison["gt"] = GCC_JIT_COMPARISON_GT;
    comparison["ge"] = GCC_JIT_COMPARISON_GE;
    module["Comparison"] = comparison;

    return module;
}

} // namespace

void lua_bind_gccjit(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("gccjit", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_gccjit_table(lua);
    });
}

#else

void lua_bind_gccjit(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("gccjit", [](sol::this_state state) {
        sol::state_view lua_state(state);
        sol::table module = lua_state.create_table();
        module["available"] = false;
        module["missing-reason"] = "gccjit is only supported on Linux builds";
        sol::table mt = lua_state.create_table();
        mt["__index"] = [](sol::this_state, sol::object key) -> sol::object {
            std::string key_name = "<non-string>";
            if (key.is<std::string>()) {
                key_name = key.as<std::string>();
            }
            throw sol::error("gccjit unavailable: " + key_name);
            return sol::nil;
        };
        module[sol::metatable_key] = mt;
        return module;
    });
}

#endif
