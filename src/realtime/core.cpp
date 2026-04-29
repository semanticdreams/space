#include "realtime/core.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstring>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <ctime>
#include <unordered_set>
#include <utility>
#include <vector>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

extern "C" {
#include "netcode.h"
}

#include "yojimbo.h"

namespace space::realtime {
namespace {

constexpr uint64_t kProtocolId = 0x5350414345525401ULL;
constexpr int kReliableChannel = 0;
constexpr int kUnreliableChannel = 1;
constexpr int kMaxPayloadBytes = 1024;

enum class ControlAction : uint8_t
{
    Offer = 1,
    Activate = 2,
    Deactivate = 3,
};

enum MessageType
{
    CONTROL_MESSAGE = 0,
    PAYLOAD_MESSAGE = 1,
    NUM_REALTIME_MESSAGE_TYPES = 2,
};

class ControlMessage : public yojimbo::Message
{
public:
    uint8_t action { 0 };
    uint16_t feature_id { 0 };
    uint16_t feature_version { 0 };

    template <typename Stream> bool Serialize(Stream& stream)
    {
        int action_value = static_cast<int>(action);
        int feature_id_value = static_cast<int>(feature_id);
        int feature_version_value = static_cast<int>(feature_version);
        serialize_int(stream, action_value, 0, 255);
        serialize_int(stream, feature_id_value, 0, 65535);
        serialize_int(stream, feature_version_value, 0, 65535);
        action = static_cast<uint8_t>(action_value);
        feature_id = static_cast<uint16_t>(feature_id_value);
        feature_version = static_cast<uint16_t>(feature_version_value);
        return true;
    }

    YOJIMBO_VIRTUAL_SERIALIZE_FUNCTIONS()
};

class PayloadMessage : public yojimbo::Message
{
public:
    uint16_t feature_id { 0 };
    int payload_bytes { 0 };
    uint8_t payload[kMaxPayloadBytes] {};

    template <typename Stream> bool Serialize(Stream& stream)
    {
        int feature_id_value = static_cast<int>(feature_id);
        serialize_int(stream, feature_id_value, 0, 65535);
        serialize_int(stream, payload_bytes, 0, kMaxPayloadBytes);
        serialize_bytes(stream, payload, payload_bytes);
        feature_id = static_cast<uint16_t>(feature_id_value);
        return true;
    }

