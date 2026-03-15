#include "lua_process.h"

#include "lua_callbacks.h"

#define NOMINMAX
#include <windows.h>

#include <chrono>
#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

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
    HANDLE process_handle { nullptr };
    HANDLE thread_handle { nullptr };
    HANDLE stdout_read { nullptr };
    HANDLE stderr_read { nullptr };
    HANDLE stdin_write { nullptr };
    bool stdin_closed { false };
    std::string stdout_buffer;
    std::string stderr_buffer;
    std::chrono::steady_clock::time_point start_time;
    std::optional<double> timeout_seconds;
    bool finished { false };
    ProcessResult result;
    uint64_t callback_id { 0 };
};

struct ProcessManager
{
    std::mutex mutex;
    std::unordered_map<uint64_t, SpawnedProcess> processes;
    uint64_t next_id { 1 };
};

void close_handle(HANDLE& handle)
{
    if (handle != nullptr && handle != INVALID_HANDLE_VALUE) {
        CloseHandle(handle);
    }
    handle = nullptr;
}

std::string win32_message(DWORD code)
{
    LPSTR buffer = nullptr;
    DWORD size = FormatMessageA(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr,
        code,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        reinterpret_cast<LPSTR>(&buffer),
        0,
        nullptr);
    std::string out;
    if (size > 0 && buffer != nullptr) {
        out.assign(buffer, size);
        while (!out.empty() && (out.back() == '\n' || out.back() == '\r')) {
            out.pop_back();
        }
        LocalFree(buffer);
    }
    if (out.empty()) {
        out = "win32 error " + std::to_string(code);
    }
    return out;
}

std::wstring utf8_to_wide(const std::string& text)
{
    if (text.empty()) {
        return L"";
    }
    int needed = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0);
    if (needed <= 0) {
        throw sol::error("Failed to convert UTF-8 to UTF-16");
    }
    std::wstring wide(static_cast<size_t>(needed), L'\0');
    if (MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), wide.data(), needed) <= 0) {
        throw sol::error("Failed to convert UTF-8 to UTF-16");
    }
    return wide;
}

std::string quote_windows_arg(const std::string& arg)
{
    if (arg.empty()) {
        return "\"\"";
    }

    bool needs_quotes = false;
    for (char ch : arg) {
        if (ch == ' ' || ch == '\t' || ch == '"') {
            needs_quotes = true;
            break;
        }
    }
    if (!needs_quotes) {
        return arg;
    }

    std::string out;
    out.push_back('"');
    std::size_t backslashes = 0;
    for (char ch : arg) {
        if (ch == '\\') {
            backslashes += 1;
            continue;
        }
        if (ch == '"') {
            out.append(backslashes * 2 + 1, '\\');
            out.push_back('"');
            backslashes = 0;
            continue;
        }
        out.append(backslashes, '\\');
        backslashes = 0;
        out.push_back(ch);
    }
    out.append(backslashes * 2, '\\');
    out.push_back('"');
    return out;
}

std::string build_command_line(const std::vector<std::string>& args)
{
    std::string line;
    for (std::size_t i = 0; i < args.size(); ++i) {
        if (i > 0) {
            line.push_back(' ');
        }
        line += quote_windows_arg(args[i]);
    }
    return line;
}

