#include "dotenv.h"

#include <cctype>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>

namespace {

std::string trim_copy(const std::string& input)
{
    size_t start = 0;
    while (start < input.size() && std::isspace(static_cast<unsigned char>(input[start]))) {
        start++;
    }

    size_t end = input.size();
    while (end > start && std::isspace(static_cast<unsigned char>(input[end - 1]))) {
        end--;
    }
    return input.substr(start, end - start);
}

bool is_valid_key(const std::string& key)
{
    if (key.empty()) {
        return false;
    }
    unsigned char first = static_cast<unsigned char>(key[0]);
    if (!(std::isalpha(first) || key[0] == '_')) {
        return false;
    }

    for (char c : key) {
        unsigned char uc = static_cast<unsigned char>(c);
        if (!(std::isalnum(uc) || c == '_')) {
            return false;
        }
    }
    return true;
}

std::string parse_quoted_value(const std::string& value, char quote)
{
    std::string out;
    out.reserve(value.size());
    for (size_t i = 1; i + 1 < value.size(); i++) {
        char c = value[i];
        if (quote == '"' && c == '\\' && i + 1 < value.size() - 1) {
            char next = value[++i];
            if (next == 'n') {
                out.push_back('\n');
            } else if (next == 'r') {
                out.push_back('\r');
            } else if (next == 't') {
                out.push_back('\t');
            } else {
                out.push_back(next);
            }
            continue;
        }
        out.push_back(c);
    }
    return out;
}

bool parse_dotenv_assignment(const std::string& raw_line, std::string& out_key, std::string& out_value)
{
    std::string line = trim_copy(raw_line);
    if (line.empty() || line[0] == '#') {
        return false;
    }

    static constexpr const char* export_prefix = "export ";
    if (line.rfind(export_prefix, 0) == 0) {
        line = trim_copy(line.substr(7));
    }

    size_t equal_pos = line.find('=');
    if (equal_pos == std::string::npos) {
        return false;
    }

    std::string key = trim_copy(line.substr(0, equal_pos));
    if (!is_valid_key(key)) {
        return false;
    }

    std::string value = trim_copy(line.substr(equal_pos + 1));
    if (value.size() >= 2 && (value.front() == '"' || value.front() == '\'') && value.front() == value.back()) {
        value = parse_quoted_value(value, value.front());
    } else {
        size_t comment_pos = std::string::npos;
        for (size_t i = 0; i < value.size(); i++) {
            if (value[i] == '#') {
                if (i == 0 || std::isspace(static_cast<unsigned char>(value[i - 1]))) {
                    comment_pos = i;
                    break;
                }
            }
        }
        if (comment_pos != std::string::npos) {
            value = trim_copy(value.substr(0, comment_pos));
        }
    }

    out_key = key;
    out_value = value;
    return true;
}

bool set_env_var(const std::string& key, const std::string& value, bool override_existing)
{
#if defined(_WIN32)
    if (!override_existing && std::getenv(key.c_str()) != nullptr) {
        return true;
    }
    return _putenv_s(key.c_str(), value.c_str()) == 0;
#else
    return setenv(key.c_str(), value.c_str(), override_existing ? 1 : 0) == 0;
#endif
}

} // namespace

namespace dotenv {

bool load_dotenv_file(const std::string& path, bool override_existing)
{
    std::ifstream file(path);
    if (!file.is_open()) {
        return false;
    }

    std::string line;
    size_t line_no = 0;
    while (std::getline(file, line)) {
        line_no++;
        std::string key;
        std::string value;
        if (!parse_dotenv_assignment(line, key, value)) {
            continue;
        }
        if (!set_env_var(key, value, override_existing)) {
            std::cerr << "warning: failed to set environment variable from " << path
                      << ":" << line_no << " (" << key << ")\n";
        }
    }

    return true;
}

} // namespace dotenv