    YOJIMBO_VIRTUAL_SERIALIZE_FUNCTIONS()
};

YOJIMBO_MESSAGE_FACTORY_START(RealtimeMessageFactory, NUM_REALTIME_MESSAGE_TYPES);
YOJIMBO_DECLARE_MESSAGE_TYPE(CONTROL_MESSAGE, ControlMessage);
YOJIMBO_DECLARE_MESSAGE_TYPE(PAYLOAD_MESSAGE, PayloadMessage);
YOJIMBO_MESSAGE_FACTORY_FINISH();

class RealtimeConnectionConfig : public yojimbo::ClientServerConfig
{
public:
    RealtimeConnectionConfig()
    {
        protocolId = kProtocolId;
        networkSimulator = false;
        timeout = 10;
        numChannels = 2;
        channel[kReliableChannel].type = yojimbo::CHANNEL_TYPE_RELIABLE_ORDERED;
        channel[kReliableChannel].maxBlockSize = 16 * 1024;
        channel[kUnreliableChannel].type = yojimbo::CHANNEL_TYPE_UNRELIABLE_UNORDERED;
        channel[kUnreliableChannel].maxBlockSize = kMaxPayloadBytes;
    }
};

template <typename Set>
bool feature_set_insert(Set& set, uint16_t feature_id)
{
    return set.insert(feature_id).second;
}

template <typename Set>
bool feature_set_erase(Set& set, uint16_t feature_id)
{
    return set.erase(feature_id) > 0;
}

std::string describe_exception(std::exception_ptr exception)
{
    if (!exception) {
        return "unknown exception";
    }
    try {
        std::rethrow_exception(exception);
    } catch (const std::exception& e) {
        return e.what();
    } catch (...) {
        return "non-std exception";
    }
}

void report_callback_failure(const std::function<void(const std::string&)>& error_callback,
                             const std::string& context,
                             std::exception_ptr exception) noexcept
{
    const std::string message = context + ": " + describe_exception(exception);
    if (error_callback) {
        try {
            error_callback(message);
            return;
        } catch (...) {
            std::cerr << "[realtime] error callback failed while reporting '" << message
                      << "': " << describe_exception(std::current_exception()) << "\n";
            return;
        }
    }
    std::cerr << "[realtime] " << message << "\n";
}

template <typename Callback>
void invoke_callback_guarded(Callback&& callback,
                             const std::function<void(const std::string&)>& error_callback,
                             const std::string& context) noexcept
{
    try {
        callback();
    } catch (...) {
        report_callback_failure(error_callback, context, std::current_exception());
    }
}

std::mutex g_library_mutex;
int g_library_refs = 0;
constexpr uint8_t kAuthTicketEncodingVersion = 1;

void retain_library()
{
    std::lock_guard<std::mutex> lock(g_library_mutex);
    if (g_library_refs == 0) {
        if (!InitializeYojimbo()) {
            throw std::runtime_error("failed to initialize yojimbo");
        }
    }
    g_library_refs++;
}

void release_library()
{
    std::lock_guard<std::mutex> lock(g_library_mutex);
    if (g_library_refs <= 0) {
        return;
    }
    g_library_refs--;
    if (g_library_refs == 0) {
        ShutdownYojimbo();
    }
}

void append_u8(std::vector<uint8_t>& out, uint8_t value)
{
    out.push_back(value);
}

void append_u16(std::vector<uint8_t>& out, uint16_t value)
{
    out.push_back(static_cast<uint8_t>(value & 0xff));
    out.push_back(static_cast<uint8_t>((value >> 8) & 0xff));
}

void append_u64(std::vector<uint8_t>& out, uint64_t value)
{
    for (int shift = 0; shift < 64; shift += 8) {
        out.push_back(static_cast<uint8_t>((value >> shift) & 0xff));
    }
}

uint8_t read_u8(const std::vector<uint8_t>& data, size_t& offset)
{
    if (offset >= data.size()) {
        throw std::runtime_error("auth ticket payload truncated");
    }
    return data[offset++];
}

uint16_t read_u16(const std::vector<uint8_t>& data, size_t& offset)
{
    if (offset + 2 > data.size()) {
        throw std::runtime_error("auth ticket payload truncated");
    }
    const uint16_t value = static_cast<uint16_t>(data[offset])
                           | (static_cast<uint16_t>(data[offset + 1]) << 8);
    offset += 2;
    return value;
}

uint64_t read_u64(const std::vector<uint8_t>& data, size_t& offset)
{
    if (offset + 8 > data.size()) {
        throw std::runtime_error("auth ticket payload truncated");
    }
    uint64_t value = 0;
    for (int shift = 0; shift < 64; shift += 8) {
        value |= static_cast<uint64_t>(data[offset++]) << shift;
    }
    return value;
}

std::string read_auth_ticket_string(const std::vector<uint8_t>& data, size_t& offset, uint8_t length)
{
    if (offset + length > data.size()) {
        throw std::runtime_error("auth ticket payload truncated");
    }
    std::string value(reinterpret_cast<const char*>(data.data() + offset), length);
    offset += length;
    return value;
}

std::array<uint8_t, NETCODE_USER_DATA_BYTES> encode_auth_ticket(const AuthTicket& ticket)
{
    validate_auth_ticket(ticket);
    if (ticket.ticket_id.size() > 255 || ticket.subject_user_id.size() > 255 || ticket.server_scope.size() > 255) {
        throw std::runtime_error("auth ticket string fields exceed transport limits");
    }
    if (ticket.allowed_features.size() > 255) {
        throw std::runtime_error("auth ticket allowed-features exceed transport limits");
    }

    std::vector<uint8_t> payload;
    payload.reserve(32 + ticket.allowed_features.size() * 2
                    + ticket.ticket_id.size()
                    + ticket.subject_user_id.size()
                    + ticket.server_scope.size());
    append_u8(payload, kAuthTicketEncodingVersion);
    append_u8(payload, static_cast<uint8_t>(ticket.ticket_id.size()));
    append_u8(payload, static_cast<uint8_t>(ticket.subject_user_id.size()));
    append_u8(payload, static_cast<uint8_t>(ticket.server_scope.size()));
    append_u8(payload, static_cast<uint8_t>(ticket.allowed_features.size()));
    append_u64(payload, ticket.client_id);
    append_u64(payload, static_cast<uint64_t>(ticket.issued_at));
    append_u64(payload, static_cast<uint64_t>(ticket.expires_at));
    for (uint16_t feature_id : ticket.allowed_features) {
        append_u16(payload, feature_id);
    }
    payload.insert(payload.end(), ticket.ticket_id.begin(), ticket.ticket_id.end());
    payload.insert(payload.end(), ticket.subject_user_id.begin(), ticket.subject_user_id.end());
    payload.insert(payload.end(), ticket.server_scope.begin(), ticket.server_scope.end());

    if (payload.size() > NETCODE_USER_DATA_BYTES - 2) {
        throw std::runtime_error("auth ticket too large for connect token user-data");
    }

    std::array<uint8_t, NETCODE_USER_DATA_BYTES> bytes {};
    const uint16_t payload_size = static_cast<uint16_t>(payload.size());
    bytes[0] = static_cast<uint8_t>(payload_size & 0xff);
    bytes[1] = static_cast<uint8_t>((payload_size >> 8) & 0xff);
    if (!payload.empty()) {
        std::memcpy(bytes.data() + 2, payload.data(), payload.size());
    }
    return bytes;
}

AuthTicket decode_auth_ticket(const uint8_t* user_data)
{
    if (!user_data) {
        throw std::runtime_error("missing auth ticket user-data");
    }

    const uint16_t payload_size = static_cast<uint16_t>(user_data[0])
                                  | (static_cast<uint16_t>(user_data[1]) << 8);
    if (payload_size == 0) {
        throw std::runtime_error("missing auth ticket payload");
    }
    if (payload_size > NETCODE_USER_DATA_BYTES - 2) {
        throw std::runtime_error("auth ticket payload exceeds transport limits");
    }

    std::vector<uint8_t> payload(payload_size);
    std::memcpy(payload.data(), user_data + 2, payload_size);

    size_t offset = 0;
    const uint8_t version = read_u8(payload, offset);
    if (version != kAuthTicketEncodingVersion) {
        throw std::runtime_error("unsupported auth ticket encoding version");
    }

    const uint8_t ticket_id_size = read_u8(payload, offset);
    const uint8_t subject_user_id_size = read_u8(payload, offset);
    const uint8_t server_scope_size = read_u8(payload, offset);
    const uint8_t feature_count = read_u8(payload, offset);

    AuthTicket ticket;
    ticket.client_id = read_u64(payload, offset);
    ticket.issued_at = static_cast<int64_t>(read_u64(payload, offset));
    ticket.expires_at = static_cast<int64_t>(read_u64(payload, offset));
    ticket.allowed_features.reserve(feature_count);
    for (uint8_t i = 0; i < feature_count; ++i) {
        ticket.allowed_features.push_back(read_u16(payload, offset));
    }
    ticket.ticket_id = read_auth_ticket_string(payload, offset, ticket_id_size);
    ticket.subject_user_id = read_auth_ticket_string(payload, offset, subject_user_id_size);
    ticket.server_scope = read_auth_ticket_string(payload, offset, server_scope_size);

    if (offset != payload.size()) {
        throw std::runtime_error("auth ticket payload has trailing bytes");
    }

    validate_auth_ticket(ticket);
    return ticket;
}

std::string address_to_string(const yojimbo::Address& address)
{
    char buffer[yojimbo::MaxAddressLength] {};
    address.ToString(buffer, sizeof(buffer));
    return std::string(buffer);
}

bool feature_set_contains(const std::unordered_set<uint16_t>& features, uint16_t feature_id)
{
    return features.find(feature_id) != features.end();
}

bool feature_allowed_by_ticket(const AuthTicket& ticket, uint16_t feature_id)
{
    return std::binary_search(ticket.allowed_features.begin(), ticket.allowed_features.end(), feature_id);
}

void validate_bind_address(const std::string& bind_address)
{
    yojimbo::Address address(bind_address.c_str());
    if (!address.IsValid()) {
        throw std::runtime_error("invalid realtime server bind address: " + bind_address);
    }
}

yojimbo::Address parse_address(const std::string& address_text, const std::string& context)
{
    yojimbo::Address address(address_text.c_str());
    if (!address.IsValid()) {
        throw std::runtime_error("invalid realtime " + context + " address: " + address_text);
    }
    return address;
}

bool address_is_wildcard(const yojimbo::Address& address)
{
    if (address.GetType() == yojimbo::ADDRESS_IPV4) {
        const uint8_t* bytes = address.GetAddress4();
        return bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0;
    }
    if (address.GetType() == yojimbo::ADDRESS_IPV6) {
        const uint16_t* bytes = address.GetAddress6();
        for (int i = 0; i < 8; ++i) {
            if (bytes[i] != 0) {
                return false;
            }
        }
        return true;
    }
    return false;
}

std::string address_family_name(yojimbo::AddressType type)
{
    switch (type) {
        case yojimbo::ADDRESS_IPV4:
            return "IPv4";
        case yojimbo::ADDRESS_IPV6:
            return "IPv6";
        default:
            return "unknown";
    }
}

void validate_max_clients(int max_clients)
{
    if (max_clients <= 0 || max_clients > yojimbo::MaxClients) {
        throw std::runtime_error("realtime max-clients must be in range [1,"
                                 + std::to_string(yojimbo::MaxClients) + "]");
    }
}

void validate_registry(const std::shared_ptr<FeatureRegistry>& registry, const char* owner_kind)
{
    if (!registry) {
        throw std::runtime_error(std::string("realtime ") + owner_kind + " requires a feature registry");
    }
}

void validate_connect_addresses(const yojimbo::Address& bind_address, const std::vector<std::string>& connect_addresses)
{
    for (const auto& address_text : connect_addresses) {
        const yojimbo::Address address = parse_address(address_text, "server connect");
        if (address_is_wildcard(address)) {
            throw std::runtime_error("realtime connect-address must not use a wildcard host: " + address_text);
        }
        if (address.GetType() != bind_address.GetType()) {
            throw std::runtime_error("realtime connect-address family mismatch: bind "
                                     + address_family_name(bind_address.GetType())
                                     + " connect " + address_family_name(address.GetType()));
        }
    }
}

void validate_client_index(int client_index, int max_clients, bool allow_broadcast)
{
    if (allow_broadcast && client_index == -1) {
        return;
    }
    if (client_index < 0 || client_index >= max_clients) {
        throw std::runtime_error("realtime client-index out of range: " + std::to_string(client_index));
    }
}

} // namespace

void FeatureRegistry::register_feature(const FeatureDefinition& feature)
{
    if (feature.id == 0) {
        throw std::runtime_error("feature id must be non-zero");
    }
    if (feature.name.empty()) {
        throw std::runtime_error("feature name must be non-empty");
    }

    std::lock_guard<std::mutex> lock(mutex_);
    if (features_.find(feature.id) != features_.end()) {
        throw std::runtime_error("feature id already registered: " + std::to_string(feature.id));
    }
    features_.emplace(feature.id, feature);
}

std::vector<FeatureDefinition> FeatureRegistry::list_features() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    std::vector<FeatureDefinition> out;
    out.reserve(features_.size());
    for (const auto& entry : features_) {
        out.push_back(entry.second);
    }
    std::sort(out.begin(), out.end(), [](const FeatureDefinition& a, const FeatureDefinition& b) {
        return a.id < b.id;
    });
    return out;
}