std::vector<wchar_t> build_environment_block(const ProcessArgs& args)
{
    std::vector<std::wstring> entries;

    if (!args.clear_env) {
        LPWCH env_strings = GetEnvironmentStringsW();
        if (env_strings != nullptr) {
            for (LPCWSTR it = env_strings; *it != L'\0';) {
                std::wstring entry(it);
                if (!entry.empty()) {
                    entries.push_back(entry);
                }
                it += entry.size() + 1;
            }
            FreeEnvironmentStringsW(env_strings);
        }
    }

    for (const auto& [k_utf8, v_utf8] : args.env) {
        std::wstring key = utf8_to_wide(k_utf8);
        std::wstring value = utf8_to_wide(v_utf8);
        std::wstring pref = key + L"=";

        bool replaced = false;
        for (auto& entry : entries) {
            if (entry.rfind(pref, 0) == 0) {
                entry = pref + value;
                replaced = true;
                break;
            }
        }
        if (!replaced) {
            entries.push_back(pref + value);
        }
    }

    std::vector<wchar_t> block;
    for (const auto& entry : entries) {
        block.insert(block.end(), entry.begin(), entry.end());
        block.push_back(L'\0');
    }
    block.push_back(L'\0');
    return block;
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

bool drain_pipe_nonblocking(HANDLE pipe, std::string& out)
{
    if (pipe == nullptr || pipe == INVALID_HANDLE_VALUE) {
        return false;
    }

    char buffer[4096];
    while (true) {
        DWORD available = 0;
        BOOL peek_ok = PeekNamedPipe(pipe, nullptr, 0, nullptr, &available, nullptr);
        if (!peek_ok) {
            DWORD err = GetLastError();
            if (err == ERROR_BROKEN_PIPE || err == ERROR_PIPE_NOT_CONNECTED) {
                return false;
            }
            return false;
        }

        if (available == 0) {
            return true;
        }

        DWORD to_read = available;
        if (to_read > sizeof(buffer)) {
            to_read = sizeof(buffer);
        }

        DWORD read_bytes = 0;
        BOOL read_ok = ReadFile(pipe, buffer, to_read, &read_bytes, nullptr);
        if (!read_ok || read_bytes == 0) {
            DWORD err = GetLastError();
            if (err == ERROR_BROKEN_PIPE || err == ERROR_PIPE_NOT_CONNECTED) {
                return false;
            }
            return false;
        }
        out.append(buffer, static_cast<std::size_t>(read_bytes));
    }
}

void finalize_process(SpawnedProcess& proc)
{
    if (proc.finished) {
        return;
    }

    if (proc.stdout_read != nullptr) {
        drain_pipe_nonblocking(proc.stdout_read, proc.stdout_buffer);
    }
    if (proc.stderr_read != nullptr) {
        drain_pipe_nonblocking(proc.stderr_read, proc.stderr_buffer);
    }

    DWORD exit_code = 1;
    if (!GetExitCodeProcess(proc.process_handle, &exit_code)) {
        exit_code = 1;
    }

    proc.finished = true;
    proc.result.stdout_text = std::move(proc.stdout_buffer);
    proc.result.stderr_text = std::move(proc.stderr_buffer);
    proc.result.exit_code = static_cast<int>(exit_code);

    auto end = std::chrono::steady_clock::now();
    proc.result.duration_ms = static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(end - proc.start_time).count());

    close_handle(proc.stdin_write);
    close_handle(proc.stdout_read);
    close_handle(proc.stderr_read);
    close_handle(proc.thread_handle);
    close_handle(proc.process_handle);
}

