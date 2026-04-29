#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include <sol/sol.hpp>

#include "lua_callbacks.h"
#include "realtime/auth_ticket.h"
#include "realtime/core.h"

namespace {

using space::realtime::AuthTicket;
using space::realtime::ClientCallbacks;
using space::realtime::FeatureDefinition;
using space::realtime::FeatureRegistry;
using space::realtime::RealtimeClient;
using space::realtime::RealtimeServer;
using space::realtime::RealtimeService;
using space::realtime::ServerCallbacks;
using space::realtime::SignedAuthTicket;
using space::realtime::VerifiedAuthTicket;
using space::realtime::make_dev_auth_ticket;
using space::realtime::verify_dev_auth_ticket;

constexpr char kHexDigits[] = "0123456789abcdef";

char decode_hex_digit(char ch)
{
    if (ch >= '0' && ch <= '9') {
        return static_cast<char>(ch - '0');
    }
    if (ch >= 'a' && ch <= 'f') {
        return static_cast<char>(10 + (ch - 'a'));
    }
    if (ch >= 'A' && ch <= 'F') {
        return static_cast<char>(10 + (ch - 'A'));
    }
    throw std::runtime_error("invalid hex digit in realtime connect token");
}

std::string hex_encode(const std::string& bytes)
{
    std::string encoded;
    encoded.resize(bytes.size() * 2);
    for (size_t i = 0; i < bytes.size(); ++i) {
        const unsigned char value = static_cast<unsigned char>(bytes[i]);
        encoded[i * 2] = kHexDigits[value >> 4];
        encoded[i * 2 + 1] = kHexDigits[value & 0x0f];
    }
    return encoded;
}

std::string hex_decode(const std::string& text)
{
    if (text.size() % 2 != 0) {
        throw std::runtime_error("realtime connect token must have even-length hex encoding");
    }

    std::string decoded;
    decoded.resize(text.size() / 2);
    for (size_t i = 0; i < decoded.size(); ++i) {
        const unsigned char high = static_cast<unsigned char>(decode_hex_digit(text[i * 2]));
        const unsigned char low = static_cast<unsigned char>(decode_hex_digit(text[i * 2 + 1]));
        decoded[i] = static_cast<char>((high << 4) | low);
    }
    return decoded;
}

std::vector<uint16_t> parse_allowed_features(sol::table features)
{
    std::vector<uint16_t> result;
    const size_t count = features.size();
    result.reserve(count);
    for (size_t i = 1; i <= count; ++i) {
        result.push_back(features.get<uint16_t>(static_cast<int>(i)));
    }
    return result;
}

std::vector<std::string> parse_string_list(sol::table values)
{
    std::vector<std::string> result;
    const size_t count = values.size();
    result.reserve(count);
    for (size_t i = 1; i <= count; ++i) {
        result.push_back(values.get<std::string>(static_cast<int>(i)));
    }
    return result;
}

AuthTicket auth_ticket_from_lua(sol::table opts)
{
    AuthTicket ticket;
    ticket.ticket_id = opts.get_or<std::string>("ticket-id", "");
    ticket.subject_user_id = opts.get_or<std::string>("subject-user-id", "");
    ticket.client_id = opts.get_or<uint64_t>("client-id", 0);
    ticket.server_scope = opts.get_or<std::string>("server-scope", "");
    if (sol::optional<sol::table> features = opts["allowed-features"]) {
        ticket.allowed_features = parse_allowed_features(*features);
    }
    ticket.issued_at = opts.get_or<int64_t>("issued-at", 0);
    ticket.expires_at = opts.get_or<int64_t>("expires-at", 0);
    return ticket;
}

SignedAuthTicket signed_auth_ticket_from_lua(sol::table signed_ticket_table)
{
    SignedAuthTicket signed_ticket;
    signed_ticket.payload_json = signed_ticket_table.get_or<std::string>("payload-json", "");
    signed_ticket.signature_hex = signed_ticket_table.get_or<std::string>("signature", "");
    return signed_ticket;
}

VerifiedAuthTicket verified_dev_auth_ticket_from_lua(sol::table opts)
{
    sol::optional<sol::table> signed_ticket_table = opts["signed-ticket"];
    if (!signed_ticket_table) {
        throw sol::error("realtime server create-connect-token requires signed-ticket");
    }
    SignedAuthTicket signed_ticket = signed_auth_ticket_from_lua(*signed_ticket_table);
    std::string secret = opts.get_or<std::string>("secret", "");
    const std::string& payload_json = signed_ticket.payload_json;
    const std::string& signature = signed_ticket.signature_hex;
    if (payload_json.empty()) {
        throw sol::error("realtime server create-connect-token requires payload-json");
    }
    if (signature.empty()) {
        throw sol::error("realtime server create-connect-token requires signature");
    }
    if (secret.empty()) {
        throw sol::error("realtime server create-connect-token requires secret");
    }

    std::optional<int64_t> now;
    if (sol::optional<int64_t> now_opt = opts["now"]) {
        now = *now_opt;
    }
    return verify_dev_auth_ticket(payload_json, signature, secret, now);
}

bool is_known_callback_name(const std::string& name, std::initializer_list<const char*> allowed_names)
{
    for (const char* allowed_name : allowed_names) {
        if (name == allowed_name) {
            return true;
        }
    }
    return false;
}

void ensure_known_callback_name(const std::string& owner_kind,
                                const std::string& name,
                                std::initializer_list<const char*> allowed_names)
{
    if (is_known_callback_name(name, allowed_names)) {
        return;
    }
    throw sol::error("realtime " + owner_kind + " does not support callback '" + name + "'");
}

sol::table auth_ticket_to_lua(sol::state_view lua, const AuthTicket& ticket)
{
    sol::table out = lua.create_table();
    out["ticket-id"] = ticket.ticket_id;
    out["subject-user-id"] = ticket.subject_user_id;
    out["client-id"] = ticket.client_id;
    out["server-scope"] = ticket.server_scope;
    out["issued-at"] = ticket.issued_at;
    out["expires-at"] = ticket.expires_at;
    sol::table features = lua.create_table();
    int index = 1;
    for (uint16_t feature_id : ticket.allowed_features) {
        features[index++] = feature_id;
    }
    out["allowed-features"] = features;
    return out;
}

sol::table signed_auth_ticket_to_lua(sol::state_view lua, const SignedAuthTicket& signed_ticket)
{
    sol::table out = auth_ticket_to_lua(lua, signed_ticket.ticket);
    out["payload-json"] = signed_ticket.payload_json;
    out["signature"] = signed_ticket.signature_hex;
    return out;
}

class LuaRealtimeServer
{
public:
    LuaRealtimeServer(std::shared_ptr<RealtimeServer> server, lua_State* lua_state)
        : server_(std::move(server))
        , lua_state_(lua_state)
    {
    }

