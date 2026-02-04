#include "lua_process.h"
#include "lua_callbacks.h"

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include <cerrno>
#include <cstdio>
#include <cstring>

#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

namespace {

struct ProcessArgs
{
    std::vector<std::string> args;
    std::optional<std::string> cwd;
    std::vector<std::pair<std::string, std::string>> env;
    bool clear_env { false };
    std::optional<double> timeout_seconds;
    std::optional<std::string> stdin_data;
    bool merge_stderr { false };
};

struct ProcessResult
{
    int exit_code { -1 };
    int signal { 0 };
    bool timed_out { false };
    std::string stdout_text;
    std::string stderr_text;
    std::uint64_t duration_ms { 0 };
};

struct SpawnedProcess
{
    uint64_t id { 0 };
    pid_t pid { -1 };
    int stdout_fd { -1 };
    int stderr_fd { -1 };
    int stdin_fd { -1 };
    bool stdin_closed { false };
    std::string stdout_buffer;
    std::string stderr_buffer;
    std::chrono::steady_clock::time_point start_time;
    std::optional<double> timeout_seconds;
    bool finished { false };
    ProcessResult result;
    uint64_t callback_id { 0 };
    bool merge_stderr { false };
};

struct ProcessManager
{
    std::mutex mutex;
    std::unordered_map<uint64_t, SpawnedProcess> processes;
    std::vector<std::pair<uint64_t, ProcessResult>> completed;
    uint64_t next_id { 1 };
};

int set_nonblocking(int fd)
{
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags == -1) {
        return -1;
    }
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

int set_cloexec(int fd)
{
    int flags = fcntl(fd, F_GETFD, 0);
    if (flags == -1) {
        return -1;
    }
    return fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
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

ProcessArgs parse_args(sol::table opts)
{
    ProcessArgs parsed;

    sol::object args_obj = opts.get<sol::object>("args");
    if (!args_obj.is<sol::table>()) {
        throw sol::error("process.run/spawn requires 'args' as a table of strings");
    }
    sol::table args_table = args_obj.as<sol::table>();
    std::size_t len = args_table.size();
    if (len == 0) {
        throw sol::error("process.run/spawn args must not be empty");
    }
    for (std::size_t i = 1; i <= len; ++i) {
        sol::object item = args_table[i];
        if (!item.is<std::string>()) {
            throw sol::error("process.run/spawn args must all be strings");
        }
        parsed.args.push_back(item.as<std::string>());
    }

    sol::object cwd_obj = opts.get<sol::object>("cwd");
    if (cwd_obj.valid() && !cwd_obj.is<sol::lua_nil_t>()) {
        if (!cwd_obj.is<std::string>()) {
            throw sol::error("process cwd must be a string");
        }
        std::string cwd_value = cwd_obj.as<std::string>();
        if (!cwd_value.empty()) {
            parsed.cwd = std::move(cwd_value);
        }
    }

    sol::object env_obj = opts.get<sol::object>("env");
    if (env_obj.valid() && env_obj.is<sol::table>()) {
        sol::table env_table = env_obj.as<sol::table>();
        for (auto& kv : env_table) {
            if (kv.first.is<std::string>() && kv.second.is<std::string>()) {
                parsed.env.emplace_back(kv.first.as<std::string>(), kv.second.as<std::string>());
            }
        }
    }

    sol::object clear_env_obj = opts.get<sol::object>("clear-env");
    if (clear_env_obj.valid() && clear_env_obj.is<bool>()) {
        parsed.clear_env = clear_env_obj.as<bool>();
    }

    sol::object timeout_obj = opts.get<sol::object>("timeout");
    if (timeout_obj.valid() && !timeout_obj.is<sol::lua_nil_t>()) {
        double timeout = 0.0;
        if (timeout_obj.is<double>()) {
            timeout = timeout_obj.as<double>();
        } else if (timeout_obj.is<int>()) {
            timeout = static_cast<double>(timeout_obj.as<int>());
        } else if (timeout_obj.is<uint64_t>()) {
            timeout = static_cast<double>(timeout_obj.as<uint64_t>());
        } else {
            throw sol::error("process timeout must be a number");
        }
        if (timeout > 0.0) {
            parsed.timeout_seconds = timeout;
        }
    }

    sol::object stdin_obj = opts.get<sol::object>("stdin");
    if (stdin_obj.valid() && !stdin_obj.is<sol::lua_nil_t>()) {
        if (!stdin_obj.is<std::string>()) {
            throw sol::error("process stdin must be a string");
        }
        parsed.stdin_data = stdin_obj.as<std::string>();
    }

    sol::object merge_stderr_obj = opts.get<sol::object>("merge-stderr");
    if (merge_stderr_obj.valid() && merge_stderr_obj.is<bool>()) {
        parsed.merge_stderr = merge_stderr_obj.as<bool>();
    }

    return parsed;
}

void setup_child_env(const ProcessArgs& args)
{
    if (args.clear_env) {
        clearenv();
    }
    for (const auto& [key, value] : args.env) {
        setenv(key.c_str(), value.c_str(), 1);
    }
}

ProcessResult run_process_sync(const ProcessArgs& args)
{
    int stdout_pipe[2] = { -1, -1 };
    int stderr_pipe[2] = { -1, -1 };
    int stdin_pipe[2] = { -1, -1 };

    if (pipe(stdout_pipe) != 0) {
        throw sol::error("process.run failed to create stdout pipe");
    }
    if (!args.merge_stderr && pipe(stderr_pipe) != 0) {
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        throw sol::error("process.run failed to create stderr pipe");
    }
    if (args.stdin_data.has_value() && pipe(stdin_pipe) != 0) {
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        if (!args.merge_stderr) {
            close(stderr_pipe[0]);
            close(stderr_pipe[1]);
        }
        throw sol::error("process.run failed to create stdin pipe");
    }

    pid_t pid = fork();
    if (pid < 0) {
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        if (!args.merge_stderr) {
            close(stderr_pipe[0]);
            close(stderr_pipe[1]);
        }
        if (stdin_pipe[0] != -1) {
            close(stdin_pipe[0]);
            close(stdin_pipe[1]);
        }
        throw sol::error("process.run failed to fork");
    }

    if (pid == 0) {
        // Child process
        setpgid(0, 0);

        dup2(stdout_pipe[1], STDOUT_FILENO);
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);

        if (args.merge_stderr) {
            dup2(STDOUT_FILENO, STDERR_FILENO);
        } else {
            dup2(stderr_pipe[1], STDERR_FILENO);
            close(stderr_pipe[0]);
            close(stderr_pipe[1]);
        }

        if (stdin_pipe[0] != -1) {
            dup2(stdin_pipe[0], STDIN_FILENO);
            close(stdin_pipe[0]);
            close(stdin_pipe[1]);
        } else {
            int devnull = open("/dev/null", O_RDONLY);
            if (devnull >= 0) {
                dup2(devnull, STDIN_FILENO);
                close(devnull);
            }
        }

        if (args.cwd.has_value()) {
            if (chdir(args.cwd->c_str()) != 0) {
                dprintf(STDERR_FILENO, "process failed to chdir to %s: %s\n",
                    args.cwd->c_str(), strerror(errno));
                _exit(126);
            }
        }

        setup_child_env(args);

        std::vector<char*> argv;
        for (const auto& arg : args.args) {
            argv.push_back(const_cast<char*>(arg.c_str()));
        }
        argv.push_back(nullptr);

        execvp(argv[0], argv.data());
        dprintf(STDERR_FILENO, "process failed to exec %s: %s\n",
            argv[0], strerror(errno));
        _exit(127);
    }

    // Parent process
    // Set process group from parent side too, to avoid race condition with child's setpgid
    setpgid(pid, pid);

    close(stdout_pipe[1]);
    if (!args.merge_stderr) {
        close(stderr_pipe[1]);
    }
    if (stdin_pipe[0] != -1) {
        close(stdin_pipe[0]);
    }

    set_nonblocking(stdout_pipe[0]);
    if (!args.merge_stderr) {
        set_nonblocking(stderr_pipe[0]);
    }
    if (stdin_pipe[1] != -1) {
        set_nonblocking(stdin_pipe[1]);
    }

    ProcessResult result;
    bool stdout_open = true;
    bool stderr_open = !args.merge_stderr;
    bool child_done = false;
    int status = 0;

    // Write stdin data
    std::size_t stdin_written = 0;
    const std::string* stdin_data = args.stdin_data.has_value() ? &args.stdin_data.value() : nullptr;

    auto start = std::chrono::steady_clock::now();

    while (stdout_open || stderr_open || !child_done) {
        if (!child_done) {
            pid_t wait_result = waitpid(pid, &status, WNOHANG);
            if (wait_result == pid) {
                child_done = true;
            }
        }

        // Check timeout
        if (!child_done && args.timeout_seconds.has_value()) {
            auto now = std::chrono::steady_clock::now();
            double elapsed = std::chrono::duration<double>(now - start).count();
            if (elapsed >= args.timeout_seconds.value()) {
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
                    struct timespec sleep_time
                    {
                        0, 10 * 1000 * 1000
                    };
                    nanosleep(&sleep_time, nullptr);
                }
            }
        }

        // Write stdin if any
        if (stdin_pipe[1] != -1 && stdin_data != nullptr && stdin_written < stdin_data->size()) {
            ssize_t written = write(stdin_pipe[1],
                stdin_data->data() + stdin_written,
                stdin_data->size() - stdin_written);
            if (written > 0) {
                stdin_written += static_cast<std::size_t>(written);
            }
            if (stdin_written >= stdin_data->size()) {
                close(stdin_pipe[1]);
                stdin_pipe[1] = -1;
            }
        } else if (stdin_pipe[1] != -1 && (stdin_data == nullptr || stdin_written >= stdin_data->size())) {
            close(stdin_pipe[1]);
            stdin_pipe[1] = -1;
        }

        if (!stdout_open && !stderr_open) {
            if (child_done) {
                break;
            }
            struct timespec sleep_time
            {
                0, 5 * 1000 * 1000
            };
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
        if (!child_done && args.timeout_seconds.has_value()) {
            auto now = std::chrono::steady_clock::now();
            double elapsed = std::chrono::duration<double>(now - start).count();
            double remaining = args.timeout_seconds.value() - elapsed;
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
                    } else if (!args.merge_stderr && entry.fd == stderr_pipe[0]) {
                        stderr_open = drain_fd(stderr_pipe[0], result.stderr_text);
                    }
                } else if ((entry.revents & (POLLHUP | POLLERR | POLLNVAL)) != 0) {
                    if (entry.fd == stdout_pipe[0]) {
                        stdout_open = drain_fd(stdout_pipe[0], result.stdout_text);
                    } else if (!args.merge_stderr && entry.fd == stderr_pipe[0]) {
                        stderr_open = drain_fd(stderr_pipe[0], result.stderr_text);
                    }
                }
            }
        }
    }

    close(stdout_pipe[0]);
    if (!args.merge_stderr) {
        close(stderr_pipe[0]);
    }
    if (stdin_pipe[1] != -1) {
        close(stdin_pipe[1]);
    }

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

