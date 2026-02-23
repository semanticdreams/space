#include <iostream>
#include <stdexcept>

#include <sol/sol.hpp>

#include "lua_gccjit.h"

int main()
{
    try {
        sol::state lua;
        lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::math, sol::lib::table, sol::lib::string);
        lua_bind_gccjit(lua);

        lua.script(R"(
            local gccjit = require("gccjit")
            local ctxt = gccjit.Context()
            local int_type = ctxt["get-type"](ctxt, gccjit.Types["int"])
            local a = ctxt["new-param"](ctxt, nil, int_type, "a")
            local b = ctxt["new-param"](ctxt, nil, int_type, "b")
            local fn = ctxt["new-function"](ctxt, nil, gccjit.FunctionKind["exported"], int_type, "add_from_cpp_test", {a, b}, false)
            local block = fn["new-block"](fn, "entry")
            local ar = a["as-rvalue"](a)
            local br = b["as-rvalue"](b)
            local sum = ctxt["new-binary-op"](ctxt, nil, gccjit.BinaryOp["plus"], int_type, ar, br)
            block["end-with-return"](block, nil, sum)

            local result = ctxt["compile"](ctxt)
            local value = result["call-i32"](result, "add_from_cpp_test", {21, 21})
            if value ~= 42 then
                error("unexpected value from gccjit binding: " .. tostring(value))
            end

            result["drop"](result)
            ctxt["drop"](ctxt)
        )");
    }
    catch (const std::exception& e) {
        std::cerr << "test_lua_gccjit_binding failure: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