void poll_process(SpawnedProcess& proc)
{
    if (proc.finished) {
        return;
    }

    if (proc.stdout_read != nullptr) {
        if (!drain_pipe_nonblocking(proc.stdout_read, proc.stdout_buffer)) {
            close_handle(proc.stdout_read);
        }
    }
    if (proc.stderr_read != nullptr) {
        if (!drain_pipe_nonblocking(proc.stderr_read, proc.stderr_buffer)) {
            close_handle(proc.stderr_read);
        }
    }

    if (proc.timeout_seconds.has_value()) {
        auto now = std::chrono::steady_clock::now();
        double elapsed = std::chrono::duration<double>(now - proc.start_time).count();
        if (elapsed >= proc.timeout_seconds.value()) {
            proc.result.timed_out = true;
            TerminateProcess(proc.process_handle, 1);
        }
    }

    DWORD wait_result = WaitForSingleObject(proc.process_handle, 0);
    if (wait_result == WAIT_OBJECT_0) {
        finalize_process(proc);
    }
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
    SECURITY_ATTRIBUTES sa;
    sa.nLength = sizeof(SECURITY_ATTRIBUTES);
    sa.lpSecurityDescriptor = nullptr;
    sa.bInheritHandle = TRUE;

    HANDLE child_stdout_read = nullptr;
    HANDLE child_stdout_write = nullptr;
    HANDLE child_stderr_read = nullptr;
    HANDLE child_stderr_write = nullptr;
    HANDLE child_stdin_read = nullptr;
    HANDLE child_stdin_write = nullptr;

    if (!CreatePipe(&child_stdout_read, &child_stdout_write, &sa, 0)) {
        throw sol::error("process.spawn failed to create stdout pipe: " + win32_message(GetLastError()));
    }
    if (!SetHandleInformation(child_stdout_read, HANDLE_FLAG_INHERIT, 0)) {
        close_handle(child_stdout_read);
        close_handle(child_stdout_write);
        throw sol::error("process.spawn failed to set stdout pipe handle flags");
    }

    if (!args.merge_stderr) {
        if (!CreatePipe(&child_stderr_read, &child_stderr_write, &sa, 0)) {
            close_handle(child_stdout_read);
            close_handle(child_stdout_write);
            throw sol::error("process.spawn failed to create stderr pipe: " + win32_message(GetLastError()));
        }
        if (!SetHandleInformation(child_stderr_read, HANDLE_FLAG_INHERIT, 0)) {
            close_handle(child_stdout_read);
            close_handle(child_stdout_write);
            close_handle(child_stderr_read);
            close_handle(child_stderr_write);
            throw sol::error("process.spawn failed to set stderr pipe handle flags");
        }
    }

    if (!CreatePipe(&child_stdin_read, &child_stdin_write, &sa, 0)) {
        close_handle(child_stdout_read);
        close_handle(child_stdout_write);
        close_handle(child_stderr_read);
        close_handle(child_stderr_write);
        throw sol::error("process.spawn failed to create stdin pipe: " + win32_message(GetLastError()));
    }
    if (!SetHandleInformation(child_stdin_write, HANDLE_FLAG_INHERIT, 0)) {
        close_handle(child_stdout_read);
        close_handle(child_stdout_write);
        close_handle(child_stderr_read);
        close_handle(child_stderr_write);
        close_handle(child_stdin_read);
        close_handle(child_stdin_write);
        throw sol::error("process.spawn failed to set stdin pipe handle flags");
    }

    STARTUPINFOW si;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = child_stdin_read;
    si.hStdOutput = child_stdout_write;
    si.hStdError = args.merge_stderr ? child_stdout_write : child_stderr_write;

    PROCESS_INFORMATION pi;
    ZeroMemory(&pi, sizeof(pi));

    std::string cmd_line_utf8 = build_command_line(args.args);
    std::wstring cmd_line_wide = utf8_to_wide(cmd_line_utf8);
    std::vector<wchar_t> cmd_line_mut(cmd_line_wide.begin(), cmd_line_wide.end());
    cmd_line_mut.push_back(L'\0');

    std::wstring cwd_wide;
    LPCWSTR cwd_ptr = nullptr;
    if (args.cwd.has_value()) {
        cwd_wide = utf8_to_wide(args.cwd.value());
        cwd_ptr = cwd_wide.c_str();
    }

    std::vector<wchar_t> env_block;
    LPVOID env_ptr = nullptr;
    if (args.clear_env || !args.env.empty()) {
        env_block = build_environment_block(args);
        env_ptr = env_block.data();
    }

    DWORD flags = CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP;

    BOOL created = CreateProcessW(
        nullptr,
        cmd_line_mut.data(),
        nullptr,
        nullptr,
        TRUE,
        flags,
        env_ptr,
        cwd_ptr,
        &si,
        &pi);

    close_handle(child_stdout_write);
    close_handle(child_stdin_read);
    if (!args.merge_stderr) {
        close_handle(child_stderr_write);
    }

    if (!created) {
        DWORD create_error = GetLastError();
        close_handle(child_stdout_read);
        close_handle(child_stderr_read);
        close_handle(child_stdin_write);

        if (create_error == ERROR_FILE_NOT_FOUND || create_error == ERROR_PATH_NOT_FOUND) {
            std::lock_guard<std::mutex> lock(mgr.mutex);
            uint64_t id = mgr.next_id++;

            SpawnedProcess proc;
            proc.id = id;
            proc.finished = true;
            proc.start_time = std::chrono::steady_clock::now();
            proc.result.exit_code = 127;
            proc.result.stderr_text =
                "process failed to exec " + args.args.front() + ": " + win32_message(create_error) + "\n";
            proc.result.duration_ms = 0;

            if (callback.has_value()) {
                proc.callback_id = lua_callbacks_register(callback.value());
            }

            mgr.processes[id] = std::move(proc);
            return id;
        }

        throw sol::error("process.spawn failed: " + win32_message(create_error));
    }

    {
        std::lock_guard<std::mutex> lock(mgr.mutex);
        uint64_t id = mgr.next_id++;

        SpawnedProcess proc;
        proc.id = id;
        proc.process_handle = pi.hProcess;
        proc.thread_handle = pi.hThread;
        proc.stdout_read = child_stdout_read;
        proc.stderr_read = args.merge_stderr ? nullptr : child_stderr_read;
        proc.stdin_write = child_stdin_write;
        proc.stdin_closed = false;
        proc.start_time = std::chrono::steady_clock::now();
        proc.timeout_seconds = args.timeout_seconds;

        if (callback.has_value()) {
            proc.callback_id = lua_callbacks_register(callback.value());
        }

        if (args.stdin_data.has_value() && !args.stdin_data->empty()) {
            DWORD written = 0;
            WriteFile(proc.stdin_write,
                args.stdin_data->data(),
                static_cast<DWORD>(args.stdin_data->size()),
                &written,
                nullptr);
        }

        mgr.processes[id] = std::move(proc);
        return id;
    }
}