sol::table make_result_table(sol::state_view lua, const ProcessResult& result)
{
    sol::table output = lua.create_table();
    output["exit-code"] = result.exit_code;
    output["signal"] = result.signal > 0 ? sol::make_object(lua, result.signal)
                                         : sol::make_object(lua, sol::lua_nil);
    output["timed-out"] = result.timed_out;
    output["stdout"] = result.stdout_text;
    output["stderr"] = result.stderr_text;
    output["duration-ms"] = result.duration_ms;
    return output;
}

ProcessManager* get_process_manager(sol::state& lua)
{
    sol::object obj = lua["process-manager-handle"];
    if (obj.is<ProcessManager*>()) {
        return obj.as<ProcessManager*>();
    }
    return nullptr;
}

uint64_t spawn_process(ProcessManager& mgr, const ProcessArgs& args, sol::optional<sol::function> callback)
{
    int stdout_pipe[2] = { -1, -1 };
    int stderr_pipe[2] = { -1, -1 };
    int stdin_pipe[2] = { -1, -1 };

    if (pipe(stdout_pipe) != 0) {
        throw sol::error("process.spawn failed to create stdout pipe");
    }
    if (!args.merge_stderr && pipe(stderr_pipe) != 0) {
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        throw sol::error("process.spawn failed to create stderr pipe");
    }
    if (pipe(stdin_pipe) != 0) {
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        if (!args.merge_stderr) {
            close(stderr_pipe[0]);
            close(stderr_pipe[1]);
        }
        throw sol::error("process.spawn failed to create stdin pipe");
    }

    pid_t pid = fork();
    if (pid < 0) {
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        if (!args.merge_stderr) {
            close(stderr_pipe[0]);
            close(stderr_pipe[1]);
        }
        close(stdin_pipe[0]);
        close(stdin_pipe[1]);
        throw sol::error("process.spawn failed to fork");
    }

    if (pid == 0) {
        // Child process
        setpgid(0, 0);

        dup2(stdout_pipe[1], STDOUT_FILENO);
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);

        if (args.merge_stderr) {
            dup2(STDOUT_FILENO, STDERR_FILENO);
        } else {
            dup2(stderr_pipe[1], STDERR_FILENO);
            close(stderr_pipe[0]);
            close(stderr_pipe[1]);
        }

        dup2(stdin_pipe[0], STDIN_FILENO);
        close(stdin_pipe[0]);
        close(stdin_pipe[1]);

        if (args.cwd.has_value()) {
            if (chdir(args.cwd->c_str()) != 0) {
                dprintf(STDERR_FILENO, "process failed to chdir to %s: %s\n",
                    args.cwd->c_str(), strerror(errno));
                _exit(126);
            }
        }

        setup_child_env(args);

        std::vector<char*> argv;
        for (const auto& arg : args.args) {
            argv.push_back(const_cast<char*>(arg.c_str()));
        }
        argv.push_back(nullptr);

        execvp(argv[0], argv.data());
        dprintf(STDERR_FILENO, "process failed to exec %s: %s\n",
            argv[0], strerror(errno));
        _exit(127);
    }

    // Parent process
    // Set process group from parent side too, to avoid race condition with child's setpgid
    setpgid(pid, pid);

    close(stdout_pipe[1]);
    if (!args.merge_stderr) {
        close(stderr_pipe[1]);
    }
    close(stdin_pipe[0]);

    set_nonblocking(stdout_pipe[0]);
    set_cloexec(stdout_pipe[0]);
    if (!args.merge_stderr) {
        set_nonblocking(stderr_pipe[0]);
        set_cloexec(stderr_pipe[0]);
    }
    set_nonblocking(stdin_pipe[1]);
    set_cloexec(stdin_pipe[1]);

    std::lock_guard<std::mutex> lock(mgr.mutex);
    uint64_t id = mgr.next_id++;

    SpawnedProcess proc;
    proc.id = id;
    proc.pid = pid;
    proc.stdout_fd = stdout_pipe[0];
    proc.stderr_fd = args.merge_stderr ? -1 : stderr_pipe[0];
    proc.stdin_fd = stdin_pipe[1];
    proc.stdin_closed = false;
    proc.start_time = std::chrono::steady_clock::now();
    proc.timeout_seconds = args.timeout_seconds;
    proc.merge_stderr = args.merge_stderr;

    if (callback.has_value()) {
        proc.callback_id = lua_callbacks_register(callback.value());
    }

    // Write initial stdin data if provided
    if (args.stdin_data.has_value() && !args.stdin_data->empty()) {
        const std::string& data = args.stdin_data.value();
        ssize_t written = write(proc.stdin_fd, data.data(), data.size());
        // If we couldn't write it all, we'll need to buffer it
        // For simplicity in this initial version, we write what we can and close
        (void)written;
    }

    mgr.processes[id] = std::move(proc);
    return id;
}

