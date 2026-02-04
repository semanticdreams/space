#pragma once

#include <atomic>
#include <cstdint>
#include <iostream>
#include <memory>
#include <string>
#include <unordered_map>

//#include <pybind11/pybind11.h>
//#include <pybind11/embed.h>

#define SOL_ALL_SAFETIES_ON 1  // optional, extra safety checks
#include <sol/sol.hpp>

#include "window_sdl.h"
#include "timer.h"
#include "input_state.h"
#include "physics.h"
#include "audio.h"
#include "job_system.h"
#include "http_client.h"
#include "keyring.h"

//namespace py = pybind11;

struct EngineConfig {
    bool headless { false };
    int width { 0 };
    int height { 0 };
    bool maximized { true };
};

class Engine {
public:
    Engine();
    bool start(sol::state& lua, sol::table engine_table, const EngineConfig& config);
    void run();
    void shutdown();

    template<typename... Args>
    void fennel_call_fatal(sol::function fn, Args&&... args) {
        if (!lua_state) {
            std::cerr << "Lua state not initialized\n";
            std::abort();
        }
        sol::protected_function pf = fn;

        pf.set_error_handler((*lua_state)["__FENNEL_FATAL_TRACEBACK"]);

        sol::protected_function_result res =
            pf(std::forward<Args>(args)...);

        if (!res.valid()) {
            std::cerr << "Unreachable: fatal call returned after error\n";
            std::abort();
        }
    }

    std::unique_ptr<WindowSdl> window { nullptr };

    void quit() { isRunning = false; };

private:
    bool isRunning { false };

    // Delta time
    uint32_t dt;
    std::atomic<uint64_t> frame_id {0};

    std::string title;
    const int screenWidth = 450;
    const int screenHeight = 680;
    Timer timer;

    InputState inputState {};
    [[nodiscard]] const InputState& getState() const;

    Physics physics;
    Audio audio;
    std::unique_ptr<JobSystem> jobs;
    std::unique_ptr<HttpClient> http;
    Keyring keyring;

    // lua
    sol::state* lua_state { nullptr };
    sol::table lua_engine;

    void emit_engine_event(const std::string& signal_name, sol::table payload);

    void initSystemCursors();
    void shutdownSystemCursors();
    void setSystemCursor(const std::string& name);

    std::unordered_map<std::string, SDL_Cursor*> systemCursors;
    SDL_Cursor* activeCursor { nullptr };

    // python
    //std::unique_ptr<py::scoped_interpreter> python;
    //py::object pythonWorld;
};