std::optional<FeatureDefinition> FeatureRegistry::find_feature(uint16_t id) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = features_.find(id);
    if (it == features_.end()) {
        return std::nullopt;
    }
    return it->second;
}


class RealtimeServerAdapter : public yojimbo::Adapter
{
public:
    explicit RealtimeServerAdapter(RealtimeServer::Impl* owner)
        : owner_(owner)
    {
    }

    yojimbo::MessageFactory* CreateMessageFactory(yojimbo::Allocator& allocator) override
    {
        return YOJIMBO_NEW(allocator, RealtimeMessageFactory, allocator);
    }

    void OnServerClientConnected(int clientIndex) override;
    void OnServerClientDisconnected(int clientIndex) override;

private:
    RealtimeServer::Impl* owner_ { nullptr };
};

class RealtimeClientAdapter : public yojimbo::Adapter
{
public:
    yojimbo::MessageFactory* CreateMessageFactory(yojimbo::Allocator& allocator) override
    {
        return YOJIMBO_NEW(allocator, RealtimeMessageFactory, allocator);
    }
};

struct RealtimeServer::Impl
{
    struct Command
    {
        enum class Type
        {
            ActivateFeature,
            DeactivateFeature,
            SendPayload,
        };

        Type type { Type::SendPayload };
        int client_index { -1 };
        uint16_t feature_id { 0 };
        bool reliable { true };
        std::string payload;
    };

    explicit Impl(std::shared_ptr<FeatureRegistry> feature_registry,
                  std::string bind,
                  int client_slots,
                  std::string scope,
                  std::vector<std::string> advertised)
        : registry(std::move(feature_registry))
        , bind_address(std::move(bind))
        , max_clients(client_slots)
        , auth_scope(std::move(scope))
        , connect_addresses(std::move(advertised))
        , adapter(this)
    {
        validate_registry(registry, "server");
        validate_bind_address(bind_address);
        validate_max_clients(max_clients);
        validate_connect_addresses(parse_address(bind_address, "server bind"), connect_addresses);
        retain_library();
        yojimbo_random_bytes(private_key.data(), static_cast<int>(private_key.size()));
        server = std::make_unique<yojimbo::Server>(yojimbo::GetDefaultAllocator(),
                                                   private_key.data(),
                                                   yojimbo::Address(bind_address.c_str()),
                                                   connection_config,
                                                   adapter,
                                                   0.0);
    }

    ~Impl()
    {
        stop();
        release_library();
    }

    ServerCallbacks current_callbacks()
    {
        std::lock_guard<std::mutex> lock(callbacks_mutex);
        return callbacks;
    }

    std::vector<std::string> resolved_connect_addresses() const
    {
        if (bound_address.empty()) {
            throw std::runtime_error("realtime server connect addresses are unavailable before startup");
        }

        std::vector<std::string> resolved;
        resolved.reserve(connect_addresses.empty() ? 1 : connect_addresses.size());
        const yojimbo::Address bound = parse_address(bound_address, "server bound");
        if (connect_addresses.empty()) {
            if (address_is_wildcard(bound)) {
                throw std::runtime_error("realtime server create-connect-token requires connect-addresses for wildcard binds");
            }
            resolved.push_back(bound_address);
            return resolved;
        }

        for (const auto& configured : connect_addresses) {
            yojimbo::Address address = parse_address(configured, "server connect");
            if (address.GetPort() == 0) {
                address.SetPort(bound.GetPort());
            }
            char buffer[yojimbo::MaxAddressLength] {};
            address.ToString(buffer, sizeof(buffer));
            resolved.emplace_back(buffer);
        }
        return resolved;
    }

    std::string effective_auth_scope() const
    {
        if (!auth_scope.empty()) {
            return auth_scope;
        }
        if (!bound_address.empty()) {
            return bound_address;
        }
        throw std::runtime_error("realtime server auth scope is unavailable before startup");
    }

    void start()
    {
        if (running.load()) {
            return;
        }

        server->Start(max_clients);
        if (!server->IsRunning()) {
            throw std::runtime_error("failed to start realtime server");
        }

        const std::string started_bound_address = address_to_string(server->GetAddress());
        running.store(true);
        try {
            worker = std::thread([this]() { run_loop(); });
        } catch (...) {
            running.store(false);
            server->Stop();
            throw;
        }
        bound_address = started_bound_address;

        auto current = current_callbacks();
        if (current.started) {
            invoke_callback_guarded([&]() {
                current.started(bound_address);
            }, current.error, "realtime server started callback failed");
        }
    }

