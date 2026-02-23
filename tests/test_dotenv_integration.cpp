#include <array>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <sys/wait.h>

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

std::string shell_quote(const fs::path& path)
{
    std::string value = path.string();
    std::string quoted = "'";
    for (char c : value) {
        if (c == '\'') {
            quoted += "'\\''";
        } else {
            quoted.push_back(c);
        }
    }
    quoted.push_back('\'');
    return quoted;
}

bool run_command_capture(const std::string& command, std::string& output, int& exit_code)
{
    std::array<char, 256> buffer {};
    std::string full_command = command + " 2>&1";
    FILE* pipe = popen(full_command.c_str(), "r");
    if (!pipe) {
        return false;
    }

    output.clear();
    while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe) != nullptr) {
        output.append(buffer.data());
    }

    int status = pclose(pipe);
    if (status == -1) {
        return false;
    }
    exit_code = WEXITSTATUS(status);
    return true;
}

bool output_contains_value(const std::string& output, const std::string& expected)
{
    return output.find("VALUE:" + expected) != std::string::npos;
}

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

} // namespace

int main()
{
    const fs::path dotenv_path = fs::temp_directory_path() / "space_test_dotenv_integration.env";
    const fs::path script_path = fs::temp_directory_path() / "space_test_dotenv_integration.fnl";

    {
        std::ofstream dotenv_out(dotenv_path);
        dotenv_out << "DOTENV_IT_VALUE=from_file\n";
    }
    {
        std::ofstream script_out(script_path);
        script_out << "(print (.. \"VALUE:\" (or (os.getenv \"DOTENV_IT_VALUE\") \"\")))\n";
    }

    if (!set_env_var("SPACE_DISABLE_AUDIO", "1")) {
        std::cerr << "FAIL: failed to set SPACE_DISABLE_AUDIO\n";
        return 1;
    }

    std::string output;
    int exit_code = 1;

    if (!set_env_var("DOTENV_IT_VALUE", "from_env")) {
        std::cerr << "FAIL: failed to set DOTENV_IT_VALUE\n";
        return 1;
    }
    std::string default_cmd = "./space --dotenv " + shell_quote(dotenv_path) + " " + shell_quote(script_path);
    if (!check(run_command_capture(default_cmd, output, exit_code), "run default dotenv command")) {
        return 1;
    }
    if (!check(exit_code == 0, "default dotenv command exits 0")) {
        std::cerr << output << "\n";
        return 1;
    }
    if (!check(output_contains_value(output, "from_env"), "existing env wins without override")) {
        std::cerr << output << "\n";
        return 1;
    }

    std::string override_cmd = "./space --dotenv " + shell_quote(dotenv_path) + " --dotenv-override " + shell_quote(script_path);
    if (!check(run_command_capture(override_cmd, output, exit_code), "run dotenv override command")) {
        return 1;
    }
    if (!check(exit_code == 0, "dotenv override command exits 0")) {
        std::cerr << output << "\n";
        return 1;
    }
    if (!check(output_contains_value(output, "from_file"), "dotenv override replaces existing env")) {
        std::cerr << output << "\n";
        return 1;
    }

    if (!unset_env_var("DOTENV_IT_VALUE")) {
        std::cerr << "FAIL: failed to unset DOTENV_IT_VALUE\n";
        return 1;
    }
    std::string disabled_cmd = "./space --dotenv " + shell_quote(dotenv_path) + " --no-dotenv " + shell_quote(script_path);
    if (!check(run_command_capture(disabled_cmd, output, exit_code), "run no-dotenv command")) {
        return 1;
    }
    if (!check(exit_code == 0, "no-dotenv command exits 0")) {
        std::cerr << output << "\n";
        return 1;
    }
    if (!check(output_contains_value(output, ""), "no-dotenv keeps variable unset")) {
        std::cerr << output << "\n";
        return 1;
    }

    std::error_code ec;
    fs::remove(dotenv_path, ec);
    fs::remove(script_path, ec);
    return 0;
}