void poll_process(SpawnedProcess& proc)
{
    if (proc.finished) {
        return;
    }

    // Read available data
    if (proc.stdout_fd >= 0) {
        if (!drain_fd(proc.stdout_fd, proc.stdout_buffer)) {
            close(proc.stdout_fd);
            proc.stdout_fd = -1;
        }
    }
    if (proc.stderr_fd >= 0) {
        if (!drain_fd(proc.stderr_fd, proc.stderr_buffer)) {
            close(proc.stderr_fd);
            proc.stderr_fd = -1;
        }
    }

    // Check if child has exited
    int status = 0;
    pid_t wait_result = waitpid(proc.pid, &status, WNOHANG);
    if (wait_result == proc.pid) {
        // Drain any remaining data
        if (proc.stdout_fd >= 0) {
            drain_fd(proc.stdout_fd, proc.stdout_buffer);
            close(proc.stdout_fd);
            proc.stdout_fd = -1;
        }
        if (proc.stderr_fd >= 0) {
            drain_fd(proc.stderr_fd, proc.stderr_buffer);
            close(proc.stderr_fd);
            proc.stderr_fd = -1;
        }
        if (proc.stdin_fd >= 0) {
            close(proc.stdin_fd);
            proc.stdin_fd = -1;
        }

        proc.finished = true;
        proc.result.stdout_text = std::move(proc.stdout_buffer);
        proc.result.stderr_text = std::move(proc.stderr_buffer);

        if (WIFEXITED(status)) {
            proc.result.exit_code = WEXITSTATUS(status);
        } else if (WIFSIGNALED(status)) {
            proc.result.signal = WTERMSIG(status);
            proc.result.exit_code = 128 + proc.result.signal;
        }

        auto end = std::chrono::steady_clock::now();
        proc.result.duration_ms = static_cast<std::uint64_t>(
            std::chrono::duration_cast<std::chrono::milliseconds>(end - proc.start_time).count());
        return;
    }

    // Check timeout
    if (proc.timeout_seconds.has_value()) {
        auto now = std::chrono::steady_clock::now();
        double elapsed = std::chrono::duration<double>(now - proc.start_time).count();
        if (elapsed >= proc.timeout_seconds.value()) {
            proc.result.timed_out = true;
            killpg(proc.pid, SIGTERM);

            auto term_deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(200);
            while (true) {
                pid_t wr = waitpid(proc.pid, &status, WNOHANG);
                if (wr == proc.pid) {
                    break;
                }
                if (std::chrono::steady_clock::now() >= term_deadline) {
                    killpg(proc.pid, SIGKILL);
                    waitpid(proc.pid, &status, 0);
                    break;
                }
                struct timespec sleep_time
                {
                    0, 10 * 1000 * 1000
                };
                nanosleep(&sleep_time, nullptr);
            }

            // Drain remaining
            if (proc.stdout_fd >= 0) {
                drain_fd(proc.stdout_fd, proc.stdout_buffer);
                close(proc.stdout_fd);
                proc.stdout_fd = -1;
            }
            if (proc.stderr_fd >= 0) {
                drain_fd(proc.stderr_fd, proc.stderr_buffer);
                close(proc.stderr_fd);
                proc.stderr_fd = -1;
            }
            if (proc.stdin_fd >= 0) {
                close(proc.stdin_fd);
                proc.stdin_fd = -1;
            }

            proc.finished = true;
            proc.result.stdout_text = std::move(proc.stdout_buffer);
            proc.result.stderr_text = std::move(proc.stderr_buffer);

            if (WIFEXITED(status)) {
                proc.result.exit_code = WEXITSTATUS(status);
            } else if (WIFSIGNALED(status)) {
                proc.result.signal = WTERMSIG(status);
                proc.result.exit_code = 128 + proc.result.signal;
            }

            auto end = std::chrono::steady_clock::now();
            proc.result.duration_ms = static_cast<std::uint64_t>(
                std::chrono::duration_cast<std::chrono::milliseconds>(end - proc.start_time).count());
        }
    }
}

} // namespace