    void stop()
    {
        if (!running.exchange(false)) {
            std::lock_guard<std::mutex> lock(commands_mutex);
            commands.clear();
            return;
        }
        if (worker.joinable()) {
            worker.join();
        }
        {
            std::lock_guard<std::mutex> lock(commands_mutex);
            commands.clear();
        }
        active_features.clear();
        client_auth_tickets.clear();

        auto current = current_callbacks();
        if (current.stopped) {
            invoke_callback_guarded([&]() {
                current.stopped();
            }, current.error, "realtime server stopped callback failed");
        }
    }

    void run_loop()
    {
        using clock = std::chrono::steady_clock;
        constexpr double fixed_dt = 1.0 / 60.0;
        auto next_tick = clock::now();
        double time = 0.0;

        while (running.load()) {
            try {
                time += fixed_dt;
                server->AdvanceTime(time);
                server->ReceivePackets();
                process_commands();
                process_messages();
                server->SendPackets();
                next_tick += std::chrono::milliseconds(16);
                std::this_thread::sleep_until(next_tick);
            } catch (...) {
                auto current = current_callbacks();
                report_callback_failure(current.error, "realtime server worker failed", std::current_exception());
                running.store(false);
            }
        }

        server->Stop();
    }

    void on_client_connected(int client_index)
    {
        AuthTicket auth_ticket;
        try {
            auth_ticket = decode_auth_ticket(server->GetClientUserData(client_index));
        } catch (const std::exception& e) {
            auto current = current_callbacks();
            if (current.error) {
                current.error("client connected with invalid auth ticket: " + std::string(e.what()));
            }
            server->DisconnectClient(client_index);
            return;
        }

        const uint64_t client_id = server->GetClientId(client_index);
        if (auth_ticket.client_id != client_id) {
            auto current = current_callbacks();
            if (current.error) {
                current.error("client auth ticket client-id mismatch: ticket "
                              + std::to_string(auth_ticket.client_id)
                              + " transport " + std::to_string(client_id));
            }
            server->DisconnectClient(client_index);
            return;
        }
        if (auth_ticket.server_scope != effective_auth_scope()) {
            auto current = current_callbacks();
            if (current.error) {
                current.error("client auth ticket server-scope mismatch: ticket '"
                              + auth_ticket.server_scope
                              + "' server '" + effective_auth_scope() + "'");
            }
            server->DisconnectClient(client_index);
            return;
        }

        client_auth_tickets[client_index] = auth_ticket;
        auto current = current_callbacks();
        if (current.client_connected) {
            invoke_callback_guarded([&]() {
                current.client_connected(client_index, client_id, auth_ticket);
            }, current.error, "realtime server client-connected callback failed");
        }

        for (const auto& feature : registry->list_features()) {
            if (!feature_allowed_by_ticket(auth_ticket, feature.id)) {
                continue;
            }
            auto* message = static_cast<ControlMessage*>(server->CreateMessage(client_index, CONTROL_MESSAGE));
            message->action = static_cast<uint8_t>(ControlAction::Offer);
            message->feature_id = feature.id;
            message->feature_version = feature.version;
            server->SendMessage(client_index, kReliableChannel, message);
        }
    }

    void on_client_disconnected(int client_index)
    {
        active_features.erase(client_index);
        client_auth_tickets.erase(client_index);
        auto current = current_callbacks();
        if (current.client_disconnected) {
            invoke_callback_guarded([&]() {
                current.client_disconnected(client_index);
            }, current.error, "realtime server client-disconnected callback failed");
        }
    }

    void process_commands()
    {
        std::vector<Command> pending;
        {
            std::lock_guard<std::mutex> lock(commands_mutex);
            pending.swap(commands);
        }

        for (auto& command : pending) {
            if (command.client_index >= 0 && !server->IsClientConnected(command.client_index)) {
                continue;
            }

            switch (command.type) {
                case Command::Type::ActivateFeature:
                    {
                        auto feature = registry->find_feature(command.feature_id);
                        if (!feature) {
                            break;
                        }
                        auto ticket_it = client_auth_tickets.find(command.client_index);
                        if (ticket_it == client_auth_tickets.end()) {
                            auto current = current_callbacks();
                            if (current.error) {
                                current.error("cannot activate feature for client without auth ticket");
                            }
                            break;
                        }
                        if (!feature_allowed_by_ticket(ticket_it->second, command.feature_id)) {
                            auto current = current_callbacks();
                            if (current.error) {
                                current.error("client auth ticket does not allow feature id "
                                              + std::to_string(command.feature_id));
                            }
                            break;
                        }
                        auto& client_features = active_features[command.client_index];
                        if (!feature_set_insert(client_features, command.feature_id)) {
                            break;
                        }
                        auto* message = static_cast<ControlMessage*>(server->CreateMessage(command.client_index, CONTROL_MESSAGE));
                        message->action = static_cast<uint8_t>(ControlAction::Activate);
                        message->feature_id = command.feature_id;
                        message->feature_version = feature->version;
                        server->SendMessage(command.client_index, kReliableChannel, message);
                        auto current = current_callbacks();
                        if (current.feature_activated) {
                            invoke_callback_guarded([&]() {
                                current.feature_activated(command.client_index, command.feature_id);
                            }, current.error, "realtime server feature-activated callback failed");
                        }
                    }
                    break;

                case Command::Type::DeactivateFeature:
                    {
                        if (!registry->find_feature(command.feature_id)) {
                            auto current = current_callbacks();
                            if (current.error) {
                                current.error("cannot deactivate unknown feature id "
                                              + std::to_string(command.feature_id));
                            }
                            break;
                        }
                        auto active_it = active_features.find(command.client_index);
                        if (active_it == active_features.end()
                            || !feature_set_erase(active_it->second, command.feature_id)) {
                            break;
                        }
                        if (active_it->second.empty()) {
                            active_features.erase(active_it);
                        }
                        {
                            auto* message = static_cast<ControlMessage*>(server->CreateMessage(command.client_index, CONTROL_MESSAGE));
                            message->action = static_cast<uint8_t>(ControlAction::Deactivate);
                            message->feature_id = command.feature_id;
                            message->feature_version = 0;
                            server->SendMessage(command.client_index, kReliableChannel, message);
                        }
                        {
                            auto current = current_callbacks();
                            if (current.feature_deactivated) {
                                invoke_callback_guarded([&]() {
                                    current.feature_deactivated(command.client_index, command.feature_id);
                                }, current.error, "realtime server feature-deactivated callback failed");
                            }
                        }
                    }
                    break;

                case Command::Type::SendPayload:
                    send_payload(command.client_index, command.feature_id, command.payload, command.reliable);
                    break;
            }
        }
    }

