#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

#include "dotenv.h"

namespace fs = std::filesystem;

namespace {

bool set_env_var(const std::string& key, const std::string& value)
{
#if defined(_WIN32)
    return _putenv_s(key.c_str(), value.c_str()) == 0;
#else
    return setenv(key.c_str(), value.c_str(), 1) == 0;
#endif
}

bool unset_env_var(const std::string& key)
{
#if defined(_WIN32)
    return _putenv_s(key.c_str(), "") == 0;
#else
    return unsetenv(key.c_str()) == 0;
#endif
}

std::string getenv_or_empty(const std::string& key)
{
    const char* value = std::getenv(key.c_str());
    return value ? std::string(value) : std::string();
}

int check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return 1;
    }
    return 0;
}

} // namespace

int main()
{
    const fs::path dotenv_path = fs::temp_directory_path() / "space_test_dotenv.env";
    {
        std::ofstream out(dotenv_path);
        out << "# comment\n";
        out << "DOTENV_TEST_SIMPLE=from_file\n";
        out << " DOTENV_TEST_SPACED = spaced value   \n";
        out << "DOTENV_TEST_DOUBLE=\"double quoted\"\n";
        out << "DOTENV_TEST_SINGLE='single quoted'\n";
        out << "export DOTENV_TEST_EXPORT=from_export\n";
        out << "DOTENV_TEST_COMMENT=value # trailing comment\n";
        out << "DOTENV_TEST_EMPTY=\n";
        out << "INVALID LINE\n";
    }

    unset_env_var("DOTENV_TEST_SIMPLE");
    unset_env_var("DOTENV_TEST_SPACED");
    unset_env_var("DOTENV_TEST_DOUBLE");
    unset_env_var("DOTENV_TEST_SINGLE");
    unset_env_var("DOTENV_TEST_EXPORT");
    unset_env_var("DOTENV_TEST_COMMENT");
    unset_env_var("DOTENV_TEST_EMPTY");

    if (check(dotenv::load_dotenv_file(dotenv_path.string(), false), "dotenv file should load")) {
        return 1;
    }

    if (check(getenv_or_empty("DOTENV_TEST_SIMPLE") == "from_file", "simple assignment")) {
        return 1;
    }
    if (check(getenv_or_empty("DOTENV_TEST_SPACED") == "spaced value", "trim spacing")) {
        return 1;
    }
    if (check(getenv_or_empty("DOTENV_TEST_DOUBLE") == "double quoted", "double-quoted value")) {
        return 1;
    }
    if (check(getenv_or_empty("DOTENV_TEST_SINGLE") == "single quoted", "single-quoted value")) {
        return 1;
    }
    if (check(getenv_or_empty("DOTENV_TEST_EXPORT") == "from_export", "export prefix")) {
        return 1;
    }
    if (check(getenv_or_empty("DOTENV_TEST_COMMENT") == "value", "inline comment strip")) {
        return 1;
    }
    if (check(getenv_or_empty("DOTENV_TEST_EMPTY").empty(), "empty value stays empty")) {
        return 1;
    }

    if (!set_env_var("DOTENV_TEST_PRECEDENCE", "existing")) {
        std::cerr << "FAIL: setenv for precedence test\n";
        return 1;
    }
    {
        std::ofstream out(dotenv_path);
        out << "DOTENV_TEST_PRECEDENCE=from_file\n";
    }

    if (check(dotenv::load_dotenv_file(dotenv_path.string(), false), "load without override")) {
        return 1;
    }
    if (check(getenv_or_empty("DOTENV_TEST_PRECEDENCE") == "existing", "existing env should win by default")) {
        return 1;
    }

    if (check(dotenv::load_dotenv_file(dotenv_path.string(), true), "load with override")) {
        return 1;
    }
    if (check(getenv_or_empty("DOTENV_TEST_PRECEDENCE") == "from_file", "dotenv override should replace existing")) {
        return 1;
    }

    std::error_code ec;
    fs::remove(dotenv_path, ec);
    return 0;
}
