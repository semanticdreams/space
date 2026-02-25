#pragma once

#include <string>

namespace cef_runtime {

struct Config {
    int argc { 0 };
    char** argv { nullptr };
    std::string helper_executable_path;
};

// Returns >= 0 when the current process is a CEF subprocess and should exit with that code.
// Returns -1 when the caller should continue normal app startup.
int maybe_execute_subprocess(int argc, char** argv);

void configure_browser_process(const Config& config);
bool ensure_initialized();
bool initialize_browser_process(const Config& config);
void do_message_loop_work();
void shutdown();
bool is_initialized();

} // namespace cef_runtime
