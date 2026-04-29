#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "realtime/auth_ticket.h"

namespace space::realtime {

struct FeatureDefinition
{
    uint16_t id { 0 };
    uint16_t version { 1 };
    std::string name;
};

class FeatureRegistry
{
public:
    void register_feature(const FeatureDefinition& feature);
    std::vector<FeatureDefinition> list_features() const;
    std::optional<FeatureDefinition> find_feature(uint16_t id) const;

private:
    mutable std::mutex mutex_;
    std::unordered_map<uint16_t, FeatureDefinition> features_;
};

struct ServerCallbacks
{
    std::function<void(const std::string& address)> started;
    std::function<void()> stopped;
    std::function<void(int client_index, uint64_t client_id, const AuthTicket& auth_ticket)> client_connected;
    std::function<void(int client_index)> client_disconnected;
    std::function<void(int client_index, uint16_t feature_id)> feature_activated;
    std::function<void(int client_index, uint16_t feature_id)> feature_deactivated;
    std::function<void(int client_index, uint16_t feature_id, const std::string& payload)> message;
    std::function<void(const std::string& error)> error;
};

struct ClientCallbacks
{
    std::function<void()> connected;
    std::function<void()> disconnected;
    std::function<void(uint16_t feature_id, uint16_t version, const std::string& name)> feature_offered;
    std::function<void(uint16_t feature_id)> feature_activated;
    std::function<void(uint16_t feature_id)> feature_deactivated;
    std::function<void(uint16_t feature_id, const std::string& payload)> message;
    std::function<void(const std::string& error)> error;
};

class RealtimeServer
{
public:
    struct Impl;

    RealtimeServer(std::shared_ptr<FeatureRegistry> registry,
                   const std::string& bind_address,
                   int max_clients,
                   const std::string& auth_scope = "",
                   std::vector<std::string> connect_addresses = {});
    ~RealtimeServer();

    RealtimeServer(const RealtimeServer&) = delete;
    RealtimeServer& operator=(const RealtimeServer&) = delete;

    void set_callbacks(ServerCallbacks callbacks);
    void start();
    void stop();
    [[nodiscard]] bool is_running() const;
    [[nodiscard]] std::string address() const;
    std::string create_connect_token(const VerifiedAuthTicket& auth_ticket,
                                     int expire_seconds = 30,
                                     int timeout_seconds = 10) const;
    void activate_feature(int client_index, uint16_t feature_id);
    void deactivate_feature(int client_index, uint16_t feature_id);
    void send_reliable(int client_index, uint16_t feature_id, const std::string& payload);
    void send_unreliable(int client_index, uint16_t feature_id, const std::string& payload);
    void broadcast_reliable(uint16_t feature_id, const std::string& payload);
    void broadcast_unreliable(uint16_t feature_id, const std::string& payload);

private:
    std::unique_ptr<Impl> impl_;
};

class RealtimeClient
{
public:
    struct Impl;

    RealtimeClient(std::shared_ptr<FeatureRegistry> registry, const std::string& bind_address);
    ~RealtimeClient();

    RealtimeClient(const RealtimeClient&) = delete;
    RealtimeClient& operator=(const RealtimeClient&) = delete;

    void set_callbacks(ClientCallbacks callbacks);
    void connect(uint64_t client_id, const std::string& connect_token);
    void disconnect();
    void close();
    [[nodiscard]] bool is_connected() const;
    void send_reliable(uint16_t feature_id, const std::string& payload);
    void send_unreliable(uint16_t feature_id, const std::string& payload);

private:
    std::unique_ptr<Impl> impl_;
};

class RealtimeService
{
public:
    std::shared_ptr<FeatureRegistry> create_feature_registry() const;
    std::shared_ptr<RealtimeServer> create_server(const std::shared_ptr<FeatureRegistry>& registry,
                                                  const std::string& bind_address,
                                                  int max_clients,
                                                  const std::string& auth_scope = "",
                                                  std::vector<std::string> connect_addresses = {}) const;
    std::shared_ptr<RealtimeClient> create_client(const std::shared_ptr<FeatureRegistry>& registry,
                                                  const std::string& bind_address) const;
};

std::string yojimbo_version_string();

} // namespace space::realtime