void lua_bind_process(sol::state& lua)
{
    auto* mgr = new ProcessManager();
    lua["process-manager-handle"] = mgr;

    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("process", [mgr](sol::this_state state) {
        sol::state_view lua_view(state);
        sol::table process_table = lua_view.create_table();

        // Synchronous run
        process_table.set_function("run", [](sol::table opts) {
            ProcessArgs args = parse_args(opts);
            ProcessResult result = run_process_sync(args);
            sol::state_view lua_view(opts.lua_state());
            return make_result_table(lua_view, result);
        });

        // Async spawn
        process_table.set_function("spawn", [mgr](sol::table opts, sol::optional<sol::function> callback) {
            ProcessArgs args = parse_args(opts);
            return spawn_process(*mgr, args, callback);
        });

        // Write to stdin of spawned process
        process_table.set_function("write", [mgr](uint64_t id, const std::string& data) {
            std::lock_guard<std::mutex> lock(mgr->mutex);
            auto it = mgr->processes.find(id);
            if (it == mgr->processes.end()) {
                throw sol::error("process.write: invalid process id");
            }
            SpawnedProcess& proc = it->second;
            if (proc.stdin_fd < 0 || proc.stdin_closed) {
                throw sol::error("process.write: stdin is closed");
            }
            ssize_t written = write(proc.stdin_fd, data.data(), data.size());
            return written >= 0 ? static_cast<std::size_t>(written) : 0;
        });

        // Close stdin of spawned process
        process_table.set_function("close-stdin", [mgr](uint64_t id) {
            std::lock_guard<std::mutex> lock(mgr->mutex);
            auto it = mgr->processes.find(id);
            if (it == mgr->processes.end()) {
                return false;
            }
            SpawnedProcess& proc = it->second;
            if (proc.stdin_fd >= 0 && !proc.stdin_closed) {
                close(proc.stdin_fd);
                proc.stdin_fd = -1;
                proc.stdin_closed = true;
                return true;
            }
            return false;
        });

        // Kill spawned process
        process_table.set_function("kill", [mgr](uint64_t id, sol::optional<int> sig) {
            std::lock_guard<std::mutex> lock(mgr->mutex);
            auto it = mgr->processes.find(id);
            if (it == mgr->processes.end()) {
                return false;
            }
            SpawnedProcess& proc = it->second;
            if (proc.finished) {
                return false;
            }
            int signal = sig.value_or(SIGTERM);
            return killpg(proc.pid, signal) == 0;
        });

        // Check if process is still running
        process_table.set_function("running", [mgr](uint64_t id) {
            std::lock_guard<std::mutex> lock(mgr->mutex);
            auto it = mgr->processes.find(id);
            if (it == mgr->processes.end()) {
                return false;
            }
            return !it->second.finished;
        });

        // Poll for completed processes (manual polling mode)
        process_table.set_function("poll", [mgr](sol::this_state state, sol::optional<uint64_t> max_results) {
            sol::state_view lua_view(state);

            std::vector<std::pair<uint64_t, ProcessResult>> completed;
            {
                std::lock_guard<std::mutex> lock(mgr->mutex);

                // Poll all processes
                for (auto& [id, proc] : mgr->processes) {
                    poll_process(proc);
                }

                // Collect completed ones
                std::size_t max = max_results.value_or(0);
                for (auto it = mgr->processes.begin(); it != mgr->processes.end();) {
                    if (it->second.finished) {
                        if (it->second.callback_id == 0) {
                            // No callback, add to poll results
                            completed.emplace_back(it->first, std::move(it->second.result));
                        }
                        it = mgr->processes.erase(it);
                        if (max > 0 && completed.size() >= max) {
                            break;
                        }
                    } else {
                        ++it;
                    }
                }
            }

            sol::table results = lua_view.create_table();
            std::size_t idx = 1;
            for (auto& [id, result] : completed) {
                sol::table entry = make_result_table(lua_view, result);
                entry["id"] = id;
                results[idx++] = entry;
            }
            return results;
        });

        // Get result of specific process (blocks until done)
        process_table.set_function("wait", [mgr](sol::this_state state, uint64_t id) {
            sol::state_view lua_view(state);

            while (true) {
                {
                    std::lock_guard<std::mutex> lock(mgr->mutex);
                    auto it = mgr->processes.find(id);
                    if (it == mgr->processes.end()) {
                        throw sol::error("process.wait: invalid process id");
                    }
                    poll_process(it->second);
                    if (it->second.finished) {
                        ProcessResult result = std::move(it->second.result);
                        // Drop callback if any
                        if (it->second.callback_id != 0) {
                            lua_callbacks_unregister(it->second.callback_id);
                        }
                        mgr->processes.erase(it);
                        return make_result_table(lua_view, result);
                    }
                }
                struct timespec sleep_time
                {
                    0, 10 * 1000 * 1000
                };
                nanosleep(&sleep_time, nullptr);
            }
        });

        return process_table;
    });
}

