#include <pybind11/pybind11.h>
#include "engine.h"
#include "asset_manager.h"
#include "appdirs.h"
#include "paths.h"

namespace py = pybind11;

Engine::Engine() {
}

extern "C" int luaopen_lsqlite3(lua_State* L);

void lua_bind_bullet(sol::state&);
void lua_bind_opengl(sol::state&);
void lua_bind_json(sol::state&);
void lua_bind_shaders(sol::state&);
void lua_bind_glm(sol::state&);
void lua_bind_vector_buffer(sol::state&);
void lua_bind_tree_sitter(sol::state&);

extern "C" PyObject* PyInit_bullet();
extern "C" PyObject* PyInit_space();
extern "C" PyObject* PyInit_audio();
extern "C" PyObject* PyInit_force_layout();
extern "C" PyObject* PyInit_colors();

void Engine::start() {
    window = WindowSdl::create();
    if (!window->init(SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, screenWidth, screenHeight)) {
        return;
    }
    window->logGlParams();

    inputState.keyboardState.currentValue = SDL_GetKeyboardState(nullptr);
    // Clear previous state memory
    memset(inputState.keyboardState.previousValue, 0, SDL_NUM_SCANCODES);

    std::string assetsPath = AssetManager::getAssetPath("");

    // lua
    lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::table, sol::lib::math, sol::lib::string, sol::lib::debug, sol::lib::io, sol::lib::os);
    lua.require("lsqlite3", luaopen_lsqlite3);
    lua_bind_opengl(lua);
    lua_bind_bullet(lua);
    lua_bind_json(lua);
    lua_bind_shaders(lua);
    lua_bind_glm(lua);
    lua_bind_vector_buffer(lua);
    lua_bind_tree_sitter(lua);
    std::string luaPath = AssetManager::getAssetPath("lua");
    std::string packagePath = luaPath + "/?.lua";
    std::string fennelPath = luaPath + "/?.fnl";
    lua["package"]["path"] = lua["package"]["path"].get<std::string>() + ";" + packagePath;
    lua_space = lua.create_named_table("space");
    lua_space["data_dir"] = get_user_data_dir("space");
    lua_space["assets_dir"] = assetsPath;
    lua_space["fennel_path"] = fennelPath;
    lua_space.set_function("join_path", join_path);
    lua_space.set_function("get_asset_path", &AssetManager::getAssetPath);
    //lua.script_file(luaPath + "/init.lua");
    lua.script(R"(
    local fennel = require("fennel")
    fennel.path = ")" + fennelPath + R"(" .. ";" .. fennel.path
    fennel.install()
    require("main")
    )");
    ((sol::unsafe_function) lua_space["init"])();

    // python
    PyImport_AppendInittab("space", &PyInit_space);
    PyImport_AppendInittab("bullet", &PyInit_bullet);
    PyImport_AppendInittab("audio", &PyInit_audio);
    PyImport_AppendInittab("force_layout", &PyInit_force_layout);
    PyImport_AppendInittab("colors", &PyInit_colors);
    python = std::make_unique<py::scoped_interpreter>();
    std::string pyAssetsPath = AssetManager::getAssetPath("python");
    std::replace(pyAssetsPath.begin(), pyAssetsPath.end(), '\\', '/');
    py::module sys = py::module::import("sys");
    sys.attr("path").attr("insert")(0, pyAssetsPath);
    py::module init = py::module::import("python_world");
    py::object PythonWorld = init.attr("PythonWorld");
    pythonWorld = PythonWorld(
        py::make_tuple(screenWidth, screenHeight),
        assetsPath,
        py::cast(&physics, py::return_value_policy::reference),
        py::cast(&audio, py::return_value_policy::reference)
    );
    pythonWorld.attr("init")();

    lua_space["fbo"] = pythonWorld.attr("renderers").attr("lua_world").attr("fbo").cast<int>();

    isRunning = true;
}