    ~LuaRealtimeServer()
    {
        close_impl(false);
    }

    void ensure_queryable() const
    {
        if (closed_) {
            throw sol::error("realtime server is closed");
        }
    }

    void ensure_operational() const
    {
        ensure_queryable();
        if (closing_) {
            throw sol::error("realtime server is closing");
        }
    }

    void set_callback(const std::string& name, sol::function fn)
    {
        ensure_operational();
        ensure_known_callback_name("server",
                                   name,
                                   { "started",
                                     "stopped",
                                     "client-connected",
                                     "client-disconnected",
                                     "feature-activated",
                                     "feature-deactivated",
                                     "message",
                                     "error" });
        auto it = callback_ids_.find(name);
        if (it != callback_ids_.end()) {
            lua_callbacks_unregister(it->second);
        }
        callback_ids_[name] = lua_callbacks_register(std::move(fn));
        refresh_callbacks();
    }

    void start()
    {
        ensure_operational();
        server_->start();
    }

    void close()
    {
        close_impl(true);
    }

    bool is_running() const
    {
        ensure_queryable();
        return server_->is_running();
    }

    std::string address() const
    {
        ensure_queryable();
        return server_->address();
    }

    std::string create_connect_token(sol::table opts)
    {
        ensure_operational();
        VerifiedAuthTicket auth_ticket = verified_dev_auth_ticket_from_lua(opts);
        int expire_seconds = opts["expire-seconds"].get_or(30);
        int timeout_seconds = opts["timeout-seconds"].get_or(10);
        return hex_encode(server_->create_connect_token(auth_ticket, expire_seconds, timeout_seconds));
    }

