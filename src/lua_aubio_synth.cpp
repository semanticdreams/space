#include "lua_aubio_bindings.h"
#include "lua_aubio_types.h"

namespace lua_aubio {

void register_synth(sol::state_view lua, sol::table& aubio_table)
{
    ensure_types_registered(lua);
    aubio_table.new_usertype<AubioSampler>("Sampler",
        sol::no_constructor,
        "load", &AubioSampler::load,
        "do", &AubioSampler::do_sampler,
        "do-multi", &AubioSampler::do_sampler_multi,
        "playing?", &AubioSampler::get_playing,
        "set-playing", &AubioSampler::set_playing,
        "play", &AubioSampler::play,
        "stop", &AubioSampler::stop);

    aubio_table.new_usertype<AubioWavetable>("Wavetable",
        sol::no_constructor,
        "load", &AubioWavetable::load,
        "do", &AubioWavetable::do_wavetable,
        "do-multi", &AubioWavetable::do_wavetable_multi,
        "playing?", &AubioWavetable::get_playing,
        "set-playing", &AubioWavetable::set_playing,
        "play", &AubioWavetable::play,
        "stop", &AubioWavetable::stop,
        "set-freq", &AubioWavetable::set_freq,
        "get-freq", &AubioWavetable::get_freq,
        "set-amp", &AubioWavetable::set_amp,
        "get-amp", &AubioWavetable::get_amp);

    aubio_table.set_function("Sampler", [](uint_t samplerate, uint_t hop_size) {
        return AubioSampler(samplerate, hop_size);
    });
    aubio_table.set_function("Wavetable", [](uint_t samplerate, uint_t hop_size) {
        return AubioWavetable(samplerate, hop_size);
    });
}

} // namespace lua_aubio
