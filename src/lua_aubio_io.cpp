#include "lua_aubio_bindings.h"
#include "lua_aubio_types.h"

namespace lua_aubio {

void register_io(sol::state_view lua, sol::table& aubio_table)
{
    ensure_types_registered(lua);
    aubio_table.new_usertype<AubioSource>("Source",
        sol::no_constructor,
        "do", &AubioSource::do_read,
        "do-multi", &AubioSource::do_read_multi,
        "samplerate", &AubioSource::samplerate,
        "channels", &AubioSource::channels,
        "seek", &AubioSource::seek,
        "duration", &AubioSource::duration,
        "close", &AubioSource::close);

    aubio_table.new_usertype<AubioSink>("Sink",
        sol::no_constructor,
        "preset-samplerate", &AubioSink::preset_samplerate,
        "preset-channels", &AubioSink::preset_channels,
        "samplerate", &AubioSink::samplerate,
        "channels", &AubioSink::channels,
        "do", &AubioSink::do_write,
        "do-multi", &AubioSink::do_write_multi,
        "close", &AubioSink::close);

    aubio_table.set_function("Source", [](const std::string& uri, uint_t samplerate, uint_t hop_size) {
        return AubioSource(uri, samplerate, hop_size);
    });
    aubio_table.set_function("Sink", [](const std::string& uri, uint_t samplerate) {
        return AubioSink(uri, samplerate);
    });
}

} // namespace lua_aubio
