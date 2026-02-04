#include <sol/sol.hpp>

#include <string>

#include "keyring.h"

namespace {

struct LuaKeyring
{
    Keyring* handle { nullptr };

    bool set_password(const std::string& service, const std::string& account, const std::string& secret)
    {
        return handle->set_password(service, account, secret);
    }

    sol::object get_password(sol::state_view lua, const std::string& service, const std::string& account)
    {
        std::optional<std::string> result = handle->get_password(service, account);
        if (!result.has_value()) {
            return sol::lua_nil;
        }
        return sol::make_object(lua, result.value());
    }

    bool delete_password(const std::string& service, const std::string& account)
    {
        return handle->delete_password(service, account);
    }
};

LuaKeyring* get_lua_keyring(sol::state& lua)
{
    sol::object obj = lua["keyring-handle"];
    if (obj.is<LuaKeyring*>()) {
        return obj.as<LuaKeyring*>();
    }
    return nullptr;
}

} // namespace

void lua_bind_keyring(sol::state& lua, Keyring& keyring)
{
    auto* state = new LuaKeyring();
    state->handle = &keyring;
    lua["keyring-handle"] = state;

    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("keyring", [&lua, state](sol::this_state s) {
        sol::state_view lua_state(s);
        sol::table binding = lua_state.create_table();
        binding.set_function("set-password", [state](const std::string& service,
                                                     const std::string& account,
                                                     const std::string& secret) {
            return state->set_password(service, account, secret);
        });
        binding.set_function("get-password", [&lua, state](const std::string& service, const std::string& account) {
            return state->get_password(lua, service, account);
        });
        binding.set_function("delete-password", [state](const std::string& service, const std::string& account) {
            return state->delete_password(service, account);
        });
        return binding;
    });
}

void lua_keyring_drop(sol::state& lua)
{
    LuaKeyring* state = get_lua_keyring(lua);
    if (state != nullptr) {
        sol::table package = lua["package"];
        sol::table loaded = package["loaded"];
        loaded["keyring"] = sol::lua_nil;
        lua["keyring-handle"] = sol::lua_nil;
        delete state;
    }
}
