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
#include <cinttypes>
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

Uint64 ns_to_ms(Uint64 timestamp_ns)
{
    return timestamp_ns / 1000000ULL;
}

const char* startup_mode_to_string(WindowStartupMode mode)
{
    if (mode == WindowStartupMode::Windowed) {
        return "windowed";
    }
    if (mode == WindowStartupMode::Maximized) {
        return "maximized";
    }
    return "fullscreen";
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
        if (!window->init(target_width, target_height, config.window_mode)) {
            return false;
        }
        window->setTextInputEnabled(false);
        window->logGlParams();

        initSystemCursors();
        SDL_SetGamepadEventsEnabled(true);

        inputState.keyboardState.currentValue = SDL_GetKeyboardState(nullptr);
        // Clear previous state memory
        memset(inputState.keyboardState.previousValue, 0, SDL_SCANCODE_COUNT);
        {
            float mouseX = 0.0F;
            float mouseY = 0.0F;
            SDL_MouseButtonFlags mouseMask = SDL_GetMouseState(&mouseX, &mouseY);
            inputState.mouseState.update_from_mask(mouseMask);
            inputState.mouseState.set_motion(mouseX, mouseY, 0.0F, 0.0F);
        }

        int gamepad_count = 0;
        SDL_JoystickID* gamepad_ids = SDL_GetGamepads(&gamepad_count);
        for (int i = 0; i < gamepad_count; ++i) {
            openGamepad(gamepad_ids[i], SDL_GetTicks());
        }
        SDL_free(gamepad_ids);
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
    lua_engine["window-mode"] = startup_mode_to_string(config.window_mode);
    if (!config.headless) {
        int actual_width = 0;
        int actual_height = 0;
        int actual_pixel_width = 0;
        int actual_pixel_height = 0;
        if (window && window->getWindowSize(actual_width, actual_height)) {
            lua_engine["width"] = actual_width;
            lua_engine["height"] = actual_height;
        } else {
            int target_width = config.width > 0 ? config.width : screenWidth;
            int target_height = config.height > 0 ? config.height : screenHeight;
            lua_engine["width"] = target_width;
            lua_engine["height"] = target_height;
        }
        if (window && window->getWindowSizeInPixels(actual_pixel_width, actual_pixel_height)) {
            lua_engine["pixel-width"] = actual_pixel_width;
            lua_engine["pixel-height"] = actual_pixel_height;
        } else {
            lua_engine["pixel-width"] = lua_engine["width"];
            lua_engine["pixel-height"] = lua_engine["height"];
        }
    }
    lua_engine.set_function("quit", [this]() {
        this->quit();
    });
    lua_engine.set_function("set-system-cursor", [this](const std::string& name) {
        this->setSystemCursor(name);
    });
    lua_engine.set_function("set-text-input-enabled", [this](bool enabled) {
        this->setTextInputEnabled(enabled);
    });
    lua_bind_callbacks(*lua_state, lua_engine);
    lua_engine["physics"] = &physics;
    lua_engine["audio"] = &audio;
    lua_engine["input"] = &inputState;
    inputDialType = std::make_unique<InputDialType>(inputState);
    lua_engine.set_function("dial-type-activate", [this](int instance_id) {
        if (inputDialType) {
            inputDialType->activate_gamepad(static_cast<SDL_JoystickID>(instance_id));
        }
    });
    lua_engine.set_function("dial-type-deactivate", [this](int instance_id) {
        if (inputDialType) {
            inputDialType->deactivate_gamepad(static_cast<SDL_JoystickID>(instance_id));
        }
    });
    lua_engine.set_function("dial-type-on-input", [this](int instance_id, sol::function callback) {
        if (!inputDialType) {
            return static_cast<uint64_t>(0);
        }
        auto cb = std::make_shared<sol::protected_function>(callback);
        return inputDialType->register_callback(
            static_cast<SDL_JoystickID>(instance_id),
            [this, cb](SDL_JoystickID gamepad_id, const DialTypePendingInput& input) {
                if (!lua_state || !cb || !cb->valid()) {
                    return;
                }
                sol::table payload = lua_state->create_table();
                payload["instance-id"] = static_cast<int>(gamepad_id);
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

        memcpy(inputState.keyboardState.previousValue, inputState.keyboardState.currentValue, SDL_SCANCODE_COUNT);
        inputState.mouseState.begin_frame();
        inputState.begin_frame();
        {
            float mouseX = static_cast<float>(inputState.mouseState.x);
            float mouseY = static_cast<float>(inputState.mouseState.y);
            SDL_MouseButtonFlags mouseMask = SDL_GetMouseState(&mouseX, &mouseY);
            inputState.mouseState.update_from_mask(mouseMask);
            inputState.mouseState.set_motion(mouseX, mouseY, 0.0F, 0.0F);
        }

        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            switch (event.type) {
                case SDL_EVENT_QUIT:
                    isRunning = false;
                    break;

                case SDL_EVENT_WINDOW_RESIZED:
                    {
                        Uint64 resize_started = SDL_GetPerformanceCounter();
                        Uint64 perf_frequency = SDL_GetPerformanceFrequency();
                        int width = event.window.data1;
                        int height = event.window.data2;
                        window->updateViewportFromWindowPixels();
                        lua_engine["width"] = width;
                        lua_engine["height"] = height;
                        sol::table payload = lua_state->create_table();
                        payload["width"] = width;
                        payload["height"] = height;
                        payload["timestamp"] = ns_to_ms(event.common.timestamp);
                        emit_engine_event("window-resized", payload);
                        Uint64 resize_finished = SDL_GetPerformanceCounter();
                        double resize_ms = 0.0;
                        if (perf_frequency > 0) {
                            resize_ms = (static_cast<double>(resize_finished - resize_started) * 1000.0)
                                        / static_cast<double>(perf_frequency);
                        }
                        LOG(Info) << "window-resized handled in " << resize_ms << "ms"
                                  << " (" << width << "x" << height << ")";
                    }
                    break;

                case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
                    lua_engine["pixel-width"] = event.window.data1;
                    lua_engine["pixel-height"] = event.window.data2;
                    window->updateViewportFromWindowPixels();
                    break;

                case SDL_EVENT_WINDOW_MAXIMIZED:
                    {
                        lua_engine["window-mode"] = "maximized";
                        sol::table payload = lua_state->create_table();
                        payload["mode"] = "maximized";
                        payload["timestamp"] = ns_to_ms(event.common.timestamp);
                        emit_engine_event("window-mode-changed", payload);
                    }
                    break;

                case SDL_EVENT_WINDOW_RESTORED:
                    {
                        lua_engine["window-mode"] = "windowed";
                        sol::table payload = lua_state->create_table();
                        payload["mode"] = "windowed";
                        payload["timestamp"] = ns_to_ms(event.common.timestamp);
                        emit_engine_event("window-mode-changed", payload);
                    }
                    break;

                case SDL_EVENT_WINDOW_ENTER_FULLSCREEN:
                    {
                        lua_engine["window-mode"] = "fullscreen";
                        sol::table payload = lua_state->create_table();
                        payload["mode"] = "fullscreen";
                        payload["timestamp"] = ns_to_ms(event.common.timestamp);
                        emit_engine_event("window-mode-changed", payload);
                    }
                    break;

                case SDL_EVENT_WINDOW_LEAVE_FULLSCREEN:
                    {
                        WindowStartupMode current_mode = WindowStartupMode::Windowed;
                        if (window) {
                            current_mode = window->currentStartupMode();
                        }
                        const char* mode = startup_mode_to_string(current_mode);
                        lua_engine["window-mode"] = mode;
                        sol::table payload = lua_state->create_table();
                        payload["mode"] = mode;
                        payload["timestamp"] = ns_to_ms(event.common.timestamp);
                        emit_engine_event("window-mode-changed", payload);
                    }
                    break;

                case SDL_EVENT_KEY_DOWN: {
                    switch(event.key.key) {
                        case SDLK_F11:
                            window->toggleFullscreen();
                            break;

                    }
                    sol::table payload = lua_state->create_table();
                    payload["key"] = static_cast<int>(event.key.key);
                    payload["scancode"] = static_cast<int>(event.key.scancode);
                    payload["mod"] = static_cast<int>(event.key.mod);
                    payload["repeat"] = event.key.repeat != 0;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("key-down", payload);
                    break;
                }

                case SDL_EVENT_KEY_UP: {
                    sol::table payload = lua_state->create_table();
                    payload["key"] = static_cast<int>(event.key.key);
                    payload["scancode"] = static_cast<int>(event.key.scancode);
                    payload["mod"] = static_cast<int>(event.key.mod);
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("key-up", payload);
                    break;
                }

                case SDL_EVENT_MOUSE_MOTION: {
                    inputState.mouseState.set_motion(
                        event.motion.x,
                        event.motion.y,
                        event.motion.xrel,
                        event.motion.yrel);
                    sol::table payload = lua_state->create_table();
                    payload["x"] = event.motion.x;
                    payload["y"] = event.motion.y;
                    payload["xrel"] = event.motion.xrel;
                    payload["yrel"] = event.motion.yrel;
                    payload["which"] = static_cast<int>(event.motion.which);
                    payload["mod"] = static_cast<int>(SDL_GetModState());
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("mouse-motion", payload);
                    break;
                }

                case SDL_EVENT_MOUSE_BUTTON_DOWN: {
                    inputState.mouseState.set_motion(event.button.x, event.button.y, 0.0F, 0.0F);
                    inputState.mouseState.set_button(event.button.button, true);
                    sol::table payload = lua_state->create_table();
                    payload["button"] = static_cast<int>(event.button.button);
                    payload["state"] = event.button.down;
                    payload["clicks"] = static_cast<int>(event.button.clicks);
                    payload["x"] = event.button.x;
                    payload["y"] = event.button.y;
                    payload["which"] = static_cast<int>(event.button.which);
                    payload["mod"] = static_cast<int>(SDL_GetModState());
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("mouse-button-down", payload);
                    break;
                }

                case SDL_EVENT_MOUSE_BUTTON_UP: {
                    inputState.mouseState.set_motion(event.button.x, event.button.y, 0.0F, 0.0F);
                    inputState.mouseState.set_button(event.button.button, false);
                    sol::table payload = lua_state->create_table();
                    payload["button"] = static_cast<int>(event.button.button);
                    payload["state"] = event.button.down;
                    payload["clicks"] = static_cast<int>(event.button.clicks);
                    payload["x"] = event.button.x;
                    payload["y"] = event.button.y;
                    payload["which"] = static_cast<int>(event.button.which);
                    payload["mod"] = static_cast<int>(SDL_GetModState());
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("mouse-button-up", payload);
                    break;
                }

                case SDL_EVENT_MOUSE_WHEEL: {
                    float wheel_x = event.wheel.x;
                    float wheel_y = event.wheel.y;
                    if (event.wheel.direction == SDL_MOUSEWHEEL_FLIPPED) {
                        wheel_x = -wheel_x;
                        wheel_y = -wheel_y;
                    }
                    inputState.mouseState.add_wheel(wheel_x, wheel_y);
                    sol::table payload = lua_state->create_table();
                    payload["x"] = wheel_x;
                    payload["y"] = wheel_y;
                    payload["direction"] = static_cast<int>(event.wheel.direction);
                    payload["which"] = static_cast<int>(event.wheel.which);
                    payload["mod"] = static_cast<int>(SDL_GetModState());
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("mouse-wheel", payload);
                    break;
                }

                case SDL_EVENT_TEXT_INPUT: {
                    sol::table payload = lua_state->create_table();
                    payload["text"] = std::string(event.text.text);
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("text-input", payload);
                    break;
                }

                case SDL_EVENT_TEXT_EDITING: {
                    sol::table payload = lua_state->create_table();
                    payload["text"] = std::string(event.edit.text);
                    payload["start"] = static_cast<int>(event.edit.start);
                    payload["length"] = static_cast<int>(event.edit.length);
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("text-editing", payload);
                    break;
                }

                case SDL_EVENT_GAMEPAD_BUTTON_DOWN: {
                    inputState.on_gamepad_button(event.gbutton.button, true, event.gbutton.which, ns_to_ms(event.common.timestamp));
                    sol::table payload = lua_state->create_table();
                    payload["which"] = static_cast<int>(event.gbutton.which);
                    payload["instance-id"] = static_cast<int>(event.gbutton.which);
                    payload["button"] = static_cast<int>(event.gbutton.button);
                    payload["state"] = event.gbutton.down;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("gamepad-button-down", payload);
                    break;
                }

                case SDL_EVENT_GAMEPAD_BUTTON_UP: {
                    inputState.on_gamepad_button(event.gbutton.button, false, event.gbutton.which, ns_to_ms(event.common.timestamp));
                    sol::table payload = lua_state->create_table();
                    payload["which"] = static_cast<int>(event.gbutton.which);
                    payload["instance-id"] = static_cast<int>(event.gbutton.which);
                    payload["button"] = static_cast<int>(event.gbutton.button);
                    payload["state"] = event.gbutton.down;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("gamepad-button-up", payload);
                    break;
                }

                case SDL_EVENT_GAMEPAD_AXIS_MOTION: {
                    const float axis_value = static_cast<float>(event.gaxis.value) / 32768.0f;
                    inputState.on_gamepad_axis(event.gaxis.axis, axis_value, event.gaxis.which, ns_to_ms(event.common.timestamp));
                    sol::table payload = lua_state->create_table();
                    payload["which"] = static_cast<int>(event.gaxis.which);
                    payload["instance-id"] = static_cast<int>(event.gaxis.which);
                    payload["axis"] = static_cast<int>(event.gaxis.axis);
                    payload["value"] = axis_value;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("gamepad-axis-motion", payload);
                    if (inputDialType) {
                        inputDialType->process_gamepad(event.gaxis.which);
                    }
                    break;
                }

                case SDL_EVENT_GAMEPAD_ADDED: {
                    const SDL_JoystickID instance_id = openGamepad(event.gdevice.which, ns_to_ms(event.common.timestamp));
                    sol::table payload = lua_state->create_table();
                    payload["which"] = static_cast<int>(event.gdevice.which);
                    payload["instance-id"] = static_cast<int>(instance_id);
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("gamepad-added", payload);
                    break;
                }

                case SDL_EVENT_GAMEPAD_REMOVED: {
                    closeGamepad(event.gdevice.which, ns_to_ms(event.common.timestamp));
                    sol::table payload = lua_state->create_table();
                    payload["which"] = static_cast<int>(event.gdevice.which);
                    payload["instance-id"] = static_cast<int>(event.gdevice.which);
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("gamepad-removed", payload);
                    break;
                }

                default:
                    break;
            }

        }

        physics.update(static_cast<uint32_t>(dt));

        audio.update(static_cast<uint32_t>(dt));
        video_manager.update_all(static_cast<uint32_t>(dt));

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
            fennel_call_fatal(emit, static_cast<uint32_t>(dt));
        }
        frame_id.fetch_add(1, std::memory_order_relaxed);


        window->swapBuffer();

        timer.delayTime();
    }
}

SDL_JoystickID Engine::openGamepad(SDL_JoystickID instanceId, Uint64 timestamp)
{
    if (!SDL_IsGamepad(instanceId)) {
        return 0;
    }

    SDL_Gamepad* gamepad = SDL_OpenGamepad(instanceId);
    if (!gamepad) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Failed to open gamepad %" SDL_PRIu32 ": %s",
                    instanceId,
                    SDL_GetError());
        return 0;
    }

    SDL_Joystick* joystick = SDL_GetGamepadJoystick(gamepad);
    if (!joystick) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Failed to get joystick handle for gamepad %" SDL_PRIu32 ": %s",
                    instanceId,
                    SDL_GetError());
        SDL_CloseGamepad(gamepad);
        return 0;
    }

    const SDL_JoystickID instance_id = SDL_GetJoystickID(joystick);
    auto existing = gamepads.find(instance_id);
    if (existing != gamepads.end()) {
        SDL_CloseGamepad(existing->second);
    }
    gamepads[instance_id] = gamepad;
    inputState.on_gamepad_connected(static_cast<Sint32>(instance_id), instance_id, timestamp);
    return instance_id;
}

