#include "lua_aubio_bindings.h"
#include "lua_aubio_types.h"

namespace lua_aubio {

void register_temporal(sol::state_view lua, sol::table& aubio_table)
{
    ensure_types_registered(lua);
    aubio_table.new_usertype<AubioPitch>("Pitch",
        sol::no_constructor,
        "do", &AubioPitch::do_pitch,
        "set-tolerance", &AubioPitch::set_tolerance,
        "get-tolerance", &AubioPitch::get_tolerance,
        "set-unit", &AubioPitch::set_unit,
        "set-silence", &AubioPitch::set_silence,
        "get-silence", &AubioPitch::get_silence,
        "get-confidence", &AubioPitch::get_confidence);

    aubio_table.new_usertype<AubioOnset>("Onset",
        sol::no_constructor,
        "do", &AubioOnset::do_onset,
        "get-last", &AubioOnset::get_last,
        "get-last-s", &AubioOnset::get_last_s,
        "get-last-ms", &AubioOnset::get_last_ms,
        "set-awhitening", &AubioOnset::set_awhitening,
        "get-awhitening", &AubioOnset::get_awhitening,
        "set-compression", &AubioOnset::set_compression,
        "get-compression", &AubioOnset::get_compression,
        "set-silence", &AubioOnset::set_silence,
        "get-silence", &AubioOnset::get_silence,
        "get-descriptor", &AubioOnset::get_descriptor,
        "get-thresholded-descriptor", &AubioOnset::get_thresholded_descriptor,
        "set-threshold", &AubioOnset::set_threshold,
        "set-minioi", &AubioOnset::set_minioi,
        "set-minioi-s", &AubioOnset::set_minioi_s,
        "set-minioi-ms", &AubioOnset::set_minioi_ms,
        "set-delay", &AubioOnset::set_delay,
        "set-delay-s", &AubioOnset::set_delay_s,
        "set-delay-ms", &AubioOnset::set_delay_ms,
        "get-minioi", &AubioOnset::get_minioi,
        "get-minioi-s", &AubioOnset::get_minioi_s,
        "get-minioi-ms", &AubioOnset::get_minioi_ms,
        "get-delay", &AubioOnset::get_delay,
        "get-delay-s", &AubioOnset::get_delay_s,
        "get-delay-ms", &AubioOnset::get_delay_ms,
        "get-threshold", &AubioOnset::get_threshold,
        "set-default-parameters", &AubioOnset::set_default_parameters,
        "reset", &AubioOnset::reset);

    aubio_table.new_usertype<AubioTempo>("Tempo",
        sol::no_constructor,
        "do", &AubioTempo::do_tempo,
        "get-last", &AubioTempo::get_last,
        "get-last-s", &AubioTempo::get_last_s,
        "get-last-ms", &AubioTempo::get_last_ms,
        "set-silence", &AubioTempo::set_silence,
        "get-silence", &AubioTempo::get_silence,
        "set-threshold", &AubioTempo::set_threshold,
        "get-threshold", &AubioTempo::get_threshold,
        "get-period", &AubioTempo::get_period,
        "get-period-s", &AubioTempo::get_period_s,
        "get-bpm", &AubioTempo::get_bpm,
        "get-confidence", &AubioTempo::get_confidence,
        "set-tatum-signature", &AubioTempo::set_tatum_signature,
        "was-tatum", &AubioTempo::was_tatum,
        "get-last-tatum", &AubioTempo::get_last_tatum,
        "get-delay", &AubioTempo::get_delay,
        "get-delay-s", &AubioTempo::get_delay_s,
        "get-delay-ms", &AubioTempo::get_delay_ms,
        "set-delay", &AubioTempo::set_delay,
        "set-delay-s", &AubioTempo::set_delay_s,
        "set-delay-ms", &AubioTempo::set_delay_ms);

    aubio_table.new_usertype<AubioNotes>("Notes",
        sol::no_constructor,
        "do", &AubioNotes::do_notes,
        "set-silence", &AubioNotes::set_silence,
        "get-silence", &AubioNotes::get_silence,
        "get-minioi-ms", &AubioNotes::get_minioi_ms,
        "set-minioi-ms", &AubioNotes::set_minioi_ms,
        "get-release-drop", &AubioNotes::get_release_drop,
        "set-release-drop", &AubioNotes::set_release_drop);

    aubio_table.new_usertype<AubioResampler>("Resampler",
        sol::no_constructor,
        "do", &AubioResampler::do_resample);

    aubio_table.new_usertype<AubioFilter>("Filter",
        sol::no_constructor,
        "do", &AubioFilter::do_filter,
        "do-outplace", &AubioFilter::do_outplace,
        "do-filtfilt", &AubioFilter::do_filtfilt,
        "feedback", &AubioFilter::feedback,
        "feedforward", &AubioFilter::feedforward,
        "order", &AubioFilter::get_order,
        "samplerate", &AubioFilter::get_samplerate,
        "set-samplerate", &AubioFilter::set_samplerate,
        "reset", &AubioFilter::reset,
        "set-biquad", &AubioFilter::set_biquad,
        "set-a-weighting", &AubioFilter::set_a_weighting,
        "set-c-weighting", &AubioFilter::set_c_weighting);

    aubio_table.set_function("Pitch", [](const std::string& method, uint_t buf_size, uint_t hop_size, uint_t samplerate) {
        return AubioPitch(method, buf_size, hop_size, samplerate);
    });
    aubio_table.set_function("Onset", [](const std::string& method, uint_t buf_size, uint_t hop_size, uint_t samplerate) {
        return AubioOnset(method, buf_size, hop_size, samplerate);
    });
    aubio_table.set_function("Tempo", [](const std::string& method, uint_t buf_size, uint_t hop_size, uint_t samplerate) {
        return AubioTempo(method, buf_size, hop_size, samplerate);
    });
    aubio_table.set_function("Notes", [](const std::string& method, uint_t buf_size, uint_t hop_size, uint_t samplerate) {
        return AubioNotes(method, buf_size, hop_size, samplerate);
    });
    aubio_table.set_function("Resampler", [](smpl_t ratio, uint_t type) {
        return AubioResampler(ratio, type);
    });
    aubio_table.set_function("Filter", [](uint_t order) { return AubioFilter(order); });
    aubio_table.set_function("FilterBiquad", [](lsmp_t b0, lsmp_t b1, lsmp_t b2, lsmp_t a1, lsmp_t a2) {
        return AubioFilter(new_aubio_filter_biquad(b0, b1, b2, a1, a2));
    });
    aubio_table.set_function("FilterAWeighting", [](uint_t samplerate) {
        return AubioFilter(new_aubio_filter_a_weighting(samplerate));
    });
    aubio_table.set_function("FilterCWeighting", [](uint_t samplerate) {
        return AubioFilter(new_aubio_filter_c_weighting(samplerate));
    });
}

} // namespace lua_aubio
