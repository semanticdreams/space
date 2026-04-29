#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace space::realtime {

constexpr size_t kAuthTicketTransportStringMaxBytes = 255;
constexpr size_t kAuthTicketTransportMaxFeatureCount = 255;
constexpr size_t kAuthTicketTransportPayloadMaxBytes = 254;

struct AuthTicket
{
    std::string ticket_id;
    std::string subject_user_id;
    uint64_t client_id { 0 };
    std::string server_scope;
    std::vector<uint16_t> allowed_features;
    int64_t issued_at { 0 };
    int64_t expires_at { 0 };
};

struct SignedAuthTicket
{
    AuthTicket ticket;
    std::string payload_json;
    std::string signature_hex;
};

class VerifiedAuthTicket
{
public:
    const AuthTicket& ticket() const { return ticket_; }

private:
    friend VerifiedAuthTicket verify_dev_auth_ticket(const std::string& payload_json,
                                                     const std::string& signature_hex,
                                                     const std::string& secret,
                                                     std::optional<int64_t> now);

    explicit VerifiedAuthTicket(AuthTicket ticket)
        : ticket_(std::move(ticket))
    {
    }

    AuthTicket ticket_;
};

void validate_auth_ticket(const AuthTicket& ticket);
std::string auth_ticket_to_json(const AuthTicket& ticket);
AuthTicket auth_ticket_from_json(const std::string& json_text);
SignedAuthTicket make_dev_auth_ticket(const AuthTicket& ticket, const std::string& secret);
VerifiedAuthTicket verify_dev_auth_ticket(const std::string& payload_json,
                                          const std::string& signature_hex,
                                          const std::string& secret,
                                          std::optional<int64_t> now = std::nullopt);

} // namespace space::realtime