void Engine::closeGamepad(SDL_JoystickID instanceId, Uint64 timestamp)
{
    if (inputDialType) {
        inputDialType->deactivate_gamepad(instanceId);
    }
    auto it = gamepads.find(instanceId);
    if (it != gamepads.end()) {
        if (it->second) {
            SDL_CloseGamepad(it->second);
        }
        gamepads.erase(it);
    }
    inputState.on_gamepad_disconnected(instanceId, timestamp);
}

void Engine::closeAllGamepads(Uint64 timestamp)
{
    std::vector<SDL_JoystickID> instance_ids;
    instance_ids.reserve(gamepads.size());
    for (const auto& [instance_id, gamepad] : gamepads) {
        (void)gamepad;
        instance_ids.push_back(instance_id);
    }
    for (const SDL_JoystickID instance_id : instance_ids) {
        closeGamepad(instance_id, timestamp);
    }
}

void Engine::shutdown() {
    browser_system.shutdown();
    inputDialType.reset();
    closeAllGamepads(SDL_GetTicks());
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
        {"arrow", SDL_SYSTEM_CURSOR_DEFAULT},
        {"hand", SDL_SYSTEM_CURSOR_POINTER},
        {"ibeam", SDL_SYSTEM_CURSOR_TEXT},
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
            SDL_DestroyCursor(pair.second);
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

void Engine::setTextInputEnabled(bool enabled)
{
    if (!window) {
        return;
    }
    if (window->isTextInputEnabled() == enabled) {
        return;
    }
    window->setTextInputEnabled(enabled);
}
