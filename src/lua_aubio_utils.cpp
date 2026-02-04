#include "lua_aubio_bindings.h"
#include "lua_aubio_types.h"

#include "audio_input.h"

#include <array>
#include <iostream>
#include <string>

#include <aubio/utils/log.h>

namespace {

struct AubioLogState {
    lua_State* lua_state = nullptr;
    sol::function all;
    std::array<sol::function, AUBIO_LOG_LAST_LEVEL> levels;
};

AubioLogState aubio_log_state;

const char* aubio_log_level_name(sint_t level)
{
    switch (level) {
    case AUBIO_LOG_ERR:
        return "err";
    case AUBIO_LOG_INF:
        return "inf";
    case AUBIO_LOG_MSG:
        return "msg";
    case AUBIO_LOG_DBG:
        return "dbg";
    case AUBIO_LOG_WRN:
        return "wrn";
    default:
        return "unknown";
    }
}

void aubio_log_bridge(sint_t level, const char_t* message, void* data)
{
    auto* state = static_cast<AubioLogState*>(data);
    if (!state || !state->lua_state) {
        return;
    }
    sol::function fn;
    if (level >= 0 && level < static_cast<sint_t>(state->levels.size()) && state->levels[level].valid()) {
        fn = state->levels[level];
    } else if (state->all.valid()) {
        fn = state->all;
    }
    if (!fn.valid()) {
        return;
    }
    sol::protected_function pf = fn;
    sol::protected_function_result result = pf(level, aubio_log_level_name(level), std::string(message ? message : ""));
    if (!result.valid()) {
        sol::error err = result;
        std::cerr << "aubio log handler error: " << err.what() << "\n";
    }
}

void aubio_log_clear_state()
{
    aubio_log_state.all = sol::function();
    for (auto& fn : aubio_log_state.levels) {
        fn = sol::function();
    }
    aubio_log_state.lua_state = nullptr;
}

} // namespace

namespace lua_aubio {

void register_utils(sol::state_view lua, sol::table& aubio_table)
{
    ensure_types_registered(lua);
    aubio_table.new_usertype<AubioParameter>("Parameter",
        sol::no_constructor,
        "set-target", &AubioParameter::set_target_value,
        "next-value", &AubioParameter::get_next_value,
        "current-value", &AubioParameter::get_current_value,
        "set-current", &AubioParameter::set_current_value,
        "set-steps", &AubioParameter::set_steps,
        "steps", &AubioParameter::get_steps,
        "set-min", &AubioParameter::set_min_value,
        "min", &AubioParameter::get_min_value,
        "set-max", &AubioParameter::set_max_value,
        "max", &AubioParameter::get_max_value);

    aubio_table.new_usertype<AubioScale>("Scale",
        sol::no_constructor,
        "do", &AubioScale::do_scale,
        "set-limits", &AubioScale::set_limits);

    aubio_table.new_usertype<AubioHist>("Hist",
        sol::no_constructor,
        "do", &AubioHist::do_hist,
        "do-notnull", &AubioHist::do_hist_notnull,
        "mean", &AubioHist::mean,
        "weight", &AubioHist::weight,
        "dyn-notnull", &AubioHist::dyn_notnull);

    aubio_table.set_function("Parameter", [](smpl_t min_value, smpl_t max_value, uint_t steps) {
        return AubioParameter(min_value, max_value, steps);
    });
    aubio_table.set_function("Scale", [](smpl_t flow, smpl_t fhig, smpl_t ilow, smpl_t ihig) {
        return AubioScale(flow, fhig, ilow, ihig);
    });
    aubio_table.set_function("Hist", [](smpl_t flow, smpl_t fhig, uint_t nelems) {
        return AubioHist(flow, fhig, nelems);
    });

    sol::table log_levels = lua.create_table();
    log_levels["err"] = AUBIO_LOG_ERR;
    log_levels["inf"] = AUBIO_LOG_INF;
    log_levels["msg"] = AUBIO_LOG_MSG;
    log_levels["dbg"] = AUBIO_LOG_DBG;
    log_levels["wrn"] = AUBIO_LOG_WRN;
    aubio_table["log-levels"] = log_levels;

    aubio_table.set_function("log-set", [lua](sol::function fn) mutable {
        aubio_log_state.lua_state = lua.lua_state();
        aubio_log_state.all = std::move(fn);
        aubio_log_set_function(&aubio_log_bridge, &aubio_log_state);
    });

    aubio_table.set_function("log-set-level", [lua](sint_t level, sol::function fn) mutable {
        if (level < 0 || level >= static_cast<sint_t>(aubio_log_state.levels.size())) {
            throw std::runtime_error("aubio log-set-level requires valid log level");
        }
        aubio_log_state.lua_state = lua.lua_state();
        aubio_log_state.levels[static_cast<std::size_t>(level)] = std::move(fn);
        aubio_log_set_function(&aubio_log_bridge, &aubio_log_state);
    });

    aubio_table.set_function("log-reset", []() {
        aubio_log_reset();
        aubio_log_clear_state();
    });

    aubio_table.set_function("audio-input-into-fvec", [](AudioInput& input, AubioFVec& buffer, std::size_t max_frames) {
        std::size_t channels = static_cast<std::size_t>(input.channels());
        std::size_t max_samples = max_frames * channels;
        if (channels == 0) {
            throw std::runtime_error("audio-input-into-fvec requires AudioInput with channels > 0");
        }
        if (max_samples > static_cast<std::size_t>(buffer.length())) {
            throw std::runtime_error("audio-input-into-fvec buffer too small for requested frames");
        }
        float* data = fvec_get_data(buffer.value);
        return input.readFramesInto(data, max_frames);
    });

    aubio_table.set_function("window", [](const std::string& window_type, uint_t size) {
        fvec_t* window = ensure_handle(new_aubio_window(const_cast<char_t*>(window_type.c_str()), size), "window");
        AubioFVec out(size);
        fvec_copy(window, out.value);
        del_fvec(window);
        return out;
    });

    aubio_table.set_function("unwrap2pi", &aubio_unwrap2pi);
    aubio_table.set_function("bintomidi", &aubio_bintomidi);
    aubio_table.set_function("miditobin", &aubio_miditobin);
    aubio_table.set_function("bintofreq", &aubio_bintofreq);
    aubio_table.set_function("freqtobin", &aubio_freqtobin);
    aubio_table.set_function("hztomel", &aubio_hztomel);
    aubio_table.set_function("meltohz", &aubio_meltohz);
    aubio_table.set_function("hztomel-htk", &aubio_hztomel_htk);
    aubio_table.set_function("meltohz-htk", &aubio_meltohz_htk);
    aubio_table.set_function("freqtomidi", &aubio_freqtomidi);
    aubio_table.set_function("miditofreq", &aubio_miditofreq);
    aubio_table.set_function("cleanup", &aubio_cleanup);
}

} // namespace lua_aubio