void Engine::run() {
    while (isRunning) {
        dt = timer.computeDeltaTime();
        window->updateFpsCounter(dt);

        window->clear();

        memcpy(inputState.keyboardState.previousValue, inputState.keyboardState.currentValue, SDL_NUM_SCANCODES);

        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            switch (event.type) {
                case SDL_QUIT:
                    isRunning = false;
                    break;

                case SDL_WINDOWEVENT:
                    switch (event.window.event) {
                        case SDL_WINDOWEVENT_RESIZED:
                            int width = event.window.data1;
                            int height = event.window.data2;
                            glViewport(0, 0, width, height);
                            lua_space["width"] = width;
                            lua_space["height"] = height;
                            pythonWorld.attr("viewport_changed")(py::make_tuple(0, 0, width, height));
                            break;
                    }
                    break;

                case SDL_KEYDOWN:
                    switch(event.key.keysym.sym) {
                        case SDLK_F11:
                            window->toggleFullscreen();
                            break;

                        case SDLK_F5:
                            pythonWorld.attr("drop")();
                            pythonWorld.attr("init")();
                            lua_space["fbo"] = pythonWorld.attr("renderers").attr("lua_world").attr("fbo").cast<int>();
                            break;

                        case SDLK_F7:
                            ((sol::unsafe_function) lua_space["drop"])();
                            lua.script(R"(
                            package.loaded["main"] = nil
                            require("main")
                            )");
                            ((sol::unsafe_function) lua_space["init"])();
                            break;
                    }
                    pythonWorld.attr("window").attr("keys").attr("add")((int)event.key.keysym.sym);
                    pythonWorld.attr("window").attr("keyboard").attr("emit")((int)event.key.keysym.sym, (int)event.key.keysym.scancode, 1, (int)event.key.keysym.mod);
                    break;

                case SDL_KEYUP:
                    pythonWorld.attr("window").attr("keys").attr("discard")((int)event.key.keysym.sym);
                    pythonWorld.attr("window").attr("keyboard").attr("emit")((int)event.key.keysym.sym, (int)event.key.keysym.scancode, 0, (int)event.key.keysym.mod);
                    break;

                case SDL_MOUSEMOTION:
                    pythonWorld.attr("window").attr("mouse_motion").attr("emit")(event.motion.x, event.motion.y);
                    pythonWorld.attr("window").attr("mouse_pos") = py::make_tuple(event.motion.x, event.motion.y);
                    break;

                case SDL_MOUSEBUTTONDOWN:
                    pythonWorld.attr("window").attr("mouse_button").attr("emit")((int)event.button.button, 1, (int)event.button.state);
                    break;

                case SDL_MOUSEBUTTONUP:
                    pythonWorld.attr("window").attr("mouse_button").attr("emit")((int)event.button.button, 0, (int)event.button.state);
                    break;

                case SDL_MOUSEWHEEL:
                    pythonWorld.attr("window").attr("scrolled").attr("emit")((int)event.wheel.x, (int)event.wheel.y);
                    break;

                case SDL_TEXTINPUT:
                    pythonWorld.attr("window").attr("on_text_input")(event.text.text);
                    break;

                case SDL_CONTROLLERBUTTONDOWN:
                    pythonWorld.attr("gamepads").attr("__getitem__")(event.cbutton.which).attr("button_down").attr("emit")(event.cbutton.button, event.cbutton.state, event.cbutton.timestamp);
                    break;

                case SDL_CONTROLLERBUTTONUP:
                    pythonWorld.attr("gamepads").attr("__getitem__")(event.cbutton.which).attr("button_up").attr("emit")(event.cbutton.button, event.cbutton.state, event.cbutton.timestamp);
                    break;

                case SDL_CONTROLLERAXISMOTION:
                    pythonWorld.attr("gamepads").attr("__getitem__")(event.caxis.which).attr("motion").attr("emit")(event.caxis.axis, event.caxis.value / 32768.0, event.caxis.timestamp);
                    break;

                case SDL_CONTROLLERDEVICEADDED:
                    pythonWorld.attr("gamepads").attr("add")(event.cdevice.which);
                    break;

                case SDL_CONTROLLERDEVICEREMOVED:
                    pythonWorld.attr("gamepads").attr("remove")(event.cdevice.which);
                    break;

                default:
                    break;
            }
        }

        physics.update(dt);
        audio.update(dt);

        ((sol::unsafe_function) lua_space["update"])(dt);

        pythonWorld.attr("update")(dt);

        window->swapBuffer();

        timer.delayTime();
    }
}

void Engine::shutdown() {
    pythonWorld.attr("drop")();
    pythonWorld.release();
    ((sol::unsafe_function) lua_space["drop"])();
    window->clean();
}