    void activate_feature(int client_index, uint16_t feature_id)
    {
        ensure_operational();
        server_->activate_feature(client_index, feature_id);
    }

    void deactivate_feature(int client_index, uint16_t feature_id)
    {
        ensure_operational();
        server_->deactivate_feature(client_index, feature_id);
    }

    void send_reliable(int client_index, uint16_t feature_id, const std::string& payload)
    {
        ensure_operational();
        server_->send_reliable(client_index, feature_id, payload);
    }

    void send_unreliable(int client_index, uint16_t feature_id, const std::string& payload)
    {
        ensure_operational();
        server_->send_unreliable(client_index, feature_id, payload);
    }

    void broadcast_reliable(uint16_t feature_id, const std::string& payload)
    {
        ensure_operational();
        server_->broadcast_reliable(feature_id, payload);
    }

    void broadcast_unreliable(uint16_t feature_id, const std::string& payload)
    {
        ensure_operational();
        server_->broadcast_unreliable(feature_id, payload);
    }

private:
    void close_impl(bool dispatch_callbacks)
    {
        if (closed_ || closing_) {
            return;
        }

        closing_ = true;
        server_->stop();

        std::vector<uint64_t> ids = callback_id_list();
        if (dispatch_callbacks && lua_state_) {
            sol::state_view lua(lua_state_);
            while (lua_callbacks_dispatch_ids(lua, ids) > 0) {
            }
        }
        lua_callbacks_retire_ids(ids);

        for (uint64_t id : ids) {
            lua_callbacks_unregister(id);
        }
        callback_ids_.clear();
        closed_ = true;
        closing_ = false;
    }

    std::vector<uint64_t> callback_id_list() const
    {
        std::vector<uint64_t> ids;
        ids.reserve(callback_ids_.size());
        for (const auto& [name, id] : callback_ids_) {
            (void)name;
            ids.push_back(id);
        }
        return ids;
    }

