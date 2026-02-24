//#include <pybind11/pybind11.h>
#include "engine.h"
#include "resource_manager.h"
#include "lua_callbacks.h"
#include "lua_http.h"
#include "lua_process.h"
#include "cgltf_jobs.h"
#include "lua_jobs.h"
#include "lua_keyring.h"
#include "log.h"
#include "input_mouse_state.h"
#include "lua_video.h"
#include "video_player.h"
#include "cef_runtime.h"

#include <optional>
#include <vector>

//namespace py = pybind11;
namespace {

sol::table make_int_array(sol::state& lua, const std::vector<int>& values)
{
    sol::table out = lua.create_table();
    for (size_t i = 0; i < values.size(); ++i) {
        out[static_cast<int>(i + 1)] = values[i];
    }
    return out;
}

} // namespace

Engine::Engine() {
}

bool Engine::start(sol::state& lua, sol::table engine_table, const EngineConfig& config) {
    log_set_frame_id_provider(&frame_id);
    if (!config.headless) {
        window = WindowSdl::create();
        int target_width = config.width > 0 ? config.width : screenWidth;
        int target_height = config.height > 0 ? config.height : screenHeight;
        if (!window->init(SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, target_width, target_height, config.maximized)) {
            return false;
        }
        window->logGlParams();

        initSystemCursors();
        SDL_GameControllerEventState(SDL_ENABLE);

        inputState.keyboardState.currentValue = SDL_GetKeyboardState(nullptr);
        // Clear previous state memory
        memset(inputState.keyboardState.previousValue, 0, SDL_NUM_SCANCODES);
        {
            int mouseX = 0;
            int mouseY = 0;
            Uint32 mouseMask = SDL_GetMouseState(&mouseX, &mouseY);
            inputState.mouseState.update_from_mask(mouseMask);
            inputState.mouseState.set_motion(mouseX, mouseY, 0, 0);
        }

        const int joystick_count = SDL_NumJoysticks();
        for (int device_index = 0; device_index < joystick_count; ++device_index) {
            openGameController(device_index, SDL_GetTicks());
        }
    }

    http = std::make_unique<HttpClient>();
    jobs = std::make_unique<JobSystem>();
    register_default_job_handlers(*jobs);
    register_texture_job_handlers(*jobs);
    register_audio_job_handlers(*jobs);
    register_cgltf_job_handlers(*jobs);
    ResourceManager::setJobSystem(jobs.get());
    ResourceManager::setAudio(&audio);
    video_manager.set_audio(&audio);
    lua_video_set_manager(lua, &video_manager);

    lua_state = &lua;
    lua_engine = engine_table;
    lua_engine["frame-id"] = frame_id.load(std::memory_order_relaxed);
    if (!config.headless) {
        int target_width = config.width > 0 ? config.width : screenWidth;
        int target_height = config.height > 0 ? config.height : screenHeight;
        lua_engine["width"] = target_width;
        lua_engine["height"] = target_height;
    }
    lua_engine.set_function("quit", [this]() {
        this->quit();
    });
    lua_engine.set_function("set-system-cursor", [this](const std::string& name) {
        this->setSystemCursor(name);
    });
    lua_bind_callbacks(*lua_state, lua_engine);
    lua_engine["physics"] = &physics;
    lua_engine["audio"] = &audio;
    lua_engine["input"] = &inputState;
    inputDialType = std::make_unique<InputDialType>(inputState);
    lua_engine.set_function("dial-type-activate", [this](int instance_id) {
        if (inputDialType) {
            inputDialType->activate_controller(static_cast<SDL_JoystickID>(instance_id));
        }
    });
    lua_engine.set_function("dial-type-deactivate", [this](int instance_id) {
        if (inputDialType) {
            inputDialType->deactivate_controller(static_cast<SDL_JoystickID>(instance_id));
        }
    });
    lua_engine.set_function("dial-type-on-input", [this](int instance_id, sol::function callback) {
        if (!inputDialType) {
            return static_cast<uint64_t>(0);
        }
        auto cb = std::make_shared<sol::protected_function>(callback);
        return inputDialType->register_callback(
            static_cast<SDL_JoystickID>(instance_id),
            [this, cb](SDL_JoystickID controller_id, const DialTypePendingInput& input) {
                if (!lua_state || !cb || !cb->valid()) {
                    return;
                }
                sol::table payload = lua_state->create_table();
                payload["instance-id"] = static_cast<int>(controller_id);
                sol::table in = lua_state->create_table();
                in[1] = make_int_array(*lua_state, input.left);
                in[2] = make_int_array(*lua_state, input.right);
                payload["input"] = in;
                sol::protected_function_result result = (*cb)(payload);
                if (!result.valid()) {
                    sol::error err = result;
                    std::cerr << "[dial-type] callback failed: " << err.what() << "\n";
                }
            });
    });
    lua_engine.set_function("dial-type-off-input", [this](uint64_t callback_id) {
        if (!inputDialType) {
            return false;
        }
        return inputDialType->unregister_callback(callback_id);
    });
    lua_bind_jobs(*lua_state, lua_engine, *jobs);
    lua_bind_keyring(*lua_state, keyring);
    lua_bind_http(*lua_state, *http);
    {
        sol::table mouse_buttons = lua_state->create_table();
        mouse_buttons["left"] = SDL_BUTTON_LEFT;
        mouse_buttons["middle"] = SDL_BUTTON_MIDDLE;
        mouse_buttons["right"] = SDL_BUTTON_RIGHT;
        mouse_buttons["x1"] = SDL_BUTTON_X1;
        mouse_buttons["x2"] = SDL_BUTTON_X2;
        lua_engine["mouse-buttons"] = mouse_buttons;
    }
    {
        sol::table browser_table = lua_state->create_table();
        browser_table.set_function("create-surface", [this](sol::table options) {
            browser::SurfaceConfig config;
            sol::optional<std::string> id = options["id"];
            sol::optional<std::string> url = options["url"];
            if (!id || id->empty()) {
                throw sol::error("engine.browser.create-surface requires id");
            }
            if (!url || url->empty()) {
                throw sol::error("engine.browser.create-surface requires url");
            }
            config.id = *id;
            config.url = *url;
            if (sol::optional<std::string> texture_name = options["texture-name"]) {
                config.texture_name = *texture_name;
            }
            if (sol::optional<int> width = options["width"]) {
                if (*width <= 0) {
                    throw sol::error("engine.browser.create-surface width must be > 0");
                }
                config.width = static_cast<std::uint32_t>(*width);
            }
            if (sol::optional<int> height = options["height"]) {
                if (*height <= 0) {
                    throw sol::error("engine.browser.create-surface height must be > 0");
                }
                config.height = static_cast<std::uint32_t>(*height);
            }
            if (sol::optional<int> max_fps = options["max-fps"]) {
                if (*max_fps <= 0) {
                    throw sol::error("engine.browser.create-surface max-fps must be > 0");
                }
                config.max_fps = static_cast<std::uint32_t>(*max_fps);
            }
            return browser_system.create_surface(config);
        });
        browser_table.set_function("destroy-surface", [this](const std::string& id) {
            return browser_system.destroy_surface(id);
        });
        browser_table.set_function("set-url", [this](const std::string& id, const std::string& url) {
            return browser_system.set_surface_url(id, url);
        });
        browser_table.set_function("set-visible", [this](const std::string& id, bool visible) {
            browser_system.set_surface_visible(id, visible);
        });
        browser_table.set_function("set-focus", [this](const std::string& id, bool focused) {
            return browser_system.set_surface_focus(id, focused);
        });
        browser_table.set_function("send-mouse-move", [this](const std::string& id, int x, int y, sol::object leave_opt) {
            bool leave = false;
            if (leave_opt.is<bool>()) {
                leave = leave_opt.as<bool>();
            }
            return browser_system.send_mouse_move(id, x, y, leave);
        });
        browser_table.set_function("send-mouse-click",
            [this](const std::string& id, int x, int y, int button, bool mouse_up, sol::optional<int> click_count) {
                return browser_system.send_mouse_click(id, x, y, button, mouse_up, click_count.value_or(1));
            });
        browser_table.set_function("send-mouse-wheel", [this](const std::string& id, int x, int y, int dx, int dy) {
            return browser_system.send_mouse_wheel(id, x, y, dx, dy);
        });
        browser_table.set_function("texture-name", [this](const std::string& id) -> sol::object {
            std::optional<std::string> texture_name = browser_system.get_surface_texture_name(id);
            if (!texture_name) {
                return sol::make_object(*lua_state, sol::nil);
            }
            return sol::make_object(*lua_state, *texture_name);
        });
        browser_table.set_function("texture-info", [this](const std::string& id) -> sol::object {
            std::optional<std::string> texture_name = browser_system.get_surface_texture_name(id);
            if (!texture_name) {
                return sol::make_object(*lua_state, sol::nil);
            }
            auto it = ResourceManager::textures.find(*texture_name);
            if (it == ResourceManager::textures.end()) {
                return sol::make_object(*lua_state, sol::nil);
            }
            const Texture2D& texture = it->second;
            sol::table table = lua_state->create_table();
            table["name"] = *texture_name;
            table["id"] = static_cast<int>(texture.id);
            table["width"] = texture.width;
            table["height"] = texture.height;
            table["channels"] = texture.n;
            table["ready"] = texture.ready;
            return sol::make_object(*lua_state, table);
        });
        browser_table.set_function("surface-stats", [this](const std::string& id) -> sol::object {
            std::optional<browser::BrowserSystem::SurfaceStats> stats = browser_system.get_surface_stats(id);
            if (!stats) {
                return sol::make_object(*lua_state, sol::nil);
            }
            sol::table table = lua_state->create_table();
            table["exists"] = stats->exists;
            table["visible"] = stats->visible;
            table["texture-allocated"] = stats->texture_allocated;
            table["width"] = static_cast<int>(stats->width);
            table["height"] = static_cast<int>(stats->height);
            table["paint-count"] = static_cast<double>(stats->paint_count);
            table["upload-count"] = static_cast<double>(stats->upload_count);
            table["last-upload-frame"] = static_cast<double>(stats->last_upload_frame);
            return sol::make_object(*lua_state, table);
        });
        browser_table.set_function("list-surfaces", [this]() -> sol::table {
            std::vector<std::string> ids = browser_system.list_surface_ids();
            sol::table out = lua_state->create_table(static_cast<int>(ids.size()), 0);
            int index = 1;
            for (const std::string& id : ids) {
                out[index] = id;
                ++index;
            }
            return out;
        });
        lua_engine["browser"] = browser_table;
    }
    isRunning = !config.headless;
    return true;
}

