#include "lua_matrix.h"

#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "lua_callbacks.h"

#ifdef SPACE_MATRIX_ENABLED
#include "matrix.h"
#endif

#ifdef SPACE_MATRIX_ENABLED
namespace {
struct MatrixResult
{
    bool ok { false };
    int32_t code { 0 };
    std::string message;
};

void on_client_created(mx_client_t* client, mx_result_t result, void* user_data);
void on_login_result(mx_result_t result, mx_string_t user_id, void* user_data);
void on_sync_result(mx_result_t result, void* user_data);
void on_rooms_result(mx_result_t result, mx_room_list_t rooms, void* user_data);

std::string string_from_mx(mx_string_t value)
{
    if (value.data == nullptr || value.len == 0) {
        return {};
    }
    return std::string(value.data, value.len);
}

MatrixResult capture_result(mx_result_t result)
{
    MatrixResult out;
    out.ok = result.ok != 0;
    out.code = result.error.code;
    out.message = string_from_mx(result.error.message);
    mx_result_free(result);
    return out;
}

sol::table make_error_table(sol::state_view lua, const MatrixResult& result)
{
    sol::table error = lua.create_table();
    error["code"] = result.code;
    error["message"] = result.message;
    return error;
}

void on_login_result(mx_result_t result, mx_string_t user_id, void* user_data)
{
    uint64_t cb_id = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(user_data));
    MatrixResult captured = capture_result(result);
    std::string user = string_from_mx(user_id);
    mx_string_free(user_id);
    lua_callbacks_enqueue(cb_id, [captured = std::move(captured), user = std::move(user)](sol::state_view lua) {
        sol::table payload = lua.create_table();
        payload["ok"] = captured.ok;
        payload["error"] = captured.ok ? sol::lua_nil : make_error_table(lua, captured);
        payload["user-id"] = user.empty() ? sol::lua_nil : sol::make_object(lua, user);
        return sol::make_object(lua, payload);
    });
}

void on_sync_result(mx_result_t result, void* user_data)
{
    uint64_t cb_id = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(user_data));
    MatrixResult captured = capture_result(result);
    lua_callbacks_enqueue(cb_id, [captured = std::move(captured)](sol::state_view lua) {
        sol::table payload = lua.create_table();
        payload["ok"] = captured.ok;
        payload["error"] = captured.ok ? sol::lua_nil : make_error_table(lua, captured);
        return sol::make_object(lua, payload);
    });
}

void on_rooms_result(mx_result_t result, mx_room_list_t rooms, void* user_data)
{
    uint64_t cb_id = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(user_data));
    MatrixResult captured = capture_result(result);
    std::vector<std::string> ids;
    if (rooms.room_ids != nullptr && rooms.count > 0) {
        ids.reserve(rooms.count);
        for (std::size_t i = 0; i < rooms.count; ++i) {
            ids.push_back(string_from_mx(rooms.room_ids[i]));
        }
    }
    mx_room_list_free(rooms);
    lua_callbacks_enqueue(cb_id, [captured = std::move(captured), ids = std::move(ids)](sol::state_view lua) {
        sol::table payload = lua.create_table();
        payload["ok"] = captured.ok;
        payload["error"] = captured.ok ? sol::lua_nil : make_error_table(lua, captured);
        sol::table rooms_table = lua.create_table();
        std::size_t index = 1;
        for (const auto& room_id : ids) {
            rooms_table[index++] = room_id;
        }
        payload["rooms"] = rooms_table;
        return sol::make_object(lua, payload);
    });
}

struct MatrixClient
{
    explicit MatrixClient(mx_client_t* handle_ref)
        : handle(handle_ref)
    {
    }

    ~MatrixClient()
    {
        close();
    }

    void close()
    {
        if (!closed && handle != nullptr) {
            mx_client_free(handle);
            handle = nullptr;
            closed = true;
        }
    }

    bool is_closed() const { return closed; }

