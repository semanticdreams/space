#include "lua_aubio_bindings.h"
#include "lua_aubio_types.h"

namespace lua_aubio {

void register_spectral(sol::state_view lua, sol::table& aubio_table)
{
    ensure_types_registered(lua);
    aubio_table.new_usertype<AubioFFT>("FFT",
        sol::no_constructor,
        "do", &AubioFFT::do_fft,
        "rdo", &AubioFFT::rdo_fft,
        "do-complex", &AubioFFT::do_complex,
        "rdo-complex", &AubioFFT::rdo_complex,
        "get-spectrum", &AubioFFT::get_spectrum,
        "get-realimag", &AubioFFT::get_realimag,
        "get-phas", &AubioFFT::get_phas,
        "get-imag", &AubioFFT::get_imag,
        "get-norm", &AubioFFT::get_norm,
        "get-real", &AubioFFT::get_real);

    aubio_table.new_usertype<AubioDCT>("DCT",
        sol::no_constructor,
        "do", &AubioDCT::do_dct,
        "rdo", &AubioDCT::rdo_dct);

    aubio_table.new_usertype<AubioPVoc>("PVoc",
        sol::no_constructor,
        "do", &AubioPVoc::do_pvoc,
        "rdo", &AubioPVoc::rdo_pvoc,
        "get-win", &AubioPVoc::get_win,
        "get-hop", &AubioPVoc::get_hop,
        "set-window", &AubioPVoc::set_window);

    aubio_table.new_usertype<AubioFilterbank>("Filterbank",
        sol::no_constructor,
        "do", &AubioFilterbank::do_filterbank,
        "coeffs", &AubioFilterbank::coeffs,
        "set-coeffs", &AubioFilterbank::set_coeffs,
        "set-norm", &AubioFilterbank::set_norm,
        "get-norm", &AubioFilterbank::get_norm,
        "set-power", &AubioFilterbank::set_power,
        "get-power", &AubioFilterbank::get_power,
        "set-triangle-bands", &AubioFilterbank::set_triangle_bands,
        "set-mel-coeffs-slaney", &AubioFilterbank::set_mel_coeffs_slaney,
        "set-mel-coeffs", &AubioFilterbank::set_mel_coeffs,
        "set-mel-coeffs-htk", &AubioFilterbank::set_mel_coeffs_htk);

    aubio_table.new_usertype<AubioMFCC>("MFCC",
        sol::no_constructor,
        "do", &AubioMFCC::do_mfcc,
        "set-power", &AubioMFCC::set_power,
        "get-power", &AubioMFCC::get_power,
        "set-scale", &AubioMFCC::set_scale,
        "get-scale", &AubioMFCC::get_scale,
        "set-mel-coeffs", &AubioMFCC::set_mel_coeffs,
        "set-mel-coeffs-htk", &AubioMFCC::set_mel_coeffs_htk,
        "set-mel-coeffs-slaney", &AubioMFCC::set_mel_coeffs_slaney);

    aubio_table.new_usertype<AubioSpecDesc>("SpecDesc",
        sol::no_constructor,
        "do", &AubioSpecDesc::do_specdesc);

    aubio_table.new_usertype<AubioSpectralWhitening>("SpectralWhitening",
        sol::no_constructor,
        "do", &AubioSpectralWhitening::do_whitening,
        "reset", &AubioSpectralWhitening::reset,
        "set-relax-time", &AubioSpectralWhitening::set_relax_time,
        "get-relax-time", &AubioSpectralWhitening::get_relax_time,
        "set-floor", &AubioSpectralWhitening::set_floor,
        "get-floor", &AubioSpectralWhitening::get_floor);

    aubio_table.new_usertype<AubioTSS>("TSS",
        sol::no_constructor,
        "do", &AubioTSS::do_tss,
        "set-threshold", &AubioTSS::set_threshold,
        "set-alpha", &AubioTSS::set_alpha,
        "set-beta", &AubioTSS::set_beta);

    aubio_table.set_function("FFT", [](uint_t size) { return AubioFFT(size); });
    aubio_table.set_function("DCT", [](uint_t size) { return AubioDCT(size); });
    aubio_table.set_function("PVoc", [](uint_t win_s, uint_t hop_s) { return AubioPVoc(win_s, hop_s); });
    aubio_table.set_function("Filterbank", [](uint_t n_filters, uint_t win_s) { return AubioFilterbank(n_filters, win_s); });
    aubio_table.set_function("MFCC", [](uint_t buf_size, uint_t n_filters, uint_t n_coeffs, uint_t samplerate) {
        return AubioMFCC(buf_size, n_filters, n_coeffs, samplerate);
    });
    aubio_table.set_function("SpecDesc", [](const std::string& method, uint_t buf_size) {
        return AubioSpecDesc(method, buf_size);
    });
    aubio_table.set_function("SpectralWhitening", [](uint_t buf_size, uint_t hop_size, uint_t samplerate) {
        return AubioSpectralWhitening(buf_size, hop_size, samplerate);
    });
    aubio_table.set_function("TSS", [](uint_t buf_size, uint_t hop_size) {
        return AubioTSS(buf_size, hop_size);
    });
}

} // namespace lua_aubio