void Engine::run() {
    while (isRunning) {
        cef_runtime::do_message_loop_work();
        dt = timer.computeDeltaTime();
        window->updateFpsCounter(dt);

        window->clear();

        memcpy(inputState.keyboardState.previousValue, inputState.keyboardState.currentValue, SDL_NUM_SCANCODES);
        inputState.mouseState.begin_frame();
        inputState.begin_frame();
        {
            int mouseX = inputState.mouseState.x;
            int mouseY = inputState.mouseState.y;
            Uint32 mouseMask = SDL_GetMouseState(&mouseX, &mouseY);
            inputState.mouseState.update_from_mask(mouseMask);
            inputState.mouseState.set_motion(mouseX, mouseY, 0, 0);
        }

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
                            lua_engine["width"] = width;
                            lua_engine["height"] = height;
                            {
                                sol::table payload = lua_state->create_table();
                                payload["width"] = width;
                                payload["height"] = height;
                                payload["timestamp"] = event.common.timestamp;
                                emit_engine_event("window-resized", payload);
                            }
                            break;
                    }
                    break;

                case SDL_KEYDOWN: {
                    switch(event.key.keysym.sym) {
                        case SDLK_F11:
                            window->toggleFullscreen();
                            break;

                    }
                    sol::table payload = lua_state->create_table();
                    payload["key"] = static_cast<int>(event.key.keysym.sym);
                    payload["scancode"] = static_cast<int>(event.key.keysym.scancode);
                    payload["mod"] = static_cast<int>(event.key.keysym.mod);
                    payload["repeat"] = event.key.repeat != 0;
                    payload["timestamp"] = event.common.timestamp;
                    emit_engine_event("key-down", payload);
                    break;
                }

                case SDL_KEYUP: {
                    sol::table payload = lua_state->create_table();
                    payload["key"] = static_cast<int>(event.key.keysym.sym);
                    payload["scancode"] = static_cast<int>(event.key.keysym.scancode);
                    payload["mod"] = static_cast<int>(event.key.keysym.mod);
                    payload["timestamp"] = event.common.timestamp;
                    emit_engine_event("key-up", payload);
                    break;
                }

                case SDL_MOUSEMOTION: {
                    inputState.mouseState.set_motion(event.motion.x, event.motion.y, event.motion.xrel, event.motion.yrel);
                    sol::table payload = lua_state->create_table();
                    payload["x"] = event.motion.x;
                    payload["y"] = event.motion.y;
                    payload["xrel"] = event.motion.xrel;
                    payload["yrel"] = event.motion.yrel;
                    payload["which"] = static_cast<int>(event.motion.which);
                    payload["mod"] = static_cast<int>(SDL_GetModState());
                    payload["timestamp"] = event.common.timestamp;
                    emit_engine_event("mouse-motion", payload);
                    break;
                }

                case SDL_MOUSEBUTTONDOWN: {
                    inputState.mouseState.set_motion(event.button.x, event.button.y, 0, 0);
                    inputState.mouseState.set_button(event.button.button, true);
                    sol::table payload = lua_state->create_table();
                    payload["button"] = static_cast<int>(event.button.button);
                    payload["state"] = static_cast<int>(event.button.state);
                    payload["clicks"] = static_cast<int>(event.button.clicks);
                    payload["x"] = event.button.x;
                    payload["y"] = event.button.y;
                    payload["which"] = static_cast<int>(event.button.which);
                    payload["mod"] = static_cast<int>(SDL_GetModState());
                    payload["timestamp"] = event.common.timestamp;
                    emit_engine_event("mouse-button-down", payload);
                    break;
                }

                case SDL_MOUSEBUTTONUP: {
                    inputState.mouseState.set_motion(event.button.x, event.button.y, 0, 0);
                    inputState.mouseState.set_button(event.button.button, false);
                    sol::table payload = lua_state->create_table();
                    payload["button"] = static_cast<int>(event.button.button);
                    payload["state"] = static_cast<int>(event.button.state);
                    payload["clicks"] = static_cast<int>(event.button.clicks);
                    payload["x"] = event.button.x;
                    payload["y"] = event.button.y;
                    payload["which"] = static_cast<int>(event.button.which);
                    payload["mod"] = static_cast<int>(SDL_GetModState());
                    payload["timestamp"] = event.common.timestamp;
                    emit_engine_event("mouse-button-up", payload);
                    break;
                }

                case SDL_MOUSEWHEEL: {
                    inputState.mouseState.add_wheel(event.wheel.x, event.wheel.y);
                    sol::table payload = lua_state->create_table();
                    payload["x"] = event.wheel.x;
                    payload["y"] = event.wheel.y;
                    payload["direction"] = static_cast<int>(event.wheel.direction);
                    payload["which"] = static_cast<int>(event.wheel.which);
                    payload["mod"] = static_cast<int>(SDL_GetModState());
                    payload["timestamp"] = event.common.timestamp;
                    emit_engine_event("mouse-wheel", payload);
                    break;
                }

                case SDL_TEXTINPUT: {
                    sol::table payload = lua_state->create_table();
                    payload["text"] = std::string(event.text.text);
                    payload["timestamp"] = event.common.timestamp;
                    emit_engine_event("text-input", payload);
                    break;
                }

                case SDL_CONTROLLERBUTTONDOWN: {
                    inputState.on_controller_button(event.cbutton.button, true, event.cbutton.which, event.common.timestamp);
                    sol::table payload = lua_state->create_table();
                    payload["which"] = static_cast<int>(event.cbutton.which);
                    payload["instance-id"] = static_cast<int>(event.cbutton.which);
                    payload["button"] = static_cast<int>(event.cbutton.button);
                    payload["state"] = static_cast<int>(event.cbutton.state);
                    payload["timestamp"] = event.common.timestamp;
                    emit_engine_event("controller-button-down", payload);
                    break;
                }

                case SDL_CONTROLLERBUTTONUP: {
                    inputState.on_controller_button(event.cbutton.button, false, event.cbutton.which, event.common.timestamp);
                    sol::table payload = lua_state->create_table();
                    payload["which"] = static_cast<int>(event.cbutton.which);
                    payload["instance-id"] = static_cast<int>(event.cbutton.which);
                    payload["button"] = static_cast<int>(event.cbutton.button);
                    payload["state"] = static_cast<int>(event.cbutton.state);
                    payload["timestamp"] = event.common.timestamp;
                    emit_engine_event("controller-button-up", payload);
                    break;
                }

                case SDL_CONTROLLERAXISMOTION: {
                    const float axis_value = static_cast<float>(event.caxis.value) / 32768.0f;
                    inputState.on_controller_axis(event.caxis.axis, axis_value, event.caxis.which, event.common.timestamp);
                    sol::table payload = lua_state->create_table();
                    payload["which"] = static_cast<int>(event.caxis.which);
                    payload["instance-id"] = static_cast<int>(event.caxis.which);
                    payload["axis"] = static_cast<int>(event.caxis.axis);
                    payload["value"] = axis_value;
                    payload["timestamp"] = event.common.timestamp;
                    emit_engine_event("controller-axis-motion", payload);
                    if (inputDialType) {
                        inputDialType->process_controller(event.caxis.which);
                    }
                    break;
                }

                case SDL_CONTROLLERDEVICEADDED: {
                    const SDL_JoystickID instance_id = openGameController(event.cdevice.which, event.common.timestamp);
                    sol::table payload = lua_state->create_table();
                    payload["which"] = static_cast<int>(event.cdevice.which);
                    payload["device-index"] = static_cast<int>(event.cdevice.which);
                    payload["instance-id"] = static_cast<int>(instance_id);
                    payload["timestamp"] = event.common.timestamp;
                    emit_engine_event("controller-device-added", payload);
                    break;
                }

                case SDL_CONTROLLERDEVICEREMOVED: {
                    closeGameController(event.cdevice.which, event.common.timestamp);
                    sol::table payload = lua_state->create_table();
                    payload["which"] = static_cast<int>(event.cdevice.which);
                    payload["instance-id"] = static_cast<int>(event.cdevice.which);
                    payload["timestamp"] = event.common.timestamp;
                    emit_engine_event("controller-device-removed", payload);
                    break;
                }

                default:
                    break;
            }

        }

        physics.update(dt);

        audio.update(dt);
        video_manager.update_all(dt);

        if (jobs) {
            ResourceManager::processTextureJobs();
            ResourceManager::processAudioJobs();
        }

        browser_system.tick(frame_id.load(std::memory_order_relaxed));

        lua_engine["frame-id"] = frame_id.load(std::memory_order_relaxed);
        if (jobs) {
            lua_jobs_dispatch(*lua_state, *jobs);
        }
        lua_http_dispatch(*lua_state);
        lua_process_dispatch(*lua_state);
        lua_callbacks_dispatch(*lua_state);
        {
            sol::table events = lua_engine["events"];
            sol::table signal = events["updated"];
            sol::function emit = signal["emit"];
            fennel_call_fatal(emit, dt);
        }
        frame_id.fetch_add(1, std::memory_order_relaxed);


        window->swapBuffer();

        timer.delayTime();
    }
}

