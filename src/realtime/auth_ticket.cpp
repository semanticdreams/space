#include "realtime/auth_ticket.h"

#include <algorithm>
#include <array>
#include <ctime>
#include <stdexcept>
#include <string_view>

#include <nlohmann/json.hpp>
#include <sodium.h>

namespace space::realtime {
namespace {

using json = nlohmann::json;

constexpr char kHexDigits[] = "0123456789abcdef";

unsigned char decode_hex_digit(char ch)
{
    if (ch >= '0' && ch <= '9') {
        return static_cast<unsigned char>(ch - '0');
    }
    if (ch >= 'a' && ch <= 'f') {
        return static_cast<unsigned char>(10 + (ch - 'a'));
    }
    if (ch >= 'A' && ch <= 'F') {
        return static_cast<unsigned char>(10 + (ch - 'A'));
    }
    throw std::runtime_error("invalid hex digit in auth ticket signature");
}

std::string hex_encode(std::string_view bytes)
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
        throw std::runtime_error("auth ticket signature must have even-length hex encoding");
    }

    std::string decoded;
    decoded.resize(text.size() / 2);
    for (size_t i = 0; i < decoded.size(); ++i) {
        const unsigned char high = decode_hex_digit(text[i * 2]);
        const unsigned char low = decode_hex_digit(text[i * 2 + 1]);
        decoded[i] = static_cast<char>((high << 4) | low);
    }
    return decoded;
}

void ensure_sodium()
{
    static const bool initialized = []() {
        return sodium_init() >= 0;
    }();

    if (!initialized) {
        throw std::runtime_error("failed to initialize libsodium for auth tickets");
    }
}

constexpr size_t kAuthSignatureBytes = crypto_generichash_BYTES;

std::array<unsigned char, kAuthSignatureBytes> sign_payload(const std::string& payload_json,
                                                            const std::string& secret)
{
    ensure_sodium();
    if (secret.empty()) {
        throw std::runtime_error("auth ticket secret must be non-empty");
    }

    std::array<unsigned char, crypto_generichash_KEYBYTES> key {};
    crypto_generichash(key.data(),
                       key.size(),
                       reinterpret_cast<const unsigned char*>(secret.data()),
                       secret.size(),
                       nullptr,
                       0);

    std::array<unsigned char, kAuthSignatureBytes> signature {};
    if (crypto_generichash(signature.data(),
                           signature.size(),
                           reinterpret_cast<const unsigned char*>(payload_json.data()),
                           payload_json.size(),
                           key.data(),
                           key.size()) != 0) {
        throw std::runtime_error("failed to sign auth ticket payload");
    }
    return signature;
}

bool is_sorted_unique(const std::vector<uint16_t>& values)
{
    return std::is_sorted(values.begin(), values.end()) &&
           std::adjacent_find(values.begin(), values.end()) == values.end();
}

size_t encoded_auth_ticket_payload_size(const AuthTicket& ticket)
{
    return 1
           + 4
           + 8
           + 8
           + 8
           + ticket.allowed_features.size() * sizeof(uint16_t)
           + ticket.ticket_id.size()
           + ticket.subject_user_id.size()
           + ticket.server_scope.size();
}

} // namespace

