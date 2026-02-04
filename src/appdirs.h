#pragma once

#include <string>

// Cross-platform helpers for resolving user directories.
std::string get_home_dir();
std::string get_tmp_dir();
// Returns the user data directory for the given app.
std::string get_user_data_dir(const std::string& app_name);
std::string get_user_config_dir(const std::string& app_name);
std::string get_user_cache_dir(const std::string& app_name);
std::string get_user_log_dir(const std::string& app_name);
// Returns system-wide shared directories for the given app.
std::string get_site_data_dir(const std::string& app_name);
std::string get_site_config_dir(const std::string& app_name);