SDL_JoystickID Engine::openGameController(Sint32 deviceIndex, Uint32 timestamp)
{
    if (!SDL_IsGameController(deviceIndex)) {
        return -1;
    }

    SDL_GameController* controller = SDL_GameControllerOpen(deviceIndex);
    if (!controller) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Failed to open game controller %d: %s",
                    deviceIndex,
                    SDL_GetError());
        return -1;
    }

    SDL_Joystick* joystick = SDL_GameControllerGetJoystick(controller);
    if (!joystick) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Failed to get joystick handle for game controller %d: %s",
                    deviceIndex,
                    SDL_GetError());
        SDL_GameControllerClose(controller);
        return -1;
    }

    const SDL_JoystickID instance_id = SDL_JoystickInstanceID(joystick);
    auto existing = gameControllers.find(instance_id);
    if (existing != gameControllers.end()) {
        SDL_GameControllerClose(existing->second);
    }
    gameControllers[instance_id] = controller;
    inputState.on_controller_connected(deviceIndex, instance_id, timestamp);
    return instance_id;
}

void Engine::closeGameController(SDL_JoystickID instanceId, Uint32 timestamp)
{
    if (inputDialType) {
        inputDialType->deactivate_controller(instanceId);
    }
    auto it = gameControllers.find(instanceId);
    if (it != gameControllers.end()) {
        if (it->second) {
            SDL_GameControllerClose(it->second);
        }
        gameControllers.erase(it);
    }
    inputState.on_controller_disconnected(instanceId, timestamp);
}

