#include "lua_aubio_bindings.h"
#include "lua_aubio_types.h"

#include <aubio/fmat.h>
#include <aubio/fvec.h>
#include <aubio/mathutils.h>

#include <cmath>
#include <stdexcept>

namespace lua_aubio {

namespace {

AubioFVec mixdown_equal(const AubioFMat& matrix)
{
    uint_t channels = matrix.height();
    if (channels == 0) {
        throw std::runtime_error("fmat-mixdown-equal requires at least one channel");
    }
    uint_t frames = matrix.length();
    AubioFVec out(frames);
    smpl_t inv = static_cast<smpl_t>(1.0) / static_cast<smpl_t>(channels);
    for (uint_t i = 0; i < frames; ++i) {
        smpl_t sum = 0;
        for (uint_t ch = 0; ch < channels; ++ch) {
            sum += fmat_get_sample(matrix.value, ch, i);
        }
        fvec_set_sample(out.value, sum * inv, i);
    }
    return out;
}

AubioFVec mixdown_weighted(const AubioFMat& matrix, const AubioFVec& weights)
{
    uint_t channels = matrix.height();
    if (channels == 0) {
        throw std::runtime_error("fmat-mixdown-weighted requires at least one channel");
    }
    if (channels != weights.length()) {
        throw std::runtime_error("fmat-mixdown-weighted weights length mismatch");
    }
    uint_t frames = matrix.length();
    AubioFVec out(frames);
    for (uint_t i = 0; i < frames; ++i) {
        smpl_t sum = 0;
        for (uint_t ch = 0; ch < channels; ++ch) {
            smpl_t weight = fvec_get_sample(weights.value, ch);
            sum += weight * fmat_get_sample(matrix.value, ch, i);
        }
        fvec_set_sample(out.value, sum, i);
    }
    return out;
}

void normalize_peak(AubioFVec& buffer, smpl_t target, smpl_t floor)
{
    smpl_t peak = fvec_max(buffer.value);
    if (peak <= floor) {
        throw std::runtime_error("fvec-normalize-peak requires peak above floor");
    }
    smpl_t scale = target / peak;
    fvec_mul(buffer.value, scale);
}

void normalize_rms(AubioFVec& buffer, smpl_t target, smpl_t floor)
{
    uint_t count = buffer.length();
    if (count == 0) {
        throw std::runtime_error("fvec-normalize-rms requires non-empty buffer");
    }
    smpl_t sum = 0;
    for (uint_t i = 0; i < count; ++i) {
        smpl_t value = fvec_get_sample(buffer.value, i);
        sum += value * value;
    }
    smpl_t rms = static_cast<smpl_t>(std::sqrt(sum / static_cast<smpl_t>(count)));
    if (rms <= floor) {
        throw std::runtime_error("fvec-normalize-rms requires rms above floor");
    }
    smpl_t scale = target / rms;
    fvec_mul(buffer.value, scale);
}

} // namespace

void register_vec(sol::state_view lua, sol::table& aubio_table)
{
    ensure_types_registered(lua);

    aubio_table.set_function("FVec", [](uint_t length) { return AubioFVec(length); });
    aubio_table.set_function("CVec", [](uint_t length) { return AubioCVec(length); });
    aubio_table.set_function("FMat", [](uint_t height, uint_t length) { return AubioFMat(height, length); });
    aubio_table.set_function("LVec", [](uint_t length) { return AubioLVec(length); });

    aubio_table.set_function("fvec-exp", [](AubioFVec& vec) { fvec_exp(vec.value); });
    aubio_table.set_function("fvec-cos", [](AubioFVec& vec) { fvec_cos(vec.value); });
    aubio_table.set_function("fvec-sin", [](AubioFVec& vec) { fvec_sin(vec.value); });
    aubio_table.set_function("fvec-abs", [](AubioFVec& vec) { fvec_abs(vec.value); });
    aubio_table.set_function("fvec-sqrt", [](AubioFVec& vec) { fvec_sqrt(vec.value); });
    aubio_table.set_function("fvec-log10", [](AubioFVec& vec) { fvec_log10(vec.value); });
    aubio_table.set_function("fvec-log", [](AubioFVec& vec) { fvec_log(vec.value); });
    aubio_table.set_function("fvec-floor", [](AubioFVec& vec) { fvec_floor(vec.value); });
    aubio_table.set_function("fvec-ceil", [](AubioFVec& vec) { fvec_ceil(vec.value); });
    aubio_table.set_function("fvec-round", [](AubioFVec& vec) { fvec_round(vec.value); });
    aubio_table.set_function("fvec-pow", [](AubioFVec& vec, smpl_t pow) { fvec_pow(vec.value, pow); });

    aubio_table.set_function("fvec-mean", [](AubioFVec& vec) { return fvec_mean(vec.value); });
    aubio_table.set_function("fvec-max", [](AubioFVec& vec) { return fvec_max(vec.value); });
    aubio_table.set_function("fvec-min", [](AubioFVec& vec) { return fvec_min(vec.value); });
    aubio_table.set_function("fvec-min-elem", [](AubioFVec& vec) { return fvec_min_elem(vec.value); });
    aubio_table.set_function("fvec-max-elem", [](AubioFVec& vec) { return fvec_max_elem(vec.value); });
    aubio_table.set_function("fvec-shift", [](AubioFVec& vec) { fvec_shift(vec.value); });
    aubio_table.set_function("fvec-ishift", [](AubioFVec& vec) { fvec_ishift(vec.value); });
    aubio_table.set_function("fvec-push", [](AubioFVec& vec, smpl_t new_elem) { fvec_push(vec.value, new_elem); });
    aubio_table.set_function("fvec-sum", [](AubioFVec& vec) { return fvec_sum(vec.value); });
    aubio_table.set_function("fvec-local-hfc", [](AubioFVec& vec) { return fvec_local_hfc(vec.value); });
    aubio_table.set_function("fvec-alpha-norm", [](AubioFVec& vec, smpl_t p) { return fvec_alpha_norm(vec.value, p); });
    aubio_table.set_function("fvec-alpha-normalise", [](AubioFVec& vec, smpl_t p) { fvec_alpha_normalise(vec.value, p); });
    aubio_table.set_function("fvec-add", [](AubioFVec& vec, smpl_t c) { fvec_add(vec.value, c); });
    aubio_table.set_function("fvec-mul", [](AubioFVec& vec, smpl_t s) { fvec_mul(vec.value, s); });
    aubio_table.set_function("fvec-min-removal", [](AubioFVec& vec) { fvec_min_removal(vec.value); });
    aubio_table.set_function("fvec-moving-thres", [](AubioFVec& vec, AubioFVec& tmp, uint_t post, uint_t pre, uint_t pos) {
        return fvec_moving_thres(vec.value, tmp.value, post, pre, pos);
    });
    aubio_table.set_function("fvec-adapt-thres", [](AubioFVec& vec, AubioFVec& tmp, uint_t post, uint_t pre) {
        fvec_adapt_thres(vec.value, tmp.value, post, pre);
    });
    aubio_table.set_function("fvec-median", [](AubioFVec& vec) { return fvec_median(vec.value); });
    aubio_table.set_function("fvec-quadratic-peak-pos", [](AubioFVec& vec, uint_t p) {
        return fvec_quadratic_peak_pos(vec.value, p);
    });
    aubio_table.set_function("fvec-quadratic-peak-mag", [](AubioFVec& vec, smpl_t p) { return fvec_quadratic_peak_mag(vec.value, p); });
    aubio_table.set_function("quadfrac", &aubio_quadfrac);
    aubio_table.set_function("fvec-peakpick", [](AubioFVec& vec, uint_t p) { return fvec_peakpick(vec.value, p); });
    aubio_table.set_function("is-power-of-two", &aubio_is_power_of_two);
    aubio_table.set_function("next-power-of-two", &aubio_next_power_of_two);
    aubio_table.set_function("power-of-two-order", &aubio_power_of_two_order);
    aubio_table.set_function("autocorr", [](const AubioFVec& input, AubioFVec& output) {
        aubio_autocorr(input.value, output.value);
    });
    aubio_table.set_function("fmat-mixdown-equal", &mixdown_equal);
    aubio_table.set_function("fmat-mixdown-weighted", &mixdown_weighted);
    aubio_table.set_function("fvec-normalize-peak", [](AubioFVec& buffer, smpl_t target, smpl_t floor) {
        normalize_peak(buffer, target, floor);
    });
    aubio_table.set_function("fvec-normalize-rms", [](AubioFVec& buffer, smpl_t target, smpl_t floor) {
        normalize_rms(buffer, target, floor);
    });
}

} // namespace lua_aubio