    void send_payload(int client_index, uint16_t feature_id, const std::string& payload, bool reliable)
    {
        if (!registry->find_feature(feature_id)) {
            auto current = current_callbacks();
            if (current.error) {
                current.error("cannot send payload for unknown feature id " + std::to_string(feature_id));
            }
            return;
        }
        if (payload.size() > kMaxPayloadBytes) {
            auto current = current_callbacks();
            if (current.error) {
                current.error("payload exceeds max size");
            }
            return;
        }

        auto send_to_client = [&](int index) {
            if (!server->IsClientConnected(index)) {
                return;
            }
            auto active_it = active_features.find(index);
            if (active_it == active_features.end() || !feature_set_contains(active_it->second, feature_id)) {
                return;
            }
            auto* message = static_cast<PayloadMessage*>(server->CreateMessage(index, PAYLOAD_MESSAGE));
            message->feature_id = feature_id;
            message->payload_bytes = static_cast<int>(payload.size());
            if (!payload.empty()) {
                std::memcpy(message->payload, payload.data(), payload.size());
            }
            server->SendMessage(index, reliable ? kReliableChannel : kUnreliableChannel, message);
        };

        if (client_index >= 0) {
            send_to_client(client_index);
            return;
        }

        for (int index = 0; index < max_clients; ++index) {
            send_to_client(index);
        }
    }

    void process_messages()
    {
        for (int client_index = 0; client_index < max_clients; ++client_index) {
            if (!server->IsClientConnected(client_index)) {
                continue;
            }
            for (int channel_index = 0; channel_index < connection_config.numChannels; ++channel_index) {
                yojimbo::Message* incoming = server->ReceiveMessage(client_index, channel_index);
                while (incoming != nullptr) {
                    if (incoming->GetType() == PAYLOAD_MESSAGE) {
                        auto* payload = static_cast<PayloadMessage*>(incoming);
                        auto active_it = active_features.find(client_index);
                        if (active_it != active_features.end()
                            && feature_set_contains(active_it->second, payload->feature_id)) {
                            auto current = current_callbacks();
                            if (current.message) {
                                const std::string payload_bytes(reinterpret_cast<const char*>(payload->payload),
                                                                static_cast<size_t>(payload->payload_bytes));
                                invoke_callback_guarded([&]() {
                                    current.message(client_index, payload->feature_id, payload_bytes);
                                }, current.error, "realtime server message callback failed");
                            }
                        }
                    }
                    server->ReleaseMessage(client_index, incoming);
                    incoming = server->ReceiveMessage(client_index, channel_index);
                }
            }
        }
    }

    std::string create_connect_token(const VerifiedAuthTicket& verified_auth_ticket,
                                     int expire_seconds,
                                     int timeout_seconds) const
    {
        const AuthTicket& auth_ticket = verified_auth_ticket.ticket();
        if (!running.load() || bound_address.empty()) {
            throw std::runtime_error("server must be running before creating connect tokens");
        }
        if (expire_seconds <= 0) {
            throw std::runtime_error("connect token expire-seconds must be positive");
        }
        if (timeout_seconds <= 0) {
            throw std::runtime_error("connect token timeout-seconds must be positive");
        }
        const int64_t current_time = static_cast<int64_t>(std::time(nullptr));
        if (current_time < auth_ticket.issued_at) {
            throw std::runtime_error("verified auth ticket is not valid yet");
        }
        if (current_time > auth_ticket.expires_at) {
            throw std::runtime_error("verified auth ticket has expired");
        }
        for (uint16_t feature_id : auth_ticket.allowed_features) {
            if (!registry->find_feature(feature_id)) {
                throw std::runtime_error("auth ticket allowed unknown feature id " + std::to_string(feature_id));
            }
        }
        if (auth_ticket.server_scope != effective_auth_scope()) {
            throw std::runtime_error("auth ticket server-scope mismatch: ticket '"
                                     + auth_ticket.server_scope
                                     + "' server '" + effective_auth_scope() + "'");
        }
        const int64_t remaining_lifetime = auth_ticket.expires_at - current_time;
        if (remaining_lifetime <= 0) {
            throw std::runtime_error("verified auth ticket has no remaining lifetime");
        }
        const int effective_expire_seconds = std::min<int64_t>(expire_seconds, remaining_lifetime);
        const int effective_timeout_seconds = std::min(timeout_seconds, effective_expire_seconds);

        auto encoded = encode_auth_ticket(auth_ticket);
        std::array<uint8_t, NETCODE_CONNECT_TOKEN_BYTES> token {};
        const std::vector<std::string> addresses = resolved_connect_addresses();
        std::vector<const char*> public_addresses;
        std::vector<const char*> internal_addresses;
        public_addresses.reserve(addresses.size());
        internal_addresses.reserve(addresses.size());
        for (const auto& address : addresses) {
            public_addresses.push_back(address.c_str());
            internal_addresses.push_back(bound_address.c_str());
        }
        const int result = netcode_generate_connect_token(static_cast<int>(public_addresses.size()),
                                                          public_addresses.data(),
                                                          internal_addresses.data(),
                                                          effective_expire_seconds,
                                                          effective_timeout_seconds,
                                                          auth_ticket.client_id,
                                                          connection_config.protocolId,
                                                          private_key.data(),
                                                          encoded.data(),
                                                          token.data());
        if (result != NETCODE_OK) {
            throw std::runtime_error("failed to generate connect token");
        }
        return std::string(reinterpret_cast<const char*>(token.data()), token.size());
    }

    std::shared_ptr<FeatureRegistry> registry;
    std::string bind_address;
    int max_clients { 0 };
    RealtimeConnectionConfig connection_config;
    std::array<uint8_t, yojimbo::KeyBytes> private_key {};
    RealtimeServerAdapter adapter;
    std::unique_ptr<yojimbo::Server> server;
    std::atomic<bool> running { false };
    std::thread worker;
    std::string bound_address;
    std::string auth_scope;
    std::vector<std::string> connect_addresses;
    std::mutex callbacks_mutex;
    ServerCallbacks callbacks;
    std::mutex commands_mutex;
    std::vector<Command> commands;
    std::unordered_map<int, std::unordered_set<uint16_t>> active_features;
    std::unordered_map<int, AuthTicket> client_auth_tickets;
};

struct RealtimeClient::Impl
{
    enum class LifecycleState
    {
        Idle,
        Connecting,
        Connected,
        Closed,
    };

    struct Command
    {
        enum class Type
        {
            Connect,
            Disconnect,
            SendPayload,
        };

        Type type { Type::Disconnect };
        uint64_t client_id { 0 };
        uint16_t feature_id { 0 };
        bool reliable { true };
        std::string connect_token;
        std::string payload;
    };