void validate_auth_ticket(const AuthTicket& ticket)
{
    if (ticket.ticket_id.empty()) {
        throw std::runtime_error("auth ticket ticket-id must be non-empty");
    }
    if (ticket.subject_user_id.empty()) {
        throw std::runtime_error("auth ticket subject-user-id must be non-empty");
    }
    if (ticket.client_id == 0) {
        throw std::runtime_error("auth ticket client-id must be non-zero");
    }
    if (ticket.server_scope.empty()) {
        throw std::runtime_error("auth ticket server-scope must be non-empty");
    }
    if (ticket.issued_at <= 0) {
        throw std::runtime_error("auth ticket issued-at must be positive");
    }
    if (ticket.expires_at <= ticket.issued_at) {
        throw std::runtime_error("auth ticket expires-at must be greater than issued-at");
    }
    if (ticket.ticket_id.size() > kAuthTicketTransportStringMaxBytes
        || ticket.subject_user_id.size() > kAuthTicketTransportStringMaxBytes
        || ticket.server_scope.size() > kAuthTicketTransportStringMaxBytes) {
        throw std::runtime_error("auth ticket string fields exceed transport limits");
    }
    if (ticket.allowed_features.size() > kAuthTicketTransportMaxFeatureCount) {
        throw std::runtime_error("auth ticket allowed-features exceed transport limits");
    }
    for (uint16_t feature_id : ticket.allowed_features) {
        if (feature_id == 0) {
            throw std::runtime_error("auth ticket allowed-features must not contain zero");
        }
    }
    if (!is_sorted_unique(ticket.allowed_features)) {
        throw std::runtime_error("auth ticket allowed-features must be sorted and unique");
    }
    if (encoded_auth_ticket_payload_size(ticket) > kAuthTicketTransportPayloadMaxBytes) {
        throw std::runtime_error("auth ticket exceeds transport payload limits");
    }
}

std::string auth_ticket_to_json(const AuthTicket& ticket)
{
    validate_auth_ticket(ticket);

    json data;
    data["allowed_features"] = ticket.allowed_features;
    data["client_id"] = ticket.client_id;
    data["expires_at"] = ticket.expires_at;
    data["issued_at"] = ticket.issued_at;
    data["server_scope"] = ticket.server_scope;
    data["subject_user_id"] = ticket.subject_user_id;
    data["ticket_id"] = ticket.ticket_id;
    return data.dump();
}

AuthTicket auth_ticket_from_json(const std::string& json_text)
{
    json data = json::parse(json_text);
    AuthTicket ticket;
    ticket.ticket_id = data.at("ticket_id").get<std::string>();
    ticket.subject_user_id = data.at("subject_user_id").get<std::string>();
    ticket.client_id = data.at("client_id").get<uint64_t>();
    ticket.server_scope = data.at("server_scope").get<std::string>();
    ticket.allowed_features = data.at("allowed_features").get<std::vector<uint16_t>>();
    ticket.issued_at = data.at("issued_at").get<int64_t>();
    ticket.expires_at = data.at("expires_at").get<int64_t>();
    validate_auth_ticket(ticket);
    return ticket;
}

SignedAuthTicket make_dev_auth_ticket(const AuthTicket& ticket, const std::string& secret)
{
    const std::string payload_json = auth_ticket_to_json(ticket);
    const auto signature = sign_payload(payload_json, secret);

    SignedAuthTicket out;
    out.ticket = ticket;
    out.payload_json = payload_json;
    out.signature_hex = hex_encode(std::string_view(reinterpret_cast<const char*>(signature.data()), signature.size()));
    return out;
}

VerifiedAuthTicket verify_dev_auth_ticket(const std::string& payload_json,
                                          const std::string& signature_hex,
                                          const std::string& secret,
                                          std::optional<int64_t> now)
{
    const std::string decoded_signature = hex_decode(signature_hex);
    if (decoded_signature.size() != kAuthSignatureBytes) {
        throw std::runtime_error("auth ticket signature has invalid size");
    }

    const auto expected_signature = sign_payload(payload_json, secret);
    if (sodium_memcmp(decoded_signature.data(), expected_signature.data(), expected_signature.size()) != 0) {
        throw std::runtime_error("auth ticket signature mismatch");
    }

    AuthTicket ticket = auth_ticket_from_json(payload_json);
    const int64_t current_time = now.value_or(static_cast<int64_t>(std::time(nullptr)));
    if (current_time < ticket.issued_at) {
        throw std::runtime_error("auth ticket is not valid yet");
    }
    if (current_time > ticket.expires_at) {
        throw std::runtime_error("auth ticket has expired");
    }
    return VerifiedAuthTicket(std::move(ticket));
}

} // namespace space::realtime