void Engine::closeAllGameControllers(Uint32 timestamp)
{
    std::vector<SDL_JoystickID> instance_ids;
    instance_ids.reserve(gameControllers.size());
    for (const auto& [instance_id, controller] : gameControllers) {
        (void)controller;
        instance_ids.push_back(instance_id);
    }
    for (const SDL_JoystickID instance_id : instance_ids) {
        closeGameController(instance_id, timestamp);
    }
}

void Engine::shutdown() {
    browser_system.shutdown();
    inputDialType.reset();
    closeAllGameControllers(SDL_GetTicks());
    lua_jobs_clear_callbacks();
    lua_keyring_drop(*lua_state);
    lua_http_drop(*lua_state);
    lua_process_drop(*lua_state);
    lua_callbacks_shutdown();
    video_manager.drop_all();
    video_manager.set_audio(nullptr);
    lua_video_set_manager(*lua_state, nullptr);
    ResourceManager::clearPending();
    ResourceManager::clear();
    log_set_frame_id_provider(nullptr);
    if (http) {
        http->shutdown();
    }
    if (jobs) {
        jobs->shutdown();
    }
    shutdownSystemCursors();
    if (window) {
        window->clean();
    }
}

void Engine::emit_engine_event(const std::string& signal_name, sol::table payload) {
    sol::object events_obj = lua_engine["events"];
    //if (!events_obj.valid() || !events_obj.is<sol::table>()) {
    //    return;
    //}

    sol::table events = events_obj.as<sol::table>();
    sol::object signal_obj = events[signal_name];
    //if (!signal_obj.valid() || !signal_obj.is<sol::table>()) {
    //    return;
    //}

    sol::table signal = signal_obj.as<sol::table>();
    sol::object emit_obj = signal["emit"];
    //if (!emit_obj.is<sol::function>()) {
    //    return;
    //}

    sol::function emit = emit_obj.as<sol::function>();
    fennel_call_fatal(emit, payload);
}

