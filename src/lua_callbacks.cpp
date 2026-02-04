#include <atomic>
#include <chrono>
#include <iostream>
#include <mutex>
#include <optional>
#include <queue>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

#include "lua_callbacks.h"
#include "lua_http.h"
#include "lua_jobs.h"
#include "lua_process.h"

namespace {

struct Pending {
    uint64_t id { 0 };
    std::function<sol::object(sol::state_view)> builder;
};

std::atomic<uint64_t> next_id { 1 };
std::mutex registry_mutex;
std::unordered_map<uint64_t, sol::protected_function> registry;

std::mutex queue_mutex;
std::vector<Pending> pending_queue;

std::optional<uint64_t> parse_optional_u64(const sol::object& value)
{
    if (value.is<uint64_t>()) {
        return value.as<uint64_t>();
    }
    if (value.is<int>()) {
        int asInt = value.as<int>();
        if (asInt < 0) {
            throw sol::error("callbacks.run-loop value must be non-negative");
        }
        return static_cast<uint64_t>(asInt);
    }
    if (value.is<double>()) {
        double asDouble = value.as<double>();
        if (asDouble < 0.0) {
            throw sol::error("callbacks.run-loop value must be non-negative");
        }
        return static_cast<uint64_t>(asDouble);
    }
    return std::nullopt;
}

bool call_until(const sol::function& fn)
{
    sol::protected_function pf = fn;
    sol::protected_function_result result = pf();
    if (!result.valid()) {
        sol::error err = result;
        throw sol::error(err.what());
    }
    sol::object value = result.get<sol::object>();
    if (value.is<bool>()) {
        return value.as<bool>();
    }
    return value.valid() && value != sol::lua_nil;
}

} // namespace

void lua_bind_callbacks(sol::state& lua, sol::table& lua_space)
{
    sol::table package = lua["package"];
    sol::table loaded = package["loaded"];
    sol::object loaded_cb = loaded["callbacks"];
    sol::table cb;
    if (loaded_cb.is<sol::table>()) {
        cb = loaded_cb.as<sol::table>();
    } else {
        cb = lua.create_table();
        loaded["callbacks"] = cb;
    }

    cb.set_function("register", [](sol::function fn) {
        return lua_callbacks_register(std::move(fn));
    });
    cb.set_function("unregister", [](uint64_t id) {
        return lua_callbacks_unregister(id);
    });
    cb.set_function("enqueue", [](uint64_t id, sol::object payload) {
        lua_callbacks_enqueue(id, [payload](sol::state_view lua) {
            return sol::make_object(lua, payload);
        });
    });
    cb.set_function("dispatch", [&lua](sol::optional<uint64_t> max_results) {
        lua_callbacks_dispatch(lua, max_results.value_or(0));
    });
    cb.set_function("run-loop", [&lua](sol::optional<sol::table> opts) {
        bool poll_jobs = true;
        bool poll_http = true;
        bool poll_process = false;
        uint64_t sleep_ms = 1;
        uint64_t timeout_ms = 0;
        sol::optional<sol::function> until;

        if (opts) {
            sol::optional<bool> pollJobs = opts->get<sol::optional<bool>>("poll-jobs");
            sol::optional<bool> pollHttp = opts->get<sol::optional<bool>>("poll-http");
            sol::optional<bool> pollProcess = opts->get<sol::optional<bool>>("poll-process");
            sol::optional<sol::function> untilFn = opts->get<sol::optional<sol::function>>("until");
            if (pollJobs) {
                poll_jobs = *pollJobs;
            }
            if (pollHttp) {
                poll_http = *pollHttp;
            }
            if (pollProcess) {
                poll_process = *pollProcess;
            }
            if (untilFn) {
                until = untilFn;
            }
            sol::object sleepObj = opts->get<sol::object>("sleep-ms");
            if (sleepObj.valid() && sleepObj != sol::lua_nil) {
                auto parsed = parse_optional_u64(sleepObj);
                if (parsed) {
                    sleep_ms = *parsed;
                } else {
                    throw sol::error("callbacks.run-loop sleep-ms must be a number");
                }
            }
            sol::object timeoutObj = opts->get<sol::object>("timeout-ms");
            if (timeoutObj.valid() && timeoutObj != sol::lua_nil) {
                auto parsed = parse_optional_u64(timeoutObj);
                if (parsed) {
                    timeout_ms = *parsed;
                } else {
                    throw sol::error("callbacks.run-loop timeout-ms must be a number");
                }
            }
        }

        auto start = std::chrono::steady_clock::now();
        while (true) {
            if (poll_jobs) {
                lua_jobs_dispatch_active(lua);
            }
            if (poll_http) {
                lua_http_dispatch(lua);
            }
            if (poll_process) {
                lua_process_dispatch(lua);
            }
            lua_callbacks_dispatch(lua);

            if (until && call_until(until.value())) {
                return true;
            }

            if (timeout_ms > 0) {
                auto now = std::chrono::steady_clock::now();
                auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - start).count();
                if (elapsed >= static_cast<long long>(timeout_ms)) {
                    return false;
                }
            }

            if (sleep_ms > 0) {
                std::this_thread::sleep_for(std::chrono::milliseconds(sleep_ms));
            }
        }
    });

    lua_space["callbacks"] = cb;

    sol::table preload = package["preload"];
    preload.set_function("callbacks", [cb](sol::this_state state) mutable {
        (void)state;
        return cb;
    });
}

