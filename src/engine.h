#pragma once

#include <cstdint>
#include <string>
#include <memory>

#include <pybind11/pybind11.h>
#include <pybind11/embed.h>

#define SOL_ALL_SAFETIES_ON 1  // optional, extra safety checks
#include <sol/sol.hpp>

#include "window_sdl.h"
#include "timer.h"
#include "input_state.h"
#include "physics.h"
#include "audio.h"

namespace py = pybind11;

class Engine {
public:
    Engine();
    void start();
    void run();
    void shutdown();

    std::unique_ptr<WindowSdl> window { nullptr };

    void quit() { isRunning = false; };

private:
    bool isRunning { false };

    // Delta time
    uint32_t dt;

    std::string title;
    const int screenWidth = 450;
    const int screenHeight = 680;
    Timer timer;

    InputState inputState {};
    [[nodiscard]] const InputState& getState() const;

    Physics physics;
    Audio audio;

    // lua
    sol::state lua;
    sol::table lua_space;

    // python
    std::unique_ptr<py::scoped_interpreter> python;
    py::object pythonWorld;
};
