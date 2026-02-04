#include <sol/sol.hpp>
#include <toml++/toml.hpp>

#include <cmath>
#include <limits>
#include <sstream>
#include <stdexcept>

namespace {

bool lua_table_is_array(const sol::table& table)
{
    bool isArray = true;
    int expected = 1;
    for (auto& kv : table) {
        if (!kv.first.is<int>() || kv.first.as<int>() != expected++) {
            isArray = false;
            break;
        }
    }
    return isArray;
}

bool lua_number_is_integral(double value)
{
    if (!std::isfinite(value)) {
        return false;
    }
    double int_part = 0.0;
    if (std::modf(value, &int_part) != 0.0) {
        return false;
    }
    if (value < static_cast<double>(std::numeric_limits<int64_t>::min()) ||
        value > static_cast<double>(std::numeric_limits<int64_t>::max())) {
        return false;
    }
    return true;
}

void toml_append_value(toml::array& array, const sol::object& obj);
void toml_set_value(toml::table& table, const std::string& key, const sol::object& obj);

toml::array lua_table_to_toml_array(const sol::table& table)
{
    toml::array array;
    int expected = 1;
    for (auto& kv : table) {
        if (!kv.first.is<int>() || kv.first.as<int>() != expected++) {
            throw std::runtime_error("TOML arrays must use contiguous numeric keys starting at 1");
        }
        toml_append_value(array, kv.second);
    }
    return array;
}

toml::table lua_table_to_toml_table(const sol::table& table)
{
    toml::table result;
    for (auto& kv : table) {
        if (!kv.first.is<std::string>()) {
            throw std::runtime_error("TOML tables require string keys");
        }
        toml_set_value(result, kv.first.as<std::string>(), kv.second);
    }
    return result;
}

void toml_append_value(toml::array& array, const sol::object& obj)
{
    if (obj.is<sol::table>()) {
        sol::table nested = obj.as<sol::table>();
        if (lua_table_is_array(nested)) {
            array.push_back(lua_table_to_toml_array(nested));
        } else {
            array.push_back(lua_table_to_toml_table(nested));
        }
        return;
    }

    if (obj.is<std::string>()) {
        array.push_back(obj.as<std::string>());
    } else if (obj.get_type() == sol::type::number) {
        double value = obj.as<double>();
        if (lua_number_is_integral(value)) {
            array.push_back(static_cast<int64_t>(value));
        } else {
            array.push_back(value);
        }
    } else if (obj.is<bool>()) {
        array.push_back(obj.as<bool>());
    } else if (obj.is<sol::nil_t>()) {
        throw std::runtime_error("TOML does not support nil values");
    } else {
        throw std::runtime_error("Unsupported Lua type for TOML array value");
    }
}

void toml_set_value(toml::table& table, const std::string& key, const sol::object& obj)
{
    if (obj.is<sol::table>()) {
        sol::table nested = obj.as<sol::table>();
        if (lua_table_is_array(nested)) {
            table.insert(key, lua_table_to_toml_array(nested));
        } else {
            table.insert(key, lua_table_to_toml_table(nested));
        }
        return;
    }

    if (obj.is<std::string>()) {
        table.insert(key, obj.as<std::string>());
    } else if (obj.get_type() == sol::type::number) {
        double value = obj.as<double>();
        if (lua_number_is_integral(value)) {
            table.insert(key, static_cast<int64_t>(value));
        } else {
            table.insert(key, value);
        }
    } else if (obj.is<bool>()) {
        table.insert(key, obj.as<bool>());
    } else if (obj.is<sol::nil_t>()) {
        throw std::runtime_error("TOML does not support nil values");
    } else {
        throw std::runtime_error("Unsupported Lua type for TOML table value");
    }
}

sol::object toml_to_lua(sol::state_view lua, const toml::node& node)
{
    if (node.is_table()) {
        sol::table tbl = lua.create_table();
        for (const auto& [key, value] : *node.as_table()) {
            tbl[key.str()] = toml_to_lua(lua, value);
        }
        return tbl;
    }

    if (node.is_array()) {
        sol::table tbl = lua.create_table();
        int i = 1;
        for (const auto& value : *node.as_array()) {
            tbl[i++] = toml_to_lua(lua, value);
        }
        return tbl;
    }

    if (node.is_string()) {
        return sol::make_object(lua, node.as_string()->get());
    }

    if (node.is_integer()) {
        return sol::make_object(lua, node.as_integer()->get());
    }

    if (node.is_floating_point()) {
        return sol::make_object(lua, node.as_floating_point()->get());
    }

    if (node.is_boolean()) {
        return sol::make_object(lua, node.as_boolean()->get());
    }

    if (node.is_date() || node.is_time() || node.is_date_time()) {
        throw std::runtime_error("TOML date/time values are not supported");
    }

    throw std::runtime_error("Unsupported TOML value type");
}

sol::object toml_loads(sol::this_state ts, const std::string& toml_str)
{
    sol::state_view lua(ts);
#if TOML_EXCEPTIONS
    try {
        toml::table result = toml::parse(toml_str);
        return toml_to_lua(lua, result);
    } catch (const toml::parse_error& err) {
        throw std::runtime_error(std::string(err.description()));
    }
#else
    toml::parse_result result = toml::parse(toml_str);
    if (result.failed()) {
        throw std::runtime_error(std::string(result.error().description()));
    }
    return toml_to_lua(lua, result.table());
#endif
}

std::string toml_dumps(const sol::object& lua_obj)
{
    if (!lua_obj.is<sol::table>()) {
        throw std::runtime_error("toml.dumps expects a Lua table");
    }

    toml::table root = lua_table_to_toml_table(lua_obj.as<sol::table>());
    std::ostringstream out;
    out << root;
    return out.str();
}

sol::table create_toml_table(sol::state_view lua)
{
    sol::table toml_table = lua.create_table();
    toml_table.set_function("loads", &toml_loads);
    toml_table.set_function("dumps", &toml_dumps);
    return toml_table;
}

} // namespace

void lua_bind_toml(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("toml", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_toml_table(lua);
    });
}