    explicit Impl(std::shared_ptr<FeatureRegistry> feature_registry, std::string bind)
        : registry(std::move(feature_registry))
        , bind_address(std::move(bind))
    {
        validate_registry(registry, "client");
        validate_bind_address(bind_address);
        retain_library();
        client = std::make_unique<yojimbo::Client>(yojimbo::GetDefaultAllocator(),
                                                   yojimbo::Address(bind_address.c_str()),
                                                   connection_config,
                                                   adapter,
                                                   0.0);
    }

    ~Impl()
    {
        close();
        release_library();
    }

    ClientCallbacks current_callbacks()
    {
        std::lock_guard<std::mutex> lock(callbacks_mutex);
        return callbacks;
    }

    void enqueue(Command command)
    {
        if (lifecycle.load() == LifecycleState::Closed) {
            throw std::runtime_error("realtime client is closed");
        }
        std::lock_guard<std::mutex> lock(commands_mutex);
        commands.push_back(std::move(command));
    }

    void start_worker()
    {
        if (lifecycle.load() == LifecycleState::Closed) {
            throw std::runtime_error("realtime client is closed");
        }
        bool expected = false;
        if (!running.compare_exchange_strong(expected, true)) {
            return;
        }
        try {
            worker = std::thread([this]() { run_loop(); });
        } catch (...) {
            running.store(false);
            throw;
        }
    }

    void rollback_connect_start()
    {
        connected.store(false);
        active_features.clear();
        {
            std::lock_guard<std::mutex> lock(commands_mutex);
            commands.clear();
        }
        if (running.exchange(false) && worker.joinable()) {
            worker.join();
        }
        if (client && !client->IsDisconnected()) {
            client->Disconnect();
        }
        if (lifecycle.load() != LifecycleState::Closed) {
            lifecycle.store(LifecycleState::Idle);
        }
    }

    void close()
    {
        if (lifecycle.exchange(LifecycleState::Closed) == LifecycleState::Closed) {
            return;
        }
        connected.store(false);
        if (running.exchange(false) && worker.joinable()) {
            worker.join();
        } else if (worker.joinable()) {
            worker.join();
        }
        {
            std::lock_guard<std::mutex> lock(commands_mutex);
            commands.clear();
        }
        if (client && !client->IsDisconnected()) {
            client->Disconnect();
        }
        client.reset();
        active_features.clear();
    }

    void run_loop()
    {
        using clock = std::chrono::steady_clock;
        constexpr double fixed_dt = 1.0 / 60.0;
        auto next_tick = clock::now();
        double time = 0.0;
        auto previous_state = client->GetClientState();

        while (running.load()) {
            try {
                time += fixed_dt;
                process_commands();
                client->AdvanceTime(time);
                client->ReceivePackets();
                if (client->IsConnected()) {
                    process_messages();
                }
                client->SendPackets();

                auto current_state = client->GetClientState();
                if (current_state != previous_state) {
                    auto current = current_callbacks();
                    if (current_state == yojimbo::CLIENT_STATE_CONNECTED) {
                        connected.store(true);
                        if (lifecycle.load() != LifecycleState::Closed) {
                            lifecycle.store(LifecycleState::Connected);
                        }
                        if (current.connected) {
                            invoke_callback_guarded([&]() {
                                current.connected();
                            }, current.error, "realtime client connected callback failed");
                        }
                    } else if (current_state <= yojimbo::CLIENT_STATE_DISCONNECTED
                               && previous_state == yojimbo::CLIENT_STATE_CONNECTED) {
                        connected.store(false);
                        active_features.clear();
                        if (lifecycle.load() != LifecycleState::Closed) {
                            lifecycle.store(LifecycleState::Idle);
                        }
                        if (current.disconnected) {
                            invoke_callback_guarded([&]() {
                                current.disconnected();
                            }, current.error, "realtime client disconnected callback failed");
                        }
                    } else if (current_state == yojimbo::CLIENT_STATE_DISCONNECTED
                               && previous_state == yojimbo::CLIENT_STATE_CONNECTING) {
                        connected.store(false);
                        active_features.clear();
                        if (lifecycle.load() != LifecycleState::Closed) {
                            lifecycle.store(LifecycleState::Idle);
                        }
                        if (current.error) {
                            invoke_callback_guarded([&]() {
                                current.error("client disconnected before connection completed");
                            }, {}, "realtime client error callback failed");
                        }
                    } else if (current_state == yojimbo::CLIENT_STATE_ERROR) {
                        connected.store(false);
                        active_features.clear();
                        if (lifecycle.load() != LifecycleState::Closed) {
                            lifecycle.store(LifecycleState::Idle);
                        }
                        if (current.error) {
                            invoke_callback_guarded([&]() {
                                current.error("client connection failed");
                            }, {}, "realtime client error callback failed");
                        }
                    }
                    previous_state = current_state;
                }

                next_tick += std::chrono::milliseconds(16);
                std::this_thread::sleep_until(next_tick);
            } catch (...) {
                connected.store(false);
                active_features.clear();
                if (lifecycle.load() != LifecycleState::Closed) {
                    lifecycle.store(LifecycleState::Idle);
                }
                auto current = current_callbacks();
                report_callback_failure(current.error, "realtime client worker failed", std::current_exception());
                running.store(false);
            }
        }

        client->Disconnect();
        if (lifecycle.load() != LifecycleState::Closed) {
            lifecycle.store(LifecycleState::Idle);
        }
    }

    void process_commands()
    {
        std::vector<Command> pending;
        {
            std::lock_guard<std::mutex> lock(commands_mutex);
            pending.swap(commands);
        }

        for (auto& command : pending) {
            switch (command.type) {
                case Command::Type::Connect:
                    client->Connect(command.client_id, reinterpret_cast<uint8_t*>(command.connect_token.data()));
                    break;

                case Command::Type::Disconnect:
                    client->Disconnect();
                    break;

                case Command::Type::SendPayload:
                    if (!registry->find_feature(command.feature_id)) {
                        auto current = current_callbacks();
                        if (current.error) {
                            current.error("cannot send payload for unknown feature id "
                                          + std::to_string(command.feature_id));
                        }
                        continue;
                    }
                    if (!feature_set_contains(active_features, command.feature_id)) {
                        continue;
                    }
                    if (command.payload.size() > kMaxPayloadBytes) {
                        auto current = current_callbacks();
                        if (current.error) {
                            current.error("payload exceeds max size");
                        }
                        continue;
                    }
                    {
                        auto* message = static_cast<PayloadMessage*>(client->CreateMessage(PAYLOAD_MESSAGE));
                        message->feature_id = command.feature_id;
                        message->payload_bytes = static_cast<int>(command.payload.size());
                        if (!command.payload.empty()) {
                            std::memcpy(message->payload, command.payload.data(), command.payload.size());
                        }
                        client->SendMessage(command.reliable ? kReliableChannel : kUnreliableChannel, message);
                    }
                    break;
            }
        }
    }