uint64_t lua_callbacks_register(sol::function fn)
{
    sol::protected_function pf = std::move(fn);
    uint64_t id = next_id.fetch_add(1);
    std::lock_guard<std::mutex> lock(registry_mutex);
    registry[id] = std::move(pf);
    return id;
}

bool lua_callbacks_unregister(uint64_t id)
{
    std::lock_guard<std::mutex> lock(registry_mutex);
    return registry.erase(id) > 0;
}

void lua_callbacks_enqueue(uint64_t id, std::function<sol::object(sol::state_view)> payload_builder)
{
    Pending p;
    p.id = id;
    p.builder = std::move(payload_builder);
    std::lock_guard<std::mutex> lock(queue_mutex);
    pending_queue.push_back(std::move(p));
}

void lua_callbacks_dispatch(sol::state_view lua, std::size_t max_results)
{
    std::vector<Pending> to_process;
    {
        std::lock_guard<std::mutex> lock(queue_mutex);
        if (pending_queue.empty()) {
            return;
        }
        if (max_results == 0 || max_results >= pending_queue.size()) {
            to_process.swap(pending_queue);
        } else {
            to_process.reserve(max_results);
            auto begin = pending_queue.begin();
            auto split = begin + static_cast<std::ptrdiff_t>(max_results);
            to_process.insert(to_process.end(),
                              std::make_move_iterator(begin),
                              std::make_move_iterator(split));
            pending_queue.erase(begin, split);
        }
    }

    std::vector<Pending> deferred;

    for (auto& item : to_process) {
        sol::protected_function callback;
        {
            std::lock_guard<std::mutex> lock(registry_mutex);
            auto it = registry.find(item.id);
            if (it != registry.end()) {
                callback = it->second;
            }
        }
        if (!callback.valid()) {
            continue;
        }
        sol::object payload = item.builder ? item.builder(lua) : sol::lua_nil;
        sol::protected_function_result result = callback(payload);
        if (!result.valid()) {
            sol::error err = result;
            std::cerr << "[callbacks] invocation failed for id " << item.id << ": " << err.what() << "\n";
        }
    }
}

void lua_callbacks_shutdown()
{
    {
        std::lock_guard<std::mutex> lock(registry_mutex);
        registry.clear();
    }
    {
        std::lock_guard<std::mutex> lock(queue_mutex);
        pending_queue.clear();
    }
}
