#pragma once

#include <optional>
#include <string>

class Keyring
{
public:
    Keyring() = default;

    bool set_password(const std::string& service, const std::string& account, const std::string& secret);
    std::optional<std::string> get_password(const std::string& service, const std::string& account);
    bool delete_password(const std::string& service, const std::string& account);
};
