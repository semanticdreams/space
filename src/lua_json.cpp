#include <sol/sol.hpp>
#include <fstream>

#include "nlohmann/json.hpp"

using json = nlohmann::json;

// C++: JSON string → Lua object
sol::object json_loads(sol::this_state ts, const std::string& json_str);

// C++: Lua table → JSON string
std::string json_dumps(const sol::object& lua_obj);

// Helpers
sol::object json_to_lua(sol::state_view lua, const json& j);
json lua_to_json(const sol::object& obj);

// Implementation

sol::object json_loads(sol::this_state ts, const std::string& json_str) {
    json j = json::parse(json_str);
    sol::state_view lua(ts);
    return json_to_lua(lua, j);
}

std::string json_dumps(const sol::object& lua_obj) {
    json j = lua_to_json(lua_obj);
    return j.dump();
}

sol::object json_to_lua(sol::state_view lua, const json& j) {
    switch (j.type()) {
        case json::value_t::object: {
            sol::table tbl = lua.create_table();
            for (auto& [key, value] : j.items()) {
                tbl[key] = json_to_lua(lua, value);
            }
            return tbl;
        }
        case json::value_t::array: {
            sol::table tbl = lua.create_table();
            int i = 1;
            for (auto& value : j) {
                tbl[i++] = json_to_lua(lua, value);
            }
            return tbl;
        }
        case json::value_t::string:
            return sol::make_object(lua, j.get<std::string>());
        case json::value_t::boolean:
            return sol::make_object(lua, j.get<bool>());
        case json::value_t::number_integer:
            return sol::make_object(lua, j.get<int>());
        case json::value_t::number_unsigned:
            return sol::make_object(lua, j.get<unsigned int>());
        case json::value_t::number_float:
            return sol::make_object(lua, j.get<double>());
        case json::value_t::null:
        default:
            return sol::make_object(lua, sol::nil);
    }
}

// Recursive: Lua → JSON
json lua_to_json(const sol::object& obj) {
    if (obj.is<sol::table>()) {
        sol::table tbl = obj.as<sol::table>();

        // Check if array-like
        bool is_array = true;
        int expected = 1;
        for (auto& kv : tbl) {
            if (!kv.first.is<int>() || kv.first.as<int>() != expected++) {
                is_array = false;
                break;
            }
        }

        json j = is_array ? json::array() : json::object();

        for (auto& kv : tbl) {
            auto key = kv.first;
            auto value = kv.second;
            if (is_array) {
                j.push_back(lua_to_json(value));
            } else {
                std::string k = key.as<std::string>();
                j[k] = lua_to_json(value);
            }
        }

        return j;
    } else if (obj.is<std::string>()) {
        return obj.as<std::string>();
    } else if (obj.is<double>()) {
        return obj.as<double>();
    } else if (obj.is<int>()) {
        return obj.as<int>();
    } else if (obj.is<bool>()) {
        return obj.as<bool>();
    } else {
        return nullptr;
    }
}

// ----------------------------------
// Expose to Lua

namespace {

sol::table create_json_table(sol::state_view lua)
{
    sol::table json_table = lua.create_table();
    json_table.set_function("loads", &json_loads);
    json_table.set_function("dumps", &json_dumps);
    return json_table;
}

} // namespace

void lua_bind_json(sol::state& lua) {
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("json", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_json_table(lua);
    });
}
