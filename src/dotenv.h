#pragma once

#include <string>

namespace dotenv {

// Loads KEY=VALUE pairs from a dotenv file into the process environment.
// Returns true when the file was opened and processed.
bool load_dotenv_file(const std::string& path, bool override_existing);

} // namespace dotenv