void Engine::initSystemCursors() {
    shutdownSystemCursors();

    struct CursorDesc {
        const char* name;
        SDL_SystemCursor type;
    };

    static const CursorDesc cursorDescs[] = {
        {"arrow", SDL_SYSTEM_CURSOR_ARROW},
        {"hand", SDL_SYSTEM_CURSOR_HAND},
        {"ibeam", SDL_SYSTEM_CURSOR_IBEAM},
    };

    for (const auto& desc : cursorDescs) {
        SDL_Cursor* cursor = SDL_CreateSystemCursor(desc.type);
        if (!cursor) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "Failed to create system cursor '%s': %s",
                        desc.name,
                        SDL_GetError());
            continue;
        }
        systemCursors[desc.name] = cursor;
    }

    activeCursor = nullptr;
}

void Engine::shutdownSystemCursors() {
    for (auto& pair : systemCursors) {
        if (pair.second) {
            SDL_FreeCursor(pair.second);
        }
    }
    systemCursors.clear();
    activeCursor = nullptr;
}

void Engine::setSystemCursor(const std::string& name) {
    auto it = systemCursors.find(name);
    if (it == systemCursors.end()) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Attempted to set unknown system cursor '%s'",
                    name.c_str());
        return;
    }

    SDL_Cursor* cursor = it->second;
    if (!cursor || cursor == activeCursor) {
        return;
    }

    SDL_SetCursor(cursor);
    activeCursor = cursor;
}