    void process_messages()
    {
        for (int channel_index = 0; channel_index < connection_config.numChannels; ++channel_index) {
            yojimbo::Message* incoming = client->ReceiveMessage(channel_index);
            while (incoming != nullptr) {
                if (incoming->GetType() == CONTROL_MESSAGE) {
                    auto* control = static_cast<ControlMessage*>(incoming);
                    auto current = current_callbacks();
                    if (control->action == static_cast<uint8_t>(ControlAction::Offer)) {
                        auto feature = registry->find_feature(control->feature_id);
                        if (!feature) {
                            if (current.error) {
                                current.error("server offered unknown feature id " + std::to_string(control->feature_id));
                            }
                            client->ReleaseMessage(incoming);
                            client->Disconnect();
                            active_features.clear();
                            return;
                        }
                        if (feature->version != control->feature_version) {
                            if (current.error) {
                                current.error("server offered incompatible feature version for id "
                                              + std::to_string(control->feature_id)
                                              + ": remote " + std::to_string(control->feature_version)
                                              + " local " + std::to_string(feature->version));
                            }
                            client->ReleaseMessage(incoming);
                            client->Disconnect();
                            active_features.clear();
                            return;
                        }
                        if (current.feature_offered) {
                            invoke_callback_guarded([&]() {
                                current.feature_offered(control->feature_id, control->feature_version, feature->name);
                            }, current.error, "realtime client feature-offered callback failed");
                        }
                    } else if (control->action == static_cast<uint8_t>(ControlAction::Activate)) {
                        auto feature = registry->find_feature(control->feature_id);
                        if (!feature) {
                            if (current.error) {
                                current.error("server activated unknown feature id " + std::to_string(control->feature_id));
                            }
                            client->ReleaseMessage(incoming);
                            client->Disconnect();
                            active_features.clear();
                            return;
                        }
                        if (feature->version != control->feature_version) {
                            if (current.error) {
                                current.error("server activated incompatible feature version for id "
                                              + std::to_string(control->feature_id)
                                              + ": remote " + std::to_string(control->feature_version)
                                              + " local " + std::to_string(feature->version));
                            }
                            client->ReleaseMessage(incoming);
                            client->Disconnect();
                            active_features.clear();
                            return;
                        }
                        if (!feature_set_insert(active_features, control->feature_id)) {
                            client->ReleaseMessage(incoming);
                            incoming = client->ReceiveMessage(channel_index);
                            continue;
                        }
                        if (current.feature_activated) {
                            invoke_callback_guarded([&]() {
                                current.feature_activated(control->feature_id);
                            }, current.error, "realtime client feature-activated callback failed");
                        }
                    } else if (control->action == static_cast<uint8_t>(ControlAction::Deactivate)) {
                        auto feature = registry->find_feature(control->feature_id);
                        if (!feature) {
                            if (current.error) {
                                current.error("server deactivated unknown feature id "
                                              + std::to_string(control->feature_id));
                            }
                            client->ReleaseMessage(incoming);
                            client->Disconnect();
                            active_features.clear();
                            return;
                        }
                        if (!feature_set_erase(active_features, control->feature_id)) {
                            client->ReleaseMessage(incoming);
                            incoming = client->ReceiveMessage(channel_index);
                            continue;
                        }
                        if (current.feature_deactivated) {
                            invoke_callback_guarded([&]() {
                                current.feature_deactivated(control->feature_id);
                            }, current.error, "realtime client feature-deactivated callback failed");
                        }
                    }
                } else if (incoming->GetType() == PAYLOAD_MESSAGE) {
                    auto* payload = static_cast<PayloadMessage*>(incoming);
                    if (feature_set_contains(active_features, payload->feature_id)) {
                        auto current = current_callbacks();
                        if (current.message) {
                            const std::string payload_bytes(reinterpret_cast<const char*>(payload->payload),
                                                            static_cast<size_t>(payload->payload_bytes));
                            invoke_callback_guarded([&]() {
                                current.message(payload->feature_id, payload_bytes);
                            }, current.error, "realtime client message callback failed");
                        }
                    }
                }
                client->ReleaseMessage(incoming);
                incoming = client->ReceiveMessage(channel_index);
            }
        }
    }

    std::shared_ptr<FeatureRegistry> registry;
    std::string bind_address;
    RealtimeConnectionConfig connection_config;
    RealtimeClientAdapter adapter;
    std::unique_ptr<yojimbo::Client> client;
    std::atomic<bool> running { false };
    std::thread worker;
    std::mutex callbacks_mutex;
    ClientCallbacks callbacks;
    std::mutex commands_mutex;
    std::vector<Command> commands;
    std::unordered_set<uint16_t> active_features;
    std::atomic<LifecycleState> lifecycle { LifecycleState::Idle };
    std::atomic<bool> connected { false };
};

void RealtimeServerAdapter::OnServerClientConnected(int clientIndex)
{
    owner_->on_client_connected(clientIndex);
}

void RealtimeServerAdapter::OnServerClientDisconnected(int clientIndex)
{
    owner_->on_client_disconnected(clientIndex);
}

RealtimeServer::RealtimeServer(std::shared_ptr<FeatureRegistry> registry,
                               const std::string& bind_address,
                               int max_clients,
                               const std::string& auth_scope,
                               std::vector<std::string> connect_addresses)
    : impl_(std::make_unique<Impl>(std::move(registry),
                                   bind_address,
                                   max_clients,
                                   auth_scope,
                                   std::move(connect_addresses)))
{
}

RealtimeServer::~RealtimeServer() = default;

void RealtimeServer::set_callbacks(ServerCallbacks callbacks)
{
    std::lock_guard<std::mutex> lock(impl_->callbacks_mutex);
    impl_->callbacks = std::move(callbacks);
}

void RealtimeServer::start()
{
    impl_->start();
}

void RealtimeServer::stop()
{
    impl_->stop();
}

bool RealtimeServer::is_running() const
{
    return impl_->running.load();
}

std::string RealtimeServer::address() const
{
    return impl_->bound_address;
}

std::string RealtimeServer::create_connect_token(const VerifiedAuthTicket& auth_ticket,
                                                 int expire_seconds,
                                                 int timeout_seconds) const
{
    return impl_->create_connect_token(auth_ticket, expire_seconds, timeout_seconds);
}

void RealtimeServer::activate_feature(int client_index, uint16_t feature_id)
{
    if (!impl_->running.load()) {
        throw std::runtime_error("realtime server is not running");
    }
    validate_client_index(client_index, impl_->max_clients, false);
    if (!impl_->registry->find_feature(feature_id)) {
        throw std::runtime_error("unknown feature id for activation: " + std::to_string(feature_id));
    }

    Impl::Command command;
    command.type = Impl::Command::Type::ActivateFeature;
    command.client_index = client_index;
    command.feature_id = feature_id;

    std::lock_guard<std::mutex> lock(impl_->commands_mutex);
    impl_->commands.push_back(std::move(command));
}

