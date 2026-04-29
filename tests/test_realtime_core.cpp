#include <iostream>
#include <string>

#include <netcode.h>

#include "realtime/auth_ticket.h"
#include "realtime/core.h"

namespace {

int fail(const std::string& message)
{
    std::cerr << "FAIL: " << message << "\n";
    return 1;
}

int check(bool condition, const std::string& message)
{
    return condition ? 0 : fail(message);
}

} // namespace

int main()
{
    using space::realtime::AuthTicket;
    using space::realtime::FeatureDefinition;
    using space::realtime::FeatureRegistry;
    using space::realtime::RealtimeClient;
    using space::realtime::RealtimeServer;
    using space::realtime::auth_ticket_from_json;
    using space::realtime::auth_ticket_to_json;
    using space::realtime::make_dev_auth_ticket;
    using space::realtime::verify_dev_auth_ticket;

    FeatureRegistry registry;
    registry.register_feature(FeatureDefinition { 1, 1, "ping" });
    registry.register_feature(FeatureDefinition { 2, 3, "echo" });
    if (check(registry.list_features().size() == 2, "feature registry should list both features")) {
        return 1;
    }
    bool duplicate_failed = false;
    try {
        registry.register_feature(FeatureDefinition { 1, 9, "dup" });
    } catch (const std::exception&) {
        duplicate_failed = true;
    }
    if (check(duplicate_failed, "duplicate feature ids should fail")) {
        return 1;
    }
    const auto listed_features = registry.list_features();
    if (check(listed_features[0].id == 1 && listed_features[1].id == 2,
              "feature registry should list features in sorted id order")) {
        return 1;
    }
    const auto found_echo = registry.find_feature(2);
    if (check(found_echo.has_value() && found_echo->name == "echo" && found_echo->version == 3,
              "feature registry should find registered features by id")) {
        return 1;
    }
    if (check(!registry.find_feature(99).has_value(), "feature registry should return nullopt for unknown ids")) {
        return 1;
    }

    bool null_server_registry_failed = false;
    try {
        RealtimeServer server(nullptr, "127.0.0.1:0", 1, "loopback");
    } catch (const std::exception&) {
        null_server_registry_failed = true;
    }
    if (check(null_server_registry_failed, "realtime server should require a feature registry")) {
        return 1;
    }

    bool null_client_registry_failed = false;
    try {
        RealtimeClient client(nullptr, "127.0.0.1:0");
    } catch (const std::exception&) {
        null_client_registry_failed = true;
    }
    if (check(null_client_registry_failed, "realtime client should require a feature registry")) {
        return 1;
    }

    bool zero_client_id_failed = false;
    try {
        auto client = std::make_unique<RealtimeClient>(std::make_shared<FeatureRegistry>(), "127.0.0.1:0");
        client->connect(0, std::string(NETCODE_CONNECT_TOKEN_BYTES, '\0'));
    } catch (const std::exception&) {
        zero_client_id_failed = true;
    }
    if (check(zero_client_id_failed, "realtime client should reject zero client id")) {
        return 1;
    }

    bool duplicate_connect_failed = false;
    try {
        auto client = std::make_unique<RealtimeClient>(std::make_shared<FeatureRegistry>(), "127.0.0.1:0");
        const std::string token(NETCODE_CONNECT_TOKEN_BYTES, '\0');
        client->connect(1, token);
        client->connect(1, token);
    } catch (const std::exception&) {
        duplicate_connect_failed = true;
    }
    if (check(duplicate_connect_failed, "realtime client should reject duplicate connect while active")) {
        return 1;
    }

    AuthTicket ticket;
    ticket.ticket_id = "ticket-123";
    ticket.subject_user_id = "user-42";
    ticket.client_id = 4242;
    ticket.server_scope = "loopback";
    ticket.allowed_features = { 1, 2 };
    ticket.issued_at = 100;
    ticket.expires_at = 200;

    const std::string payload_json = auth_ticket_to_json(ticket);
    const AuthTicket parsed = auth_ticket_from_json(payload_json);
    if (check(parsed.ticket_id == ticket.ticket_id, "parsed ticket id should match")) {
        return 1;
    }
    if (check(parsed.allowed_features == ticket.allowed_features, "parsed allowed features should match")) {
        return 1;
    }

    const auto signed_ticket = make_dev_auth_ticket(ticket, "dev-secret");
    if (check(!signed_ticket.signature_hex.empty(), "signed ticket should have a signature")) {
        return 1;
    }
    const auto verified = verify_dev_auth_ticket(signed_ticket.payload_json,
                                                 signed_ticket.signature_hex,
                                                 "dev-secret",
                                                 150);
    if (check(verified.ticket().subject_user_id == ticket.subject_user_id, "verified ticket subject should match")) {
        return 1;
    }

    bool bad_secret_failed = false;
    try {
        (void) verify_dev_auth_ticket(signed_ticket.payload_json, signed_ticket.signature_hex, "wrong-secret", 150);
    } catch (const std::exception&) {
        bad_secret_failed = true;
    }
    if (check(bad_secret_failed, "wrong auth ticket secret should fail")) {
        return 1;
    }

    bool expired_failed = false;
    try {
        (void) verify_dev_auth_ticket(signed_ticket.payload_json, signed_ticket.signature_hex, "dev-secret", 250);
    } catch (const std::exception&) {
        expired_failed = true;
    }
    if (check(expired_failed, "expired auth ticket should fail")) {
        return 1;
    }

    bool not_yet_valid_failed = false;
    try {
        (void) verify_dev_auth_ticket(signed_ticket.payload_json, signed_ticket.signature_hex, "dev-secret", 50);
    } catch (const std::exception&) {
        not_yet_valid_failed = true;
    }
    if (check(not_yet_valid_failed, "auth ticket should fail before issued-at")) {
        return 1;
    }

    bool duplicate_features_failed = false;
    try {
        AuthTicket invalid = ticket;
        invalid.allowed_features = { 2, 2 };
        (void) auth_ticket_to_json(invalid);
    } catch (const std::exception&) {
        duplicate_features_failed = true;
    }
    if (check(duplicate_features_failed, "duplicate allowed features should fail")) {
        return 1;
    }

    bool unsorted_features_failed = false;
    try {
        AuthTicket invalid = ticket;
        invalid.allowed_features = { 2, 1 };
        (void) auth_ticket_to_json(invalid);
    } catch (const std::exception&) {
        unsorted_features_failed = true;
    }
    if (check(unsorted_features_failed, "unsorted allowed features should fail")) {
        return 1;
    }

    bool invalid_hex_failed = false;
    try {
        (void) verify_dev_auth_ticket(signed_ticket.payload_json, "zz", "dev-secret", 150);
    } catch (const std::exception&) {
        invalid_hex_failed = true;
    }
    if (check(invalid_hex_failed, "invalid auth ticket signature hex should fail")) {
        return 1;
    }

    bool empty_secret_failed = false;
    try {
        (void) make_dev_auth_ticket(ticket, "");
    } catch (const std::exception&) {
        empty_secret_failed = true;
    }
    if (check(empty_secret_failed, "empty auth ticket secret should fail")) {
        return 1;
    }

    bool unknown_client_send_failed = false;
    try {
        auto registry_ptr = std::make_shared<FeatureRegistry>();
        registry_ptr->register_feature(FeatureDefinition { 1, 1, "ping" });
        RealtimeClient client(registry_ptr, "127.0.0.1:0");
        client.send_reliable(999, "payload");
    } catch (const std::exception&) {
        unknown_client_send_failed = true;
    }
    if (check(unknown_client_send_failed, "realtime client should reject unknown feature payload sends")) {
        return 1;
    }

    std::cout << "test_realtime_core: all tests passed\n";
    return 0;
}
