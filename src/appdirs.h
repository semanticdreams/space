#pragma once

#include <string>

// Returns the user data directory for the given app.
// Automatically creates the directory if it doesn't exist.
std::string get_user_data_dir(const std::string& app_name);
