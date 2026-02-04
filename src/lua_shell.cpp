#include "lua_shell.h"

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include <cstdio>
#include <cstring>
#include <cerrno>

#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

namespace {

struct BashArgs {
    std::string command;
    double timeout_seconds;
    std::optional<std::string> cwd;
};

struct BashResult {
    int exit_code { -1 };
    int signal { 0 };
    bool timed_out { false };
    std::string stdout_text;
    std::string stderr_text;
    std::uint64_t duration_ms { 0 };
};

int set_nonblocking(int fd)
{
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags == -1) {
        return -1;
    }
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

BashArgs parse_args(sol::variadic_args args)
{
    if (args.size() == 0) {
        throw sol::error("shell.bash requires a command");
    }

    sol::object first = args[0];
    sol::optional<sol::table> opts;
    std::size_t index = 0;
    if (first.is<sol::table>()) {
        opts = first.as<sol::table>();
        index = 1;
    }

    sol::object command_obj = opts ? opts->get<sol::object>("command") : args[index];
    if (!command_obj.is<std::string>()) {
        throw sol::error("shell.bash command must be a string");
    }
    std::string command = command_obj.as<std::string>();
    if (command.empty()) {
        throw sol::error("shell.bash command must not be empty");
    }

    sol::object timeout_obj;
    if (opts) {
        timeout_obj = opts->get<sol::object>("timeout");
    } else if (args.size() > index + 1) {
        timeout_obj = args[index + 1];
    }

    if (!timeout_obj.is<double>() && !timeout_obj.is<int>() && !timeout_obj.is<uint64_t>()) {
        throw sol::error("shell.bash timeout must be a number");
    }

    double timeout_seconds = 0.0;
    if (timeout_obj.is<double>()) {
        timeout_seconds = timeout_obj.as<double>();
    } else if (timeout_obj.is<int>()) {
        timeout_seconds = static_cast<double>(timeout_obj.as<int>());
    } else if (timeout_obj.is<uint64_t>()) {
        timeout_seconds = static_cast<double>(timeout_obj.as<uint64_t>());
    }

    if (timeout_seconds <= 0.0) {
        throw sol::error("shell.bash timeout must be greater than 0");
    }

    sol::object cwd_obj;
    if (opts) {
        cwd_obj = opts->get<sol::object>("cwd");
    }

    std::optional<std::string> cwd;
    if (cwd_obj.valid() && !cwd_obj.is<sol::lua_nil_t>()) {
        if (!cwd_obj.is<std::string>()) {
            throw sol::error("shell.bash cwd must be a string");
        }
        std::string cwd_value = cwd_obj.as<std::string>();
        if (cwd_value.empty()) {
            throw sol::error("shell.bash cwd must not be empty");
        }
        cwd = std::move(cwd_value);
    }

    return BashArgs { std::move(command), timeout_seconds, std::move(cwd) };
}

bool drain_fd(int fd, std::string& out)
{
    char buffer[4096];
    while (true) {
        ssize_t bytes = read(fd, buffer, sizeof(buffer));
        if (bytes > 0) {
            out.append(buffer, static_cast<std::size_t>(bytes));
            continue;
        }
        if (bytes == 0) {
            return false;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return true;
        }
        return false;
    }
}

BashResult run_bash_command(const std::string& command, double timeout_seconds,
                            const std::optional<std::string>& cwd)
{
    int stdout_pipe[2];
    int stderr_pipe[2];
    if (pipe(stdout_pipe) != 0) {
        throw sol::error("shell.bash failed to open stdout pipe");
    }
    if (pipe(stderr_pipe) != 0) {
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        throw sol::error("shell.bash failed to open stderr pipe");
    }

    pid_t pid = fork();
    if (pid < 0) {
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        close(stderr_pipe[0]);
        close(stderr_pipe[1]);
        throw sol::error("shell.bash failed to fork");
    }

    if (pid == 0) {
        setpgid(0, 0);
        dup2(stdout_pipe[1], STDOUT_FILENO);
        dup2(stderr_pipe[1], STDERR_FILENO);
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        close(stderr_pipe[0]);
        close(stderr_pipe[1]);
        if (cwd.has_value()) {
            if (chdir(cwd->c_str()) != 0) {
                dprintf(STDERR_FILENO, "shell.bash failed to chdir to %s: %s\n",
                        cwd->c_str(), strerror(errno));
                _exit(126);
            }
        }
        execl("/bin/bash", "bash", "-lc", command.c_str(), static_cast<char*>(nullptr));
        _exit(127);
    }

    close(stdout_pipe[1]);
    close(stderr_pipe[1]);
    set_nonblocking(stdout_pipe[0]);
    set_nonblocking(stderr_pipe[0]);

    BashResult result;
    bool stdout_open = true;
    bool stderr_open = true;
    bool child_done = false;
    int status = 0;

    auto start = std::chrono::steady_clock::now();

    while (stdout_open || stderr_open || !child_done) {
        if (!child_done) {
            pid_t wait_result = waitpid(pid, &status, WNOHANG);
            if (wait_result == pid) {
                child_done = true;
            }
        }

        if (!child_done) {
            auto now = std::chrono::steady_clock::now();
            double elapsed = std::chrono::duration<double>(now - start).count();
            if (elapsed >= timeout_seconds) {
                result.timed_out = true;
                killpg(pid, SIGTERM);
                auto term_deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(200);
                while (true) {
                    pid_t wait_result = waitpid(pid, &status, WNOHANG);
                    if (wait_result == pid) {
                        child_done = true;
                        break;
                    }
                    if (std::chrono::steady_clock::now() >= term_deadline) {
                        killpg(pid, SIGKILL);
                        waitpid(pid, &status, 0);
                        child_done = true;
                        break;
                    }
                    struct timespec sleep_time { 0, 10 * 1000 * 1000 };
                    nanosleep(&sleep_time, nullptr);
                }
            }
        }

        if (!stdout_open && !stderr_open) {
            if (child_done) {
                break;
            }
            struct timespec sleep_time { 0, 5 * 1000 * 1000 };
            nanosleep(&sleep_time, nullptr);
            continue;
        }

        std::vector<pollfd> fds;
        if (stdout_open) {
            pollfd out_fd {};
            out_fd.fd = stdout_pipe[0];
            out_fd.events = POLLIN;
            fds.push_back(out_fd);
        }
        if (stderr_open) {
            pollfd err_fd {};
            err_fd.fd = stderr_pipe[0];
            err_fd.events = POLLIN;
            fds.push_back(err_fd);
        }

        int poll_timeout_ms = 50;
        if (!child_done) {
            auto now = std::chrono::steady_clock::now();
            double elapsed = std::chrono::duration<double>(now - start).count();
            double remaining = timeout_seconds - elapsed;
            if (remaining < 0.0) {
                poll_timeout_ms = 0;
            } else {
                int remaining_ms = static_cast<int>(remaining * 1000.0);
                if (remaining_ms < poll_timeout_ms) {
                    poll_timeout_ms = remaining_ms;
                }
            }
        }

        int poll_result = poll(fds.data(), fds.size(), poll_timeout_ms);
        if (poll_result > 0) {
            for (auto& entry : fds) {
                if ((entry.revents & POLLIN) != 0) {
                    if (entry.fd == stdout_pipe[0]) {
                        stdout_open = drain_fd(stdout_pipe[0], result.stdout_text);
                    } else if (entry.fd == stderr_pipe[0]) {
                        stderr_open = drain_fd(stderr_pipe[0], result.stderr_text);
                    }
                } else if ((entry.revents & (POLLHUP | POLLERR | POLLNVAL)) != 0) {
                    if (entry.fd == stdout_pipe[0]) {
                        stdout_open = drain_fd(stdout_pipe[0], result.stdout_text);
                    } else if (entry.fd == stderr_pipe[0]) {
                        stderr_open = drain_fd(stderr_pipe[0], result.stderr_text);
                    }
                }
            }
        }
    }

    close(stdout_pipe[0]);
    close(stderr_pipe[0]);

    if (WIFEXITED(status)) {
        result.exit_code = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        result.signal = WTERMSIG(status);
        result.exit_code = 128 + result.signal;
    }

    auto end = std::chrono::steady_clock::now();
    result.duration_ms = static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count());
    return result;
}

} // namespace

void lua_bind_shell(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("shell", [](sol::this_state state) {
        sol::state_view lua_view(state);
        sol::table shell_table = lua_view.create_table();
        shell_table.set_function("bash", [](sol::variadic_args args) {
            BashArgs parsed = parse_args(args);
            BashResult result = run_bash_command(parsed.command, parsed.timeout_seconds, parsed.cwd);
            sol::state_view lua_view(args.lua_state());
            sol::table output = lua_view.create_table();
            output["command"] = parsed.command;
            output["timeout"] = parsed.timeout_seconds;
            output["cwd"] = parsed.cwd ? sol::make_object(lua_view, *parsed.cwd)
                                       : sol::make_object(lua_view, sol::lua_nil);
            output["exit_code"] = result.exit_code;
            output["signal"] = result.signal > 0 ? sol::make_object(lua_view, result.signal)
                                                 : sol::make_object(lua_view, sol::lua_nil);
            output["timed_out"] = result.timed_out;
            output["stdout"] = result.stdout_text;
            output["stderr"] = result.stderr_text;
            output["duration_ms"] = static_cast<uint64_t>(result.duration_ms);
            return output;
        });
        return shell_table;
    });
}
