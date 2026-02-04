#include <map>
#include <sol/sol.hpp>

#include <glm/glm.hpp>

#include "colors.h"

namespace {

sol::table swatch_to_table(sol::state_view lua, const std::map<int, glm::vec3>& swatch)
{
    sol::table tbl = lua.create_table();
    for (const auto& [key, value] : swatch) {
        tbl[key] = value;
    }
    return tbl;
}

sol::table colors_create_color_swatch(sol::this_state ts, const glm::vec3& base_color)
{
    sol::state_view lua(ts);
    return swatch_to_table(lua, createColorSwatch(base_color));
}

sol::table colors_create_color_swatch(sol::this_state ts, const glm::vec4& base_color)
{
    sol::state_view lua(ts);
    return swatch_to_table(lua, createColorSwatch(glm::vec3(base_color)));
}

} // namespace

namespace {

sol::table create_colors_table(sol::state_view lua)
{
    sol::table colors_table = lua.create_table();
    colors_table.set_function("create-color-swatch",
        sol::overload(
            static_cast<sol::table(*)(sol::this_state, const glm::vec3&)>(&colors_create_color_swatch),
            static_cast<sol::table(*)(sol::this_state, const glm::vec4&)>(&colors_create_color_swatch)
        )
    );
    return colors_table;
}

} // namespace

void lua_bind_colors(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("colors", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_colors_table(lua);
    });
}