void RealtimeServer::deactivate_feature(int client_index, uint16_t feature_id)
{
    if (!impl_->running.load()) {
        throw std::runtime_error("realtime server is not running");
    }
    validate_client_index(client_index, impl_->max_clients, false);
    if (!impl_->registry->find_feature(feature_id)) {
        throw std::runtime_error("unknown feature id for deactivation: " + std::to_string(feature_id));
    }
    Impl::Command command;
    command.type = Impl::Command::Type::DeactivateFeature;
    command.client_index = client_index;
    command.feature_id = feature_id;

    std::lock_guard<std::mutex> lock(impl_->commands_mutex);
    impl_->commands.push_back(std::move(command));
}

void RealtimeServer::send_reliable(int client_index, uint16_t feature_id, const std::string& payload)
{
    if (!impl_->running.load()) {
        throw std::runtime_error("realtime server is not running");
    }
    validate_client_index(client_index, impl_->max_clients, true);
    if (!impl_->registry->find_feature(feature_id)) {
        throw std::runtime_error("unknown feature id for send: " + std::to_string(feature_id));
    }
    Impl::Command command;
    command.type = Impl::Command::Type::SendPayload;
    command.client_index = client_index;
    command.feature_id = feature_id;
    command.reliable = true;
    command.payload = payload;

    std::lock_guard<std::mutex> lock(impl_->commands_mutex);
    impl_->commands.push_back(std::move(command));
}

void RealtimeServer::send_unreliable(int client_index, uint16_t feature_id, const std::string& payload)
{
    if (!impl_->running.load()) {
        throw std::runtime_error("realtime server is not running");
    }
    validate_client_index(client_index, impl_->max_clients, true);
    if (!impl_->registry->find_feature(feature_id)) {
        throw std::runtime_error("unknown feature id for send: " + std::to_string(feature_id));
    }
    Impl::Command command;
    command.type = Impl::Command::Type::SendPayload;
    command.client_index = client_index;
    command.feature_id = feature_id;
    command.reliable = false;
    command.payload = payload;

    std::lock_guard<std::mutex> lock(impl_->commands_mutex);
    impl_->commands.push_back(std::move(command));
}

void RealtimeServer::broadcast_reliable(uint16_t feature_id, const std::string& payload)
{
    send_reliable(-1, feature_id, payload);
}

void RealtimeServer::broadcast_unreliable(uint16_t feature_id, const std::string& payload)
{
    send_unreliable(-1, feature_id, payload);
}

RealtimeClient::RealtimeClient(std::shared_ptr<FeatureRegistry> registry, const std::string& bind_address)
    : impl_(std::make_unique<Impl>(std::move(registry), bind_address))
{
}

RealtimeClient::~RealtimeClient() = default;

void RealtimeClient::set_callbacks(ClientCallbacks callbacks)
{
    std::lock_guard<std::mutex> lock(impl_->callbacks_mutex);
    impl_->callbacks = std::move(callbacks);
}

void RealtimeClient::connect(uint64_t client_id, const std::string& connect_token)
{
    const auto lifecycle = impl_->lifecycle.load();
    if (lifecycle == Impl::LifecycleState::Closed) {
        throw std::runtime_error("realtime client is closed");
    }
    if (client_id == 0) {
        throw std::runtime_error("realtime client connect requires non-zero client-id");
    }
    if (connect_token.size() != NETCODE_CONNECT_TOKEN_BYTES) {
        throw std::runtime_error("connect token size mismatch");
    }
    auto expected = Impl::LifecycleState::Idle;
    if (!impl_->lifecycle.compare_exchange_strong(expected, Impl::LifecycleState::Connecting)) {
        throw std::runtime_error("realtime client is already connecting or connected");
    }

    try {
        impl_->start_worker();
        Impl::Command command;
        command.type = Impl::Command::Type::Connect;
        command.client_id = client_id;
        command.connect_token = connect_token;
        impl_->enqueue(std::move(command));
    } catch (...) {
        impl_->rollback_connect_start();
        throw;
    }
}

void RealtimeClient::disconnect()
{
    const auto lifecycle = impl_->lifecycle.load();
    if (lifecycle == Impl::LifecycleState::Closed) {
        throw std::runtime_error("realtime client is closed");
    }
    if (lifecycle == Impl::LifecycleState::Idle || !impl_->running.load()) {
        return;
    }
    Impl::Command command;
    command.type = Impl::Command::Type::Disconnect;
    impl_->enqueue(std::move(command));
}

void RealtimeClient::close()
{
    impl_->close();
}

bool RealtimeClient::is_connected() const
{
    return impl_->connected.load();
}

void RealtimeClient::send_reliable(uint16_t feature_id, const std::string& payload)
{
    if (impl_->lifecycle.load() == Impl::LifecycleState::Closed) {
        throw std::runtime_error("realtime client is closed");
    }
    if (!impl_->registry->find_feature(feature_id)) {
        throw std::runtime_error("unknown feature id for send: " + std::to_string(feature_id));
    }
    Impl::Command command;
    command.type = Impl::Command::Type::SendPayload;
    command.feature_id = feature_id;
    command.reliable = true;
    command.payload = payload;
    impl_->enqueue(std::move(command));
}

void RealtimeClient::send_unreliable(uint16_t feature_id, const std::string& payload)
{
    if (impl_->lifecycle.load() == Impl::LifecycleState::Closed) {
        throw std::runtime_error("realtime client is closed");
    }
    if (!impl_->registry->find_feature(feature_id)) {
        throw std::runtime_error("unknown feature id for send: " + std::to_string(feature_id));
    }
    Impl::Command command;
    command.type = Impl::Command::Type::SendPayload;
    command.feature_id = feature_id;
    command.reliable = false;
    command.payload = payload;
    impl_->enqueue(std::move(command));
}

std::shared_ptr<FeatureRegistry> RealtimeService::create_feature_registry() const
{
    return std::make_shared<FeatureRegistry>();
}

std::shared_ptr<RealtimeServer> RealtimeService::create_server(const std::shared_ptr<FeatureRegistry>& registry,
                                                               const std::string& bind_address,
                                                               int max_clients,
                                                               const std::string& auth_scope,
                                                               std::vector<std::string> connect_addresses) const
{
    return std::make_shared<RealtimeServer>(registry,
                                            bind_address,
                                            max_clients,
                                            auth_scope,
                                            std::move(connect_addresses));
}

std::shared_ptr<RealtimeClient> RealtimeService::create_client(const std::shared_ptr<FeatureRegistry>& registry,
                                                               const std::string& bind_address) const
{
    return std::make_shared<RealtimeClient>(registry, bind_address);
}

std::string yojimbo_version_string()
{
    return "1.2.5";
}

} // namespace space::realtime
