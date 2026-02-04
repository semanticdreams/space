#include <sol/sol.hpp>

#include <boost/uuid/random_generator.hpp>
#include <boost/uuid/uuid.hpp>
#include <boost/uuid/uuid_io.hpp>

namespace {

std::string uuid_v4()
{
    boost::uuids::random_generator generator;
    boost::uuids::uuid value = generator();
    return boost::uuids::to_string(value);
}

sol::table create_uuid_table(sol::state_view lua)
{
    sol::table uuid_table = lua.create_table();
    uuid_table.set_function("v4", &uuid_v4);
    return uuid_table;
}

} // namespace

void lua_bind_uuid(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("uuid", [](sol::this_state state) {
        sol::state_view lua_view(state);
        return create_uuid_table(lua_view);
    });
}