void lua_process_dispatch(sol::state& lua)
{
    ProcessManager* mgr = get_process_manager(lua);
    if (mgr == nullptr) {
        return;
    }

    std::vector<std::pair<uint64_t, ProcessResult>> to_dispatch;

    {
        std::lock_guard<std::mutex> lock(mgr->mutex);

        // Poll all processes
        for (auto& [id, proc] : mgr->processes) {
            poll_process(proc);
        }

        // Collect finished processes with callbacks
        for (auto it = mgr->processes.begin(); it != mgr->processes.end();) {
            if (it->second.finished && it->second.callback_id != 0) {
                uint64_t cb_id = it->second.callback_id;
                ProcessResult result = std::move(it->second.result);
                it = mgr->processes.erase(it);

                // Enqueue callback
                lua_callbacks_enqueue(cb_id, [result = std::move(result)](sol::state_view lua) {
                    return sol::make_object(lua, make_result_table(lua, result));
                });
            } else {
                ++it;
            }
        }
    }
}

void lua_process_drop(sol::state& lua)
{
    ProcessManager* mgr = get_process_manager(lua);
    if (mgr == nullptr) {
        return;
    }

    {
        std::lock_guard<std::mutex> lock(mgr->mutex);

        // Kill and clean up all remaining processes
        for (auto& [id, proc] : mgr->processes) {
            if (!proc.finished) {
                killpg(proc.pid, SIGKILL);
                int status;
                waitpid(proc.pid, &status, 0);
            }
            if (proc.stdout_fd >= 0) {
                close(proc.stdout_fd);
            }
            if (proc.stderr_fd >= 0) {
                close(proc.stderr_fd);
            }
            if (proc.stdin_fd >= 0) {
                close(proc.stdin_fd);
            }
            if (proc.callback_id != 0) {
                lua_callbacks_unregister(proc.callback_id);
            }
        }
        mgr->processes.clear();
    }

    sol::table package = lua["package"];
    sol::table loaded = package["loaded"];
    loaded["process"] = sol::lua_nil;
    lua["process-manager-handle"] = sol::lua_nil;
    delete mgr;
}