ProcessResult wait_for_process(ProcessManager& mgr, uint64_t id)
{
    while (true) {
        {
            std::lock_guard<std::mutex> lock(mgr.mutex);
            auto it = mgr.processes.find(id);
            if (it == mgr.processes.end()) {
                throw sol::error("process.wait: invalid process id");
            }

            poll_process(it->second);
            if (it->second.finished) {
                ProcessResult result = std::move(it->second.result);
                if (it->second.callback_id != 0) {
                    lua_callbacks_unregister(it->second.callback_id);
                }
                mgr.processes.erase(it);
                return result;
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
}

ProcessResult run_process_sync(ProcessManager& mgr, const ProcessArgs& args)
{
    sol::optional<sol::function> callback;
    uint64_t id = spawn_process(mgr, args, callback);

    {
        std::lock_guard<std::mutex> lock(mgr.mutex);
        auto it = mgr.processes.find(id);
        if (it != mgr.processes.end()) {
            close_handle(it->second.stdin_write);
            it->second.stdin_closed = true;
        }
    }

    return wait_for_process(mgr, id);
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

        process_table.set_function("run", [mgr](sol::table opts) {
            ProcessArgs args = parse_args(opts);
            ProcessResult result = run_process_sync(*mgr, args);
            sol::state_view view(opts.lua_state());
            return make_result_table(view, result);
        });

        process_table.set_function("spawn", [mgr](sol::table opts, sol::optional<sol::function> callback) {
            ProcessArgs args = parse_args(opts);
            return spawn_process(*mgr, args, callback);
        });

        process_table.set_function("write", [mgr](uint64_t id, const std::string& data) {
            std::lock_guard<std::mutex> lock(mgr->mutex);
            auto it = mgr->processes.find(id);
            if (it == mgr->processes.end()) {
                throw sol::error("process.write: invalid process id");
            }
            SpawnedProcess& proc = it->second;
            if (proc.stdin_write == nullptr || proc.stdin_closed) {
                throw sol::error("process.write: stdin is closed");
            }
            DWORD written = 0;
            BOOL ok = WriteFile(proc.stdin_write, data.data(), static_cast<DWORD>(data.size()), &written, nullptr);
            if (!ok) {
                DWORD err = GetLastError();
                if (err == ERROR_BROKEN_PIPE || err == ERROR_NO_DATA) {
                    return static_cast<std::size_t>(0);
                }
                throw sol::error("process.write failed: " + win32_message(err));
            }
            return static_cast<std::size_t>(written);
        });

        process_table.set_function("close-stdin", [mgr](uint64_t id) {
            std::lock_guard<std::mutex> lock(mgr->mutex);
            auto it = mgr->processes.find(id);
            if (it == mgr->processes.end()) {
                return false;
            }
            SpawnedProcess& proc = it->second;
            if (proc.stdin_write != nullptr && !proc.stdin_closed) {
                close_handle(proc.stdin_write);
                proc.stdin_closed = true;
                return true;
            }
            return false;
        });

        process_table.set_function("kill", [mgr](uint64_t id, sol::optional<int>) {
            std::lock_guard<std::mutex> lock(mgr->mutex);
            auto it = mgr->processes.find(id);
            if (it == mgr->processes.end() || it->second.finished) {
                return false;
            }
            return TerminateProcess(it->second.process_handle, 1) == TRUE;
        });

        process_table.set_function("running", [mgr](uint64_t id) {
            std::lock_guard<std::mutex> lock(mgr->mutex);
            auto it = mgr->processes.find(id);
            if (it == mgr->processes.end()) {
                return false;
            }
            poll_process(it->second);
            return !it->second.finished;
        });

        process_table.set_function("poll", [mgr](sol::this_state state, sol::optional<uint64_t> max_results) {
            sol::state_view view(state);
            std::vector<std::pair<uint64_t, ProcessResult>> completed;

            {
                std::lock_guard<std::mutex> lock(mgr->mutex);

                for (auto& [id, proc] : mgr->processes) {
                    poll_process(proc);
                    (void)id;
                }

                std::size_t max = max_results.value_or(0);
                for (auto it = mgr->processes.begin(); it != mgr->processes.end();) {
                    if (it->second.finished) {
                        if (it->second.callback_id == 0) {
                            completed.emplace_back(it->first, std::move(it->second.result));
                        } else {
                            lua_callbacks_unregister(it->second.callback_id);
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

            sol::table results = view.create_table();
            std::size_t idx = 1;
            for (auto& [id, result] : completed) {
                sol::table entry = make_result_table(view, result);
                entry["id"] = id;
                results[idx++] = entry;
            }
            return results;
        });

        process_table.set_function("wait", [mgr](sol::this_state state, uint64_t id) {
            sol::state_view view(state);
            ProcessResult result = wait_for_process(*mgr, id);
            return make_result_table(view, result);
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

    {
        std::lock_guard<std::mutex> lock(mgr->mutex);

        for (auto& [id, proc] : mgr->processes) {
            poll_process(proc);
            (void)id;
        }

        for (auto it = mgr->processes.begin(); it != mgr->processes.end();) {
            if (it->second.finished && it->second.callback_id != 0) {
                uint64_t cb_id = it->second.callback_id;
                ProcessResult result = std::move(it->second.result);
                it = mgr->processes.erase(it);

                lua_callbacks_enqueue(cb_id, [result = std::move(result)](sol::state_view view) {
                    return sol::make_object(view, make_result_table(view, result));
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

        for (auto& [id, proc] : mgr->processes) {
            (void)id;
            if (!proc.finished && proc.process_handle != nullptr) {
                TerminateProcess(proc.process_handle, 1);
                WaitForSingleObject(proc.process_handle, 1000);
            }

            close_handle(proc.stdin_write);
            close_handle(proc.stdout_read);
            close_handle(proc.stderr_read);
            close_handle(proc.thread_handle);
            close_handle(proc.process_handle);

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