    void refresh_callbacks()
    {
        ServerCallbacks callbacks;

        if (auto it = callback_ids_.find("started"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.started = [id](const std::string& address) {
                lua_callbacks_enqueue(id, [address](sol::state_view lua) {
                    sol::table payload = lua.create_table();
                    payload["address"] = address;
                    return sol::make_object(lua, payload);
                });
            };
        }
        if (auto it = callback_ids_.find("stopped"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.stopped = [id]() {
                lua_callbacks_enqueue(id, [](sol::state_view lua) {
                    return sol::make_object(lua, lua.create_table());
                });
            };
        }
        if (auto it = callback_ids_.find("client-connected"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.client_connected = [id](int client_index, uint64_t client_id, const AuthTicket& auth_ticket) {
                lua_callbacks_enqueue(id, [client_index, client_id, auth_ticket](sol::state_view lua) {
                    sol::table payload = lua.create_table();
                    payload["client-index"] = client_index;
                    payload["client-id"] = client_id;
                    payload["auth-ticket"] = auth_ticket_to_lua(lua, auth_ticket);
                    return sol::make_object(lua, payload);
                });
            };
        }
        if (auto it = callback_ids_.find("client-disconnected"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.client_disconnected = [id](int client_index) {
                lua_callbacks_enqueue(id, [client_index](sol::state_view lua) {
                    sol::table payload = lua.create_table();
                    payload["client-index"] = client_index;
                    return sol::make_object(lua, payload);
                });
            };
        }
        if (auto it = callback_ids_.find("feature-activated"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.feature_activated = [id](int client_index, uint16_t feature_id) {
                lua_callbacks_enqueue(id, [client_index, feature_id](sol::state_view lua) {
                    sol::table payload = lua.create_table();
                    payload["client-index"] = client_index;
                    payload["feature-id"] = feature_id;
                    return sol::make_object(lua, payload);
                });
            };
        }
        if (auto it = callback_ids_.find("feature-deactivated"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.feature_deactivated = [id](int client_index, uint16_t feature_id) {
                lua_callbacks_enqueue(id, [client_index, feature_id](sol::state_view lua) {
                    sol::table payload = lua.create_table();
                    payload["client-index"] = client_index;
                    payload["feature-id"] = feature_id;
                    return sol::make_object(lua, payload);
                });
            };
        }
        if (auto it = callback_ids_.find("message"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.message = [id](int client_index, uint16_t feature_id, const std::string& payload_bytes) {
                lua_callbacks_enqueue(id, [client_index, feature_id, payload_bytes](sol::state_view lua) {
                    sol::table payload = lua.create_table();
                    payload["client-index"] = client_index;
                    payload["feature-id"] = feature_id;
                    payload["payload"] = payload_bytes;
                    return sol::make_object(lua, payload);
                });
            };
        }
        if (auto it = callback_ids_.find("error"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.error = [id](const std::string& error) {
                lua_callbacks_enqueue(id, [error](sol::state_view lua) {
                    sol::table payload = lua.create_table();
                    payload["message"] = error;
                    return sol::make_object(lua, payload);
                });
            };
        }

        server_->set_callbacks(std::move(callbacks));
    }

    std::shared_ptr<RealtimeServer> server_;
    lua_State* lua_state_ { nullptr };
    std::unordered_map<std::string, uint64_t> callback_ids_;
    bool closing_ { false };
    bool closed_ { false };
};

class LuaRealtimeClient
{
public:
    LuaRealtimeClient(std::shared_ptr<RealtimeClient> client, lua_State* lua_state)
        : client_(std::move(client))
        , lua_state_(lua_state)
    {
    }

    ~LuaRealtimeClient()
    {
        close_impl(false);
    }

    void ensure_queryable() const
    {
        if (closed_) {
            throw sol::error("realtime client is closed");
        }
    }

    void ensure_operational() const
    {
        ensure_queryable();
        if (closing_) {
            throw sol::error("realtime client is closing");
        }
    }

    void set_callback(const std::string& name, sol::function fn)
    {
        ensure_operational();
        ensure_known_callback_name("client",
                                   name,
                                   { "connected",
                                     "disconnected",
                                     "feature-offered",
                                     "feature-activated",
                                     "feature-deactivated",
                                     "message",
                                     "error" });
        auto it = callback_ids_.find(name);
        if (it != callback_ids_.end()) {
            lua_callbacks_unregister(it->second);
        }
        callback_ids_[name] = lua_callbacks_register(std::move(fn));
        refresh_callbacks();
    }

    void connect(sol::table opts)
    {
        ensure_operational();
        uint64_t client_id = opts.get_or<uint64_t>("client-id", 0);
        std::string connect_token = opts.get_or<std::string>("connect-token", "");
        if (client_id == 0) {
            throw sol::error("realtime client connect requires client-id");
        }
        if (connect_token.empty()) {
            throw sol::error("realtime client connect requires connect-token");
        }
        client_->connect(client_id, hex_decode(connect_token));
    }

    void close()
    {
        close_impl(true);
    }

    bool is_connected() const
    {
        ensure_queryable();
        return client_->is_connected();
    }

    void send_reliable(uint16_t feature_id, const std::string& payload)
    {
        ensure_operational();
        client_->send_reliable(feature_id, payload);
    }

    void send_unreliable(uint16_t feature_id, const std::string& payload)
    {
        ensure_operational();
        client_->send_unreliable(feature_id, payload);
    }

private:
    void close_impl(bool dispatch_callbacks)
    {
        if (closed_ || closing_) {
            return;
        }

        closing_ = true;
        client_->close();

        std::vector<uint64_t> ids = callback_id_list();
        if (dispatch_callbacks && lua_state_) {
            sol::state_view lua(lua_state_);
            while (lua_callbacks_dispatch_ids(lua, ids) > 0) {
            }
        }
        lua_callbacks_retire_ids(ids);

        for (uint64_t id : ids) {
            lua_callbacks_unregister(id);
        }
        callback_ids_.clear();
        closed_ = true;
        closing_ = false;
    }

    std::vector<uint64_t> callback_id_list() const
    {
        std::vector<uint64_t> ids;
        ids.reserve(callback_ids_.size());
        for (const auto& [name, id] : callback_ids_) {
            (void)name;
            ids.push_back(id);
        }
        return ids;
    }

    void refresh_callbacks()
    {
        ClientCallbacks callbacks;

        if (auto it = callback_ids_.find("connected"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.connected = [id]() {
                lua_callbacks_enqueue(id, [](sol::state_view lua) {
                    return sol::make_object(lua, lua.create_table());
                });
            };
        }
        if (auto it = callback_ids_.find("disconnected"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.disconnected = [id]() {
                lua_callbacks_enqueue(id, [](sol::state_view lua) {
                    return sol::make_object(lua, lua.create_table());
                });
            };
        }
        if (auto it = callback_ids_.find("feature-offered"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.feature_offered = [id](uint16_t feature_id, uint16_t version, const std::string& name) {
                lua_callbacks_enqueue(id, [feature_id, version, name](sol::state_view lua) {
                    sol::table payload = lua.create_table();
                    payload["feature-id"] = feature_id;
                    payload["version"] = version;
                    payload["name"] = name;
                    return sol::make_object(lua, payload);
                });
            };
        }
        if (auto it = callback_ids_.find("feature-activated"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.feature_activated = [id](uint16_t feature_id) {
                lua_callbacks_enqueue(id, [feature_id](sol::state_view lua) {
                    sol::table payload = lua.create_table();
                    payload["feature-id"] = feature_id;
                    return sol::make_object(lua, payload);
                });
            };
        }
        if (auto it = callback_ids_.find("feature-deactivated"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.feature_deactivated = [id](uint16_t feature_id) {
                lua_callbacks_enqueue(id, [feature_id](sol::state_view lua) {
                    sol::table payload = lua.create_table();
                    payload["feature-id"] = feature_id;
                    return sol::make_object(lua, payload);
                });
            };
        }
        if (auto it = callback_ids_.find("message"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.message = [id](uint16_t feature_id, const std::string& payload_bytes) {
                lua_callbacks_enqueue(id, [feature_id, payload_bytes](sol::state_view lua) {
                    sol::table payload = lua.create_table();
                    payload["feature-id"] = feature_id;
                    payload["payload"] = payload_bytes;
                    return sol::make_object(lua, payload);
                });
            };
        }
        if (auto it = callback_ids_.find("error"); it != callback_ids_.end()) {
            const uint64_t id = it->second;
            callbacks.error = [id](const std::string& error) {
                lua_callbacks_enqueue(id, [error](sol::state_view lua) {
                    sol::table payload = lua.create_table();
                    payload["message"] = error;
                    return sol::make_object(lua, payload);
                });
            };
        }

        client_->set_callbacks(std::move(callbacks));
    }

    std::shared_ptr<RealtimeClient> client_;
    lua_State* lua_state_ { nullptr };
    std::unordered_map<std::string, uint64_t> callback_ids_;
    bool closing_ { false };
    bool closed_ { false };
};

sol::table create_realtime_table(sol::state_view lua)
{
    sol::table realtime = lua.create_table();

    realtime.new_usertype<FeatureRegistry>("FeatureRegistry",
        sol::constructors<FeatureRegistry()>(),
        "register-feature", [](FeatureRegistry& registry, sol::table opts) {
            FeatureDefinition feature;
            feature.id = opts.get_or<uint16_t>("id", 0);
            feature.version = opts.get_or<uint16_t>("version", 1);
            feature.name = opts.get_or<std::string>("name", "");
            registry.register_feature(feature);
        },
        "list-features", [](FeatureRegistry& registry, sol::this_state ts) {
            sol::state_view state(ts);
            sol::table out = state.create_table();
            int index = 1;
            for (const auto& feature : registry.list_features()) {
                sol::table item = state.create_table();
                item["id"] = feature.id;
                item["version"] = feature.version;
                item["name"] = feature.name;
                out[index++] = item;
            }
            return out;
        });

    realtime.new_usertype<RealtimeService>("RealtimeService",
        sol::constructors<RealtimeService()>(),
        "create-feature-registry", &RealtimeService::create_feature_registry,
        "create-server", [](sol::this_state ts, RealtimeService& service, sol::table opts) {
            sol::state_view lua(ts);
            auto registry = opts.get<std::shared_ptr<FeatureRegistry>>("registry");
            std::string bind_address = opts.get_or<std::string>("bind-address", "127.0.0.1:0");
            int max_clients = opts["max-clients"].get_or(8);
            std::string auth_scope = opts.get_or<std::string>("server-scope", "");
            std::vector<std::string> connect_addresses;
            if (sol::optional<sol::table> connect_addresses_table = opts["connect-addresses"]) {
                connect_addresses = parse_string_list(*connect_addresses_table);
            }
            return std::make_shared<LuaRealtimeServer>(service.create_server(registry,
                                                                             bind_address,
                                                                             max_clients,
                                                                             auth_scope,
                                                                             std::move(connect_addresses)),
                                                       lua.lua_state());
        },
        "create-client", [](sol::this_state ts, RealtimeService& service, sol::table opts) {
            sol::state_view lua(ts);
            auto registry = opts.get<std::shared_ptr<FeatureRegistry>>("registry");
            std::string bind_address = opts.get_or<std::string>("bind-address", "0.0.0.0:0");
            return std::make_shared<LuaRealtimeClient>(service.create_client(registry, bind_address),
                                                       lua.lua_state());
        });

    realtime.new_usertype<LuaRealtimeServer>("RealtimeServer",
        sol::no_constructor,
        "set-callback", &LuaRealtimeServer::set_callback,
        "start", &LuaRealtimeServer::start,
        "close", &LuaRealtimeServer::close,
        "is-running", &LuaRealtimeServer::is_running,
        "address", &LuaRealtimeServer::address,
        "create-connect-token", &LuaRealtimeServer::create_connect_token,
        "activate-feature", &LuaRealtimeServer::activate_feature,
        "deactivate-feature", &LuaRealtimeServer::deactivate_feature,
        "send-reliable", &LuaRealtimeServer::send_reliable,
        "send-unreliable", &LuaRealtimeServer::send_unreliable,
        "broadcast-reliable", &LuaRealtimeServer::broadcast_reliable,
        "broadcast-unreliable", &LuaRealtimeServer::broadcast_unreliable);

    realtime.new_usertype<LuaRealtimeClient>("RealtimeClient",
        sol::no_constructor,
        "set-callback", &LuaRealtimeClient::set_callback,
        "connect", &LuaRealtimeClient::connect,
        "close", &LuaRealtimeClient::close,
        "is-connected", &LuaRealtimeClient::is_connected,
        "send-reliable", &LuaRealtimeClient::send_reliable,
        "send-unreliable", &LuaRealtimeClient::send_unreliable);

    realtime["available"] = true;
    realtime.set_function("version", []() {
        return space::realtime::yojimbo_version_string();
    });
    realtime.set_function("Service", []() {
        return RealtimeService();
    });
    realtime.set_function("FeatureRegistry", []() {
        return std::make_shared<FeatureRegistry>();
    });
    realtime.set_function("make-dev-ticket", [](sol::this_state ts, sol::table opts) {
        sol::state_view lua(ts);
        std::string secret = opts.get_or<std::string>("secret", "");
        if (secret.empty()) {
            throw sol::error("realtime.make-dev-ticket requires secret");
        }
        return signed_auth_ticket_to_lua(lua, make_dev_auth_ticket(auth_ticket_from_lua(opts), secret));
    });
    realtime.set_function("verify-dev-ticket", [](sol::this_state ts, sol::table opts) {
        sol::state_view lua(ts);
        std::string payload_json = opts.get_or<std::string>("payload-json", "");
        std::string signature = opts.get_or<std::string>("signature", "");
        std::string secret = opts.get_or<std::string>("secret", "");
        if (payload_json.empty()) {
            throw sol::error("realtime.verify-dev-ticket requires payload-json");
        }
        if (signature.empty()) {
            throw sol::error("realtime.verify-dev-ticket requires signature");
        }
        if (secret.empty()) {
            throw sol::error("realtime.verify-dev-ticket requires secret");
        }
        std::optional<int64_t> now;
        if (sol::optional<int64_t> now_opt = opts["now"]) {
            now = *now_opt;
        }
        const VerifiedAuthTicket verified_ticket = verify_dev_auth_ticket(payload_json, signature, secret, now);
        SignedAuthTicket signed_ticket;
        signed_ticket.ticket = verified_ticket.ticket();
        signed_ticket.payload_json = payload_json;
        signed_ticket.signature_hex = signature;
        return signed_auth_ticket_to_lua(lua, signed_ticket);
    });

    return realtime;
}

} // namespace

void lua_bind_realtime(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("realtime", [](sol::this_state state) {
        sol::state_view lua_view(state);
        return create_realtime_table(lua_view);
    });
}