    void login_password(const std::string& username, const std::string& password, sol::function cb)
    {
        ensure_open("login-password");
        uint64_t cb_id = lua_callbacks_register(std::move(cb));
        mx_client_login_password(handle, username.c_str(), password.c_str(), &on_login_result,
                                 reinterpret_cast<void*>(static_cast<uintptr_t>(cb_id)));
    }

    void sync_once(sol::function cb)
    {
        ensure_open("sync-once");
        uint64_t cb_id = lua_callbacks_register(std::move(cb));
        mx_client_sync_once(handle, &on_sync_result,
                            reinterpret_cast<void*>(static_cast<uintptr_t>(cb_id)));
    }

    void rooms(sol::function cb)
    {
        ensure_open("rooms");
        uint64_t cb_id = lua_callbacks_register(std::move(cb));
        mx_client_rooms(handle, &on_rooms_result,
                        reinterpret_cast<void*>(static_cast<uintptr_t>(cb_id)));
    }

private:
    void ensure_open(const std::string& action) const
    {
        if (closed || handle == nullptr) {
            throw sol::error("matrix client is closed: " + action);
        }
    }

    mx_client_t* handle { nullptr };
    bool closed { false };
};

} // namespace

namespace {

sol::table create_matrix_table(sol::state_view lua)
{
    sol::table matrix_table = lua.create_table();
    matrix_table.new_usertype<MatrixClient>("MatrixClient",
        sol::no_constructor,
        "login-password", &MatrixClient::login_password,
        "sync-once", &MatrixClient::sync_once,
        "rooms", &MatrixClient::rooms,
        "close", &MatrixClient::close,
        "is-closed", &MatrixClient::is_closed);

    matrix_table.set_function("create-client", [lua](sol::table opts) {
        std::string homeserver = opts.get_or<std::string>("homeserver-url", "");
        if (homeserver.empty()) {
            homeserver = opts.get_or<std::string>("homeserver", "");
        }
        if (homeserver.empty()) {
            throw sol::error("matrix.create-client requires homeserver-url");
        }
        sol::object cb_obj = opts.get<sol::object>("callback");
        sol::optional<sol::function> cb_func;
        if (cb_obj.is<sol::function>()) {
            cb_func = cb_obj.as<sol::function>();
        } else {
            cb_func = opts.get<sol::optional<sol::function>>("cb");
        }
        if (!cb_func) {
            throw sol::error("matrix.create-client requires callback");
        }
        uint64_t cb_id = lua_callbacks_register(cb_func.value());
        mx_client_create(homeserver.c_str(), &on_client_created,
                         reinterpret_cast<void*>(static_cast<uintptr_t>(cb_id)));
        return cb_id;
    });
    return matrix_table;
}

void on_client_created(mx_client_t* client, mx_result_t result, void* user_data)
{
    uint64_t cb_id = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(user_data));
    MatrixResult captured = capture_result(result);
    lua_callbacks_enqueue(cb_id, [captured = std::move(captured), client](sol::state_view lua) {
        sol::table payload = lua.create_table();
        payload["ok"] = captured.ok;
        payload["error"] = captured.ok ? sol::lua_nil : make_error_table(lua, captured);
        if (captured.ok && client != nullptr) {
            payload["client"] = std::make_shared<MatrixClient>(client);
        } else {
            payload["client"] = sol::lua_nil;
        }
        return sol::make_object(lua, payload);
    });
}

} // namespace

#endif

#ifdef SPACE_MATRIX_ENABLED
void lua_bind_matrix(sol::state& lua)
{
    mx_init();
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("matrix", [](sol::this_state state) {
        sol::state_view lua_view(state);
        return create_matrix_table(lua_view);
    });
}
#else
void lua_bind_matrix(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];
    preload.set_function("matrix", [](sol::this_state state) {
        sol::state_view lua_view(state);
        sol::table module = lua_view.create_table();
        module.set_function("create-client", []() {
            throw sol::error("matrix library not built; enable SPACE_BUILD_MATRIX");
        });
        return module;
    });
}
#endif
