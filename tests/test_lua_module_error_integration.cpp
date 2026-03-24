#include <array>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>

#if !defined(_WIN32)
#include <sys/wait.h>
#endif

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

std::string shell_quote(const std::string& value)
{
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
#if defined(_WIN32)
    FILE* pipe = _popen(full_command.c_str(), "r");
#else
    FILE* pipe = popen(full_command.c_str(), "r");
#endif
    if (!pipe) {
        return false;
    }

    output.clear();
    while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe) != nullptr) {
        output.append(buffer.data());
    }

#if defined(_WIN32)
    int status = _pclose(pipe);
    if (status == -1) {
        return false;
    }
    exit_code = status;
#else
    int status = pclose(pipe);
    if (status == -1) {
        return false;
    }
    if (WIFEXITED(status)) {
        exit_code = WEXITSTATUS(status);
    } else {
        exit_code = 128;
    }
#endif
    return true;
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
    const fs::path assets_dir = fs::current_path().parent_path() / "assets";
    if (!set_env_var("SPACE_ASSETS_PATH", assets_dir.string())) {
        std::cerr << "FAIL: failed to set SPACE_ASSETS_PATH\n";
        return 1;
    }
    if (!set_env_var("SPACE_DISABLE_AUDIO", "1")) {
        std::cerr << "FAIL: failed to set SPACE_DISABLE_AUDIO\n";
        return 1;
    }

    std::string output;
    int exit_code = 0;
    const std::string command = "./space -m tests.module-error";
    if (!check(run_command_capture(command, output, exit_code), "run module error command")) {
        return 1;
    }
    if (!check(exit_code != 0, "module error command should fail")) {
        std::cerr << output << "\n";
        return 1;
    }
    if (!check(output.find("tests.module-error startup failure") != std::string::npos,
               "module error should be reported")) {
        std::cerr << output << "\n";
        return 1;
    }

    return 0;
}
