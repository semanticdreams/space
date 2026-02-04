#ifndef SPACE_LUA_AUBIO_TYPES_H
#define SPACE_LUA_AUBIO_TYPES_H

#include <cstddef>
#include <stdexcept>
#include <string>
#include <utility>

#include <aubio/aubio.h>
#include <aubio/utils/hist.h>
#include <aubio/utils/parameter.h>
#include <aubio/utils/scale.h>
#include <sol/sol.hpp>

namespace lua_aubio {

template <typename T>
T* ensure_handle(T* handle, const char* label)
{
    if (!handle) {
        throw std::runtime_error(std::string("aubio: failed to create ") + label);
    }
    return handle;
}

struct AubioFVec {
    explicit AubioFVec(uint_t length)
        : value(ensure_handle(new_fvec(length), "fvec"))
    {
    }

    AubioFVec(AubioFVec&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioFVec& operator=(AubioFVec&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_fvec(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioFVec(const AubioFVec&) = delete;
    AubioFVec& operator=(const AubioFVec&) = delete;

    ~AubioFVec()
    {
        if (value) {
            del_fvec(value);
        }
    }

    uint_t length() const
    {
        return value ? value->length : 0;
    }

    smpl_t get(uint_t index) const
    {
        return fvec_get_sample(value, index);
    }

    void set(uint_t index, smpl_t sample)
    {
        fvec_set_sample(value, sample, index);
    }

    void set_all(smpl_t val)
    {
        fvec_set_all(value, val);
    }

    void zeros()
    {
        fvec_zeros(value);
    }

    void ones()
    {
        fvec_ones(value);
    }

    void rev()
    {
        fvec_rev(value);
    }

    void weight(const AubioFVec& weights)
    {
        fvec_weight(value, weights.value);
    }

    void copy(AubioFVec& out) const
    {
        fvec_copy(value, out.value);
    }

    void weighted_copy(const AubioFVec& weights, AubioFVec& out) const
    {
        fvec_weighted_copy(value, weights.value, out.value);
    }

    void print() const
    {
        fvec_print(value);
    }

    void* data_ptr() const
    {
        return static_cast<void*>(fvec_get_data(value));
    }

    uint_t set_window(const std::string& window_type)
    {
        return fvec_set_window(value, const_cast<char_t*>(window_type.c_str()));
    }

    fvec_t* value = nullptr;
};

struct AubioCVec {
    explicit AubioCVec(uint_t length)
        : value(ensure_handle(new_cvec(length), "cvec"))
    {
    }

    AubioCVec(AubioCVec&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioCVec& operator=(AubioCVec&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_cvec(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioCVec(const AubioCVec&) = delete;
    AubioCVec& operator=(const AubioCVec&) = delete;

    ~AubioCVec()
    {
        if (value) {
            del_cvec(value);
        }
    }

    uint_t length() const
    {
        return value ? value->length : 0;
    }

    smpl_t get_norm(uint_t index) const
    {
        return cvec_norm_get_sample(value, index);
    }

    smpl_t get_phas(uint_t index) const
    {
        return cvec_phas_get_sample(value, index);
    }

    void set_norm(uint_t index, smpl_t sample)
    {
        cvec_norm_set_sample(value, sample, index);
    }

    void set_phas(uint_t index, smpl_t sample)
    {
        cvec_phas_set_sample(value, sample, index);
    }

    void norm_set_all(smpl_t val)
    {
        cvec_norm_set_all(value, val);
    }

    void phas_set_all(smpl_t val)
    {
        cvec_phas_set_all(value, val);
    }

    void norm_zeros()
    {
        cvec_norm_zeros(value);
    }

    void phas_zeros()
    {
        cvec_phas_zeros(value);
    }

    void norm_ones()
    {
        cvec_norm_ones(value);
    }

    void phas_ones()
    {
        cvec_phas_ones(value);
    }

    void zeros()
    {
        cvec_zeros(value);
    }

    void logmag(smpl_t lambda)
    {
        cvec_logmag(value, lambda);
    }

    void copy(AubioCVec& out) const
    {
        cvec_copy(value, out.value);
    }

    void print() const
    {
        cvec_print(value);
    }

    void* norm_data_ptr() const
    {
        return static_cast<void*>(cvec_norm_get_data(value));
    }

    void* phas_data_ptr() const
    {
        return static_cast<void*>(cvec_phas_get_data(value));
    }

    cvec_t* value = nullptr;
};

struct AubioFMat {
    AubioFMat(uint_t height, uint_t length)
        : value(ensure_handle(new_fmat(height, length), "fmat"))
    {
    }

    AubioFMat(AubioFMat&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioFMat& operator=(AubioFMat&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_fmat(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioFMat(const AubioFMat&) = delete;
    AubioFMat& operator=(const AubioFMat&) = delete;

    ~AubioFMat()
    {
        if (value) {
            del_fmat(value);
        }
    }

    uint_t length() const
    {
        return value ? value->length : 0;
    }

    uint_t height() const
    {
        return value ? value->height : 0;
    }

    smpl_t get(uint_t channel, uint_t position) const
    {
        return fmat_get_sample(value, channel, position);
    }

    void set(uint_t channel, uint_t position, smpl_t sample)
    {
        fmat_set_sample(value, sample, channel, position);
    }

    void get_channel(uint_t channel, AubioFVec& out) const
    {
        fmat_get_channel(value, channel, out.value);
    }

    void* channel_data_ptr(uint_t channel) const
    {
        return static_cast<void*>(fmat_get_channel_data(value, channel));
    }

    void* data_ptr() const
    {
        return reinterpret_cast<void*>(fmat_get_data(value));
    }

    void print() const
    {
        fmat_print(value);
    }

    void set_all(smpl_t val)
    {
        fmat_set(value, val);
    }

    void zeros()
    {
        fmat_zeros(value);
    }

    void ones()
    {
        fmat_ones(value);
    }

    void rev()
    {
        fmat_rev(value);
    }

    void weight(const AubioFMat& weights)
    {
        fmat_weight(value, weights.value);
    }

    void copy(AubioFMat& out) const
    {
        fmat_copy(value, out.value);
    }

    void vecmul(const AubioFVec& scale, AubioFVec& out) const
    {
        fmat_vecmul(value, scale.value, out.value);
    }

    fmat_t* value = nullptr;
};

struct AubioFMatView {
    explicit AubioFMatView(fmat_t* view)
        : value(view)
    {
    }

    uint_t length() const
    {
        return value ? value->length : 0;
    }

    uint_t height() const
    {
        return value ? value->height : 0;
    }

    smpl_t get(uint_t channel, uint_t position) const
    {
        return fmat_get_sample(value, channel, position);
    }

    void set(uint_t channel, uint_t position, smpl_t sample)
    {
        fmat_set_sample(value, sample, channel, position);
    }

    void get_channel(uint_t channel, AubioFVec& out) const
    {
        fmat_get_channel(value, channel, out.value);
    }

    void* channel_data_ptr(uint_t channel) const
    {
        return static_cast<void*>(fmat_get_channel_data(value, channel));
    }

    void* data_ptr() const
    {
        return reinterpret_cast<void*>(fmat_get_data(value));
    }

    void print() const
    {
        fmat_print(value);
    }

    fmat_t* value = nullptr;
};

struct AubioLVec {
    explicit AubioLVec(uint_t length)
        : value(ensure_handle(new_lvec(length), "lvec"))
    {
    }

    AubioLVec(AubioLVec&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioLVec& operator=(AubioLVec&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_lvec(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioLVec(const AubioLVec&) = delete;
    AubioLVec& operator=(const AubioLVec&) = delete;

    ~AubioLVec()
    {
        if (value) {
            del_lvec(value);
        }
    }

    uint_t length() const
    {
        return value ? value->length : 0;
    }

    lsmp_t get(uint_t index) const
    {
        return lvec_get_sample(value, index);
    }

    void set(uint_t index, lsmp_t sample)
    {
        lvec_set_sample(value, sample, index);
    }

    void set_all(lsmp_t val)
    {
        lvec_set_all(value, val);
    }

    void zeros()
    {
        lvec_zeros(value);
    }

    void ones()
    {
        lvec_ones(value);
    }

    void print() const
    {
        lvec_print(value);
    }

    void* data_ptr() const
    {
        return static_cast<void*>(lvec_get_data(value));
    }

    lvec_t* value = nullptr;
};

struct AubioLVecView {
    explicit AubioLVecView(lvec_t* view)
        : value(view)
    {
    }

    uint_t length() const
    {
        return value ? value->length : 0;
    }

    lsmp_t get(uint_t index) const
    {
        return lvec_get_sample(value, index);
    }

    void set(uint_t index, lsmp_t sample)
    {
        lvec_set_sample(value, sample, index);
    }

    void print() const
    {
        lvec_print(value);
    }

    void* data_ptr() const
    {
        return static_cast<void*>(lvec_get_data(value));
    }

    lvec_t* value = nullptr;
};

struct AubioFFT {
    explicit AubioFFT(uint_t size)
        : value(ensure_handle(new_aubio_fft(size), "fft"))
    {
    }

    AubioFFT(AubioFFT&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioFFT& operator=(AubioFFT&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_fft(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioFFT(const AubioFFT&) = delete;
    AubioFFT& operator=(const AubioFFT&) = delete;

    ~AubioFFT()
    {
        if (value) {
            del_aubio_fft(value);
        }
    }

    void do_fft(const AubioFVec& input, AubioCVec& spectrum)
    {
        aubio_fft_do(value, input.value, spectrum.value);
    }

    void rdo_fft(const AubioCVec& spectrum, AubioFVec& output)
    {
        aubio_fft_rdo(value, spectrum.value, output.value);
    }

    void do_complex(const AubioFVec& input, AubioFVec& output)
    {
        aubio_fft_do_complex(value, input.value, output.value);
    }

    void rdo_complex(const AubioFVec& input, AubioFVec& output)
    {
        aubio_fft_rdo_complex(value, input.value, output.value);
    }

    void get_spectrum(const AubioFVec& compspec, AubioCVec& spectrum)
    {
        aubio_fft_get_spectrum(compspec.value, spectrum.value);
    }

    void get_realimag(const AubioCVec& spectrum, AubioFVec& compspec)
    {
        aubio_fft_get_realimag(spectrum.value, compspec.value);
    }

    void get_phas(const AubioFVec& compspec, AubioCVec& spectrum)
    {
        aubio_fft_get_phas(compspec.value, spectrum.value);
    }

    void get_imag(const AubioCVec& spectrum, AubioFVec& compspec)
    {
        aubio_fft_get_imag(spectrum.value, compspec.value);
    }

    void get_norm(const AubioFVec& compspec, AubioCVec& spectrum)
    {
        aubio_fft_get_norm(compspec.value, spectrum.value);
    }

    void get_real(const AubioCVec& spectrum, AubioFVec& compspec)
    {
        aubio_fft_get_real(spectrum.value, compspec.value);
    }

    aubio_fft_t* value = nullptr;
};

struct AubioDCT {
    explicit AubioDCT(uint_t size)
        : value(ensure_handle(new_aubio_dct(size), "dct"))
    {
    }

    AubioDCT(AubioDCT&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioDCT& operator=(AubioDCT&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_dct(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioDCT(const AubioDCT&) = delete;
    AubioDCT& operator=(const AubioDCT&) = delete;

    ~AubioDCT()
    {
        if (value) {
            del_aubio_dct(value);
        }
    }

    void do_dct(const AubioFVec& input, AubioFVec& output)
    {
        aubio_dct_do(value, input.value, output.value);
    }

    void rdo_dct(const AubioFVec& input, AubioFVec& output)
    {
        aubio_dct_rdo(value, input.value, output.value);
    }

    aubio_dct_t* value = nullptr;
};

struct AubioPVoc {
    AubioPVoc(uint_t win_s, uint_t hop_s)
        : value(ensure_handle(new_aubio_pvoc(win_s, hop_s), "pvoc"))
    {
    }

    AubioPVoc(AubioPVoc&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioPVoc& operator=(AubioPVoc&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_pvoc(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioPVoc(const AubioPVoc&) = delete;
    AubioPVoc& operator=(const AubioPVoc&) = delete;

    ~AubioPVoc()
    {
        if (value) {
            del_aubio_pvoc(value);
        }
    }

    void do_pvoc(const AubioFVec& input, AubioCVec& output)
    {
        aubio_pvoc_do(value, input.value, output.value);
    }

    void rdo_pvoc(AubioCVec& input, AubioFVec& output)
    {
        aubio_pvoc_rdo(value, input.value, output.value);
    }

    uint_t get_win() const
    {
        return aubio_pvoc_get_win(value);
    }

    uint_t get_hop() const
    {
        return aubio_pvoc_get_hop(value);
    }

    uint_t set_window(const std::string& window)
    {
        return aubio_pvoc_set_window(value, window.c_str());
    }

    aubio_pvoc_t* value = nullptr;
};

struct AubioFilterbank {
    AubioFilterbank(uint_t n_filters, uint_t win_s)
        : value(ensure_handle(new_aubio_filterbank(n_filters, win_s), "filterbank"))
    {
    }

    AubioFilterbank(AubioFilterbank&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioFilterbank& operator=(AubioFilterbank&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_filterbank(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioFilterbank(const AubioFilterbank&) = delete;
    AubioFilterbank& operator=(const AubioFilterbank&) = delete;

    ~AubioFilterbank()
    {
        if (value) {
            del_aubio_filterbank(value);
        }
    }

    void do_filterbank(const AubioCVec& input, AubioFVec& output)
    {
        aubio_filterbank_do(value, input.value, output.value);
    }

    AubioFMatView coeffs() const
    {
        return AubioFMatView(aubio_filterbank_get_coeffs(value));
    }

    uint_t set_coeffs(const AubioFMat& filters)
    {
        return aubio_filterbank_set_coeffs(value, filters.value);
    }

    uint_t set_norm(smpl_t norm)
    {
        return aubio_filterbank_set_norm(value, norm);
    }

    smpl_t get_norm() const
    {
        return aubio_filterbank_get_norm(value);
    }

    uint_t set_power(smpl_t power)
    {
        return aubio_filterbank_set_power(value, power);
    }

    smpl_t get_power() const
    {
        return aubio_filterbank_get_power(value);
    }

    uint_t set_triangle_bands(const AubioFVec& freqs, smpl_t samplerate)
    {
        return aubio_filterbank_set_triangle_bands(value, freqs.value, samplerate);
    }

    uint_t set_mel_coeffs_slaney(smpl_t samplerate)
    {
        return aubio_filterbank_set_mel_coeffs_slaney(value, samplerate);
    }

    uint_t set_mel_coeffs(smpl_t samplerate, smpl_t fmin, smpl_t fmax)
    {
        return aubio_filterbank_set_mel_coeffs(value, samplerate, fmin, fmax);
    }

    uint_t set_mel_coeffs_htk(smpl_t samplerate, smpl_t fmin, smpl_t fmax)
    {
        return aubio_filterbank_set_mel_coeffs_htk(value, samplerate, fmin, fmax);
    }

    aubio_filterbank_t* value = nullptr;
};

struct AubioMFCC {
    AubioMFCC(uint_t buf_size, uint_t n_filters, uint_t n_coeffs, uint_t samplerate)
        : value(ensure_handle(new_aubio_mfcc(buf_size, n_filters, n_coeffs, samplerate), "mfcc"))
    {
    }

    AubioMFCC(AubioMFCC&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioMFCC& operator=(AubioMFCC&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_mfcc(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioMFCC(const AubioMFCC&) = delete;
    AubioMFCC& operator=(const AubioMFCC&) = delete;

    ~AubioMFCC()
    {
        if (value) {
            del_aubio_mfcc(value);
        }
    }

    void do_mfcc(const AubioCVec& input, AubioFVec& output)
    {
        aubio_mfcc_do(value, input.value, output.value);
    }

    uint_t set_power(smpl_t power)
    {
        return aubio_mfcc_set_power(value, power);
    }

    smpl_t get_power() const
    {
        return aubio_mfcc_get_power(value);
    }

    uint_t set_scale(smpl_t scale)
    {
        return aubio_mfcc_set_scale(value, scale);
    }

    smpl_t get_scale() const
    {
        return aubio_mfcc_get_scale(value);
    }

    uint_t set_mel_coeffs(smpl_t fmin, smpl_t fmax)
    {
        return aubio_mfcc_set_mel_coeffs(value, fmin, fmax);
    }

    uint_t set_mel_coeffs_htk(smpl_t fmin, smpl_t fmax)
    {
        return aubio_mfcc_set_mel_coeffs_htk(value, fmin, fmax);
    }

    uint_t set_mel_coeffs_slaney()
    {
        return aubio_mfcc_set_mel_coeffs_slaney(value);
    }

    aubio_mfcc_t* value = nullptr;
};

struct AubioSpecDesc {
    AubioSpecDesc(const std::string& method, uint_t buf_size)
        : value(ensure_handle(new_aubio_specdesc(method.c_str(), buf_size), "specdesc"))
    {
    }

    AubioSpecDesc(AubioSpecDesc&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioSpecDesc& operator=(AubioSpecDesc&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_specdesc(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioSpecDesc(const AubioSpecDesc&) = delete;
    AubioSpecDesc& operator=(const AubioSpecDesc&) = delete;

    ~AubioSpecDesc()
    {
        if (value) {
            del_aubio_specdesc(value);
        }
    }

    void do_specdesc(const AubioCVec& input, AubioFVec& output)
    {
        aubio_specdesc_do(value, input.value, output.value);
    }

    aubio_specdesc_t* value = nullptr;
};

struct AubioSpectralWhitening {
    AubioSpectralWhitening(uint_t buf_size, uint_t hop_size, uint_t samplerate)
        : value(ensure_handle(new_aubio_spectral_whitening(buf_size, hop_size, samplerate), "spectral_whitening"))
    {
    }

    AubioSpectralWhitening(AubioSpectralWhitening&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioSpectralWhitening& operator=(AubioSpectralWhitening&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_spectral_whitening(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioSpectralWhitening(const AubioSpectralWhitening&) = delete;
    AubioSpectralWhitening& operator=(const AubioSpectralWhitening&) = delete;

    ~AubioSpectralWhitening()
    {
        if (value) {
            del_aubio_spectral_whitening(value);
        }
    }

    void do_whitening(AubioCVec& input)
    {
        aubio_spectral_whitening_do(value, input.value);
    }

    void reset()
    {
        aubio_spectral_whitening_reset(value);
    }

    uint_t set_relax_time(smpl_t relax_time)
    {
        return aubio_spectral_whitening_set_relax_time(value, relax_time);
    }

    smpl_t get_relax_time() const
    {
        return aubio_spectral_whitening_get_relax_time(value);
    }

    uint_t set_floor(smpl_t floor)
    {
        return aubio_spectral_whitening_set_floor(value, floor);
    }

    smpl_t get_floor() const
    {
        return aubio_spectral_whitening_get_floor(value);
    }

    aubio_spectral_whitening_t* value = nullptr;
};

struct AubioTSS {
    AubioTSS(uint_t buf_size, uint_t hop_size)
        : value(ensure_handle(new_aubio_tss(buf_size, hop_size), "tss"))
    {
    }

    AubioTSS(AubioTSS&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioTSS& operator=(AubioTSS&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_tss(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioTSS(const AubioTSS&) = delete;
    AubioTSS& operator=(const AubioTSS&) = delete;

    ~AubioTSS()
    {
        if (value) {
            del_aubio_tss(value);
        }
    }

    void do_tss(const AubioCVec& input, AubioCVec& trans, AubioCVec& stead)
    {
        aubio_tss_do(value, input.value, trans.value, stead.value);
    }

    uint_t set_threshold(smpl_t threshold)
    {
        return aubio_tss_set_threshold(value, threshold);
    }

    uint_t set_alpha(smpl_t alpha)
    {
        return aubio_tss_set_alpha(value, alpha);
    }

    uint_t set_beta(smpl_t beta)
    {
        return aubio_tss_set_beta(value, beta);
    }

    aubio_tss_t* value = nullptr;
};

struct AubioPitch {
    AubioPitch(const std::string& method, uint_t buf_size, uint_t hop_size, uint_t samplerate)
        : value(ensure_handle(new_aubio_pitch(method.c_str(), buf_size, hop_size, samplerate), "pitch"))
    {
    }

    AubioPitch(AubioPitch&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioPitch& operator=(AubioPitch&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_pitch(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioPitch(const AubioPitch&) = delete;
    AubioPitch& operator=(const AubioPitch&) = delete;

    ~AubioPitch()
    {
        if (value) {
            del_aubio_pitch(value);
        }
    }

    void do_pitch(const AubioFVec& input, AubioFVec& output)
    {
        aubio_pitch_do(value, input.value, output.value);
    }

    uint_t set_tolerance(smpl_t tol)
    {
        return aubio_pitch_set_tolerance(value, tol);
    }

    smpl_t get_tolerance() const
    {
        return aubio_pitch_get_tolerance(value);
    }

    uint_t set_unit(const std::string& unit)
    {
        return aubio_pitch_set_unit(value, unit.c_str());
    }

    uint_t set_silence(smpl_t silence)
    {
        return aubio_pitch_set_silence(value, silence);
    }

    smpl_t get_silence() const
    {
        return aubio_pitch_get_silence(value);
    }

    smpl_t get_confidence() const
    {
        return aubio_pitch_get_confidence(value);
    }

    aubio_pitch_t* value = nullptr;
};

struct AubioOnset {
    AubioOnset(const std::string& method, uint_t buf_size, uint_t hop_size, uint_t samplerate)
        : value(ensure_handle(new_aubio_onset(method.c_str(), buf_size, hop_size, samplerate), "onset"))
    {
    }

    AubioOnset(AubioOnset&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioOnset& operator=(AubioOnset&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_onset(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioOnset(const AubioOnset&) = delete;
    AubioOnset& operator=(const AubioOnset&) = delete;

    ~AubioOnset()
    {
        if (value) {
            del_aubio_onset(value);
        }
    }

    void do_onset(const AubioFVec& input, AubioFVec& output)
    {
        aubio_onset_do(value, input.value, output.value);
    }

    uint_t get_last() const
    {
        return aubio_onset_get_last(value);
    }

    smpl_t get_last_s() const
    {
        return aubio_onset_get_last_s(value);
    }

    smpl_t get_last_ms() const
    {
        return aubio_onset_get_last_ms(value);
    }

    uint_t set_awhitening(uint_t enable)
    {
        return aubio_onset_set_awhitening(value, enable);
    }

    smpl_t get_awhitening() const
    {
        return aubio_onset_get_awhitening(value);
    }

    uint_t set_compression(smpl_t lambda)
    {
        return aubio_onset_set_compression(value, lambda);
    }

    smpl_t get_compression() const
    {
        return aubio_onset_get_compression(value);
    }

    uint_t set_silence(smpl_t silence)
    {
        return aubio_onset_set_silence(value, silence);
    }

    smpl_t get_silence() const
    {
        return aubio_onset_get_silence(value);
    }

    smpl_t get_descriptor() const
    {
        return aubio_onset_get_descriptor(value);
    }

    smpl_t get_thresholded_descriptor() const
    {
        return aubio_onset_get_thresholded_descriptor(value);
    }

    uint_t set_threshold(smpl_t threshold)
    {
        return aubio_onset_set_threshold(value, threshold);
    }

    uint_t set_minioi(uint_t minioi)
    {
        return aubio_onset_set_minioi(value, minioi);
    }

    uint_t set_minioi_s(smpl_t minioi)
    {
        return aubio_onset_set_minioi_s(value, minioi);
    }

    uint_t set_minioi_ms(smpl_t minioi)
    {
        return aubio_onset_set_minioi_ms(value, minioi);
    }

    uint_t set_delay(uint_t delay)
    {
        return aubio_onset_set_delay(value, delay);
    }

    uint_t set_delay_s(smpl_t delay)
    {
        return aubio_onset_set_delay_s(value, delay);
    }

    uint_t set_delay_ms(smpl_t delay)
    {
        return aubio_onset_set_delay_ms(value, delay);
    }

    uint_t get_minioi() const
    {
        return aubio_onset_get_minioi(value);
    }

    smpl_t get_minioi_s() const
    {
        return aubio_onset_get_minioi_s(value);
    }

    smpl_t get_minioi_ms() const
    {
        return aubio_onset_get_minioi_ms(value);
    }

    uint_t get_delay() const
    {
        return aubio_onset_get_delay(value);
    }

    smpl_t get_delay_s() const
    {
        return aubio_onset_get_delay_s(value);
    }

    smpl_t get_delay_ms() const
    {
        return aubio_onset_get_delay_ms(value);
    }

    smpl_t get_threshold() const
    {
        return aubio_onset_get_threshold(value);
    }

    uint_t set_default_parameters(const std::string& mode)
    {
        return aubio_onset_set_default_parameters(value, mode.c_str());
    }

    void reset()
    {
        aubio_onset_reset(value);
    }

    aubio_onset_t* value = nullptr;
};

struct AubioTempo {
    AubioTempo(const std::string& method, uint_t buf_size, uint_t hop_size, uint_t samplerate)
        : value(ensure_handle(new_aubio_tempo(method.c_str(), buf_size, hop_size, samplerate), "tempo"))
    {
    }

    AubioTempo(AubioTempo&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioTempo& operator=(AubioTempo&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_tempo(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioTempo(const AubioTempo&) = delete;
    AubioTempo& operator=(const AubioTempo&) = delete;

    ~AubioTempo()
    {
        if (value) {
            del_aubio_tempo(value);
        }
    }

    void do_tempo(const AubioFVec& input, AubioFVec& output)
    {
        aubio_tempo_do(value, input.value, output.value);
    }

    uint_t get_last() const
    {
        return aubio_tempo_get_last(value);
    }

    smpl_t get_last_s() const
    {
        return aubio_tempo_get_last_s(value);
    }

    smpl_t get_last_ms() const
    {
        return aubio_tempo_get_last_ms(value);
    }

    uint_t set_silence(smpl_t silence)
    {
        return aubio_tempo_set_silence(value, silence);
    }

    smpl_t get_silence() const
    {
        return aubio_tempo_get_silence(value);
    }

    uint_t set_threshold(smpl_t threshold)
    {
        return aubio_tempo_set_threshold(value, threshold);
    }

    smpl_t get_threshold() const
    {
        return aubio_tempo_get_threshold(value);
    }

    smpl_t get_period() const
    {
        return aubio_tempo_get_period(value);
    }

    smpl_t get_period_s() const
    {
        return aubio_tempo_get_period_s(value);
    }

    smpl_t get_bpm() const
    {
        return aubio_tempo_get_bpm(value);
    }

    smpl_t get_confidence() const
    {
        return aubio_tempo_get_confidence(value);
    }

    uint_t set_tatum_signature(uint_t signature)
    {
        return aubio_tempo_set_tatum_signature(value, signature);
    }

    uint_t was_tatum() const
    {
        return aubio_tempo_was_tatum(value);
    }

    smpl_t get_last_tatum() const
    {
        return aubio_tempo_get_last_tatum(value);
    }

    uint_t get_delay() const
    {
        return aubio_tempo_get_delay(value);
    }

    smpl_t get_delay_s() const
    {
        return aubio_tempo_get_delay_s(value);
    }

    smpl_t get_delay_ms() const
    {
        return aubio_tempo_get_delay_ms(value);
    }

    uint_t set_delay(sint_t delay)
    {
        return aubio_tempo_set_delay(value, delay);
    }

    uint_t set_delay_s(smpl_t delay)
    {
        return aubio_tempo_set_delay_s(value, delay);
    }

    uint_t set_delay_ms(smpl_t delay)
    {
        return aubio_tempo_set_delay_ms(value, delay);
    }

    aubio_tempo_t* value = nullptr;
};

struct AubioNotes {
    AubioNotes(const std::string& method, uint_t buf_size, uint_t hop_size, uint_t samplerate)
        : value(ensure_handle(new_aubio_notes(method.c_str(), buf_size, hop_size, samplerate), "notes"))
    {
    }

    AubioNotes(AubioNotes&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioNotes& operator=(AubioNotes&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_notes(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioNotes(const AubioNotes&) = delete;
    AubioNotes& operator=(const AubioNotes&) = delete;

    ~AubioNotes()
    {
        if (value) {
            del_aubio_notes(value);
        }
    }

    void do_notes(const AubioFVec& input, AubioFVec& output)
    {
        aubio_notes_do(value, input.value, output.value);
    }

    uint_t set_silence(smpl_t silence)
    {
        return aubio_notes_set_silence(value, silence);
    }

    smpl_t get_silence() const
    {
        return aubio_notes_get_silence(value);
    }

    smpl_t get_minioi_ms() const
    {
        return aubio_notes_get_minioi_ms(value);
    }

    uint_t set_minioi_ms(smpl_t minioi)
    {
        return aubio_notes_set_minioi_ms(value, minioi);
    }

    smpl_t get_release_drop() const
    {
        return aubio_notes_get_release_drop(value);
    }

    uint_t set_release_drop(smpl_t release_drop)
    {
        return aubio_notes_set_release_drop(value, release_drop);
    }

    aubio_notes_t* value = nullptr;
};

struct AubioResampler {
    AubioResampler(smpl_t ratio, uint_t type)
        : value(ensure_handle(new_aubio_resampler(ratio, type), "resampler"))
    {
    }

    AubioResampler(AubioResampler&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioResampler& operator=(AubioResampler&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_resampler(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioResampler(const AubioResampler&) = delete;
    AubioResampler& operator=(const AubioResampler&) = delete;

    ~AubioResampler()
    {
        if (value) {
            del_aubio_resampler(value);
        }
    }

    void do_resample(const AubioFVec& input, AubioFVec& output)
    {
        aubio_resampler_do(value, input.value, output.value);
    }

    aubio_resampler_t* value = nullptr;
};

struct AubioFilter {
    explicit AubioFilter(uint_t order)
        : value(ensure_handle(new_aubio_filter(order), "filter"))
    {
    }

    explicit AubioFilter(aubio_filter_t* handle)
        : value(ensure_handle(handle, "filter"))
    {
    }

    AubioFilter(AubioFilter&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioFilter& operator=(AubioFilter&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_filter(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioFilter(const AubioFilter&) = delete;
    AubioFilter& operator=(const AubioFilter&) = delete;

    ~AubioFilter()
    {
        if (value) {
            del_aubio_filter(value);
        }
    }

    void do_filter(AubioFVec& input)
    {
        aubio_filter_do(value, input.value);
    }

    void do_outplace(const AubioFVec& input, AubioFVec& output)
    {
        aubio_filter_do_outplace(value, input.value, output.value);
    }

    void do_filtfilt(AubioFVec& input, AubioFVec& temp)
    {
        aubio_filter_do_filtfilt(value, input.value, temp.value);
    }

    AubioLVecView feedback() const
    {
        return AubioLVecView(aubio_filter_get_feedback(value));
    }

    AubioLVecView feedforward() const
    {
        return AubioLVecView(aubio_filter_get_feedforward(value));
    }

    uint_t get_order() const
    {
        return aubio_filter_get_order(value);
    }

    uint_t get_samplerate() const
    {
        return aubio_filter_get_samplerate(value);
    }

    uint_t set_samplerate(uint_t samplerate)
    {
        return aubio_filter_set_samplerate(value, samplerate);
    }

    void reset()
    {
        aubio_filter_do_reset(value);
    }

    uint_t set_biquad(lsmp_t b0, lsmp_t b1, lsmp_t b2, lsmp_t a1, lsmp_t a2)
    {
        return aubio_filter_set_biquad(value, b0, b1, b2, a1, a2);
    }

    uint_t set_a_weighting(uint_t samplerate)
    {
        return aubio_filter_set_a_weighting(value, samplerate);
    }

    uint_t set_c_weighting(uint_t samplerate)
    {
        return aubio_filter_set_c_weighting(value, samplerate);
    }

    aubio_filter_t* value = nullptr;
};

struct AubioSource {
    AubioSource(const std::string& uri, uint_t samplerate, uint_t hop_size)
        : value(ensure_handle(new_aubio_source(uri.c_str(), samplerate, hop_size), "source"))
    {
    }

    AubioSource(AubioSource&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioSource& operator=(AubioSource&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_source(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioSource(const AubioSource&) = delete;
    AubioSource& operator=(const AubioSource&) = delete;

    ~AubioSource()
    {
        if (value) {
            del_aubio_source(value);
        }
    }

    uint_t do_read(AubioFVec& output)
    {
        uint_t read = 0;
        aubio_source_do(value, output.value, &read);
        return read;
    }

    uint_t do_read_multi(AubioFMat& output)
    {
        uint_t read = 0;
        aubio_source_do_multi(value, output.value, &read);
        return read;
    }

    uint_t samplerate() const
    {
        return aubio_source_get_samplerate(value);
    }

    uint_t channels() const
    {
        return aubio_source_get_channels(value);
    }

    uint_t seek(uint_t pos)
    {
        return aubio_source_seek(value, pos);
    }

    uint_t duration() const
    {
        return aubio_source_get_duration(value);
    }

    uint_t close()
    {
        return aubio_source_close(value);
    }

    aubio_source_t* value = nullptr;
};

struct AubioSink {
    AubioSink(const std::string& uri, uint_t samplerate)
        : value(ensure_handle(new_aubio_sink(uri.c_str(), samplerate), "sink"))
    {
    }

    AubioSink(AubioSink&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioSink& operator=(AubioSink&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_sink(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioSink(const AubioSink&) = delete;
    AubioSink& operator=(const AubioSink&) = delete;

    ~AubioSink()
    {
        if (value) {
            del_aubio_sink(value);
        }
    }

    uint_t preset_samplerate(uint_t samplerate)
    {
        return aubio_sink_preset_samplerate(value, samplerate);
    }

    uint_t preset_channels(uint_t channels)
    {
        return aubio_sink_preset_channels(value, channels);
    }

    uint_t samplerate() const
    {
        return aubio_sink_get_samplerate(value);
    }

    uint_t channels() const
    {
        return aubio_sink_get_channels(value);
    }

    void do_write(AubioFVec& input, uint_t frames)
    {
        aubio_sink_do(value, input.value, frames);
    }

    void do_write_multi(AubioFMat& input, uint_t frames)
    {
        aubio_sink_do_multi(value, input.value, frames);
    }

    uint_t close()
    {
        return aubio_sink_close(value);
    }

    aubio_sink_t* value = nullptr;
};

struct AubioSampler {
    AubioSampler(uint_t samplerate, uint_t hop_size)
        : value(ensure_handle(new_aubio_sampler(samplerate, hop_size), "sampler"))
    {
    }

    AubioSampler(AubioSampler&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioSampler& operator=(AubioSampler&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_sampler(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioSampler(const AubioSampler&) = delete;
    AubioSampler& operator=(const AubioSampler&) = delete;

    ~AubioSampler()
    {
        if (value) {
            del_aubio_sampler(value);
        }
    }

    uint_t load(const std::string& uri)
    {
        return aubio_sampler_load(value, uri.c_str());
    }

    void do_sampler(sol::object input, AubioFVec& output)
    {
        const fvec_t* in = nullptr;
        if (input.is<AubioFVec>()) {
            in = input.as<AubioFVec&>().value;
        }
        aubio_sampler_do(value, in, output.value);
    }

    void do_sampler_multi(sol::object input, AubioFMat& output)
    {
        const fmat_t* in = nullptr;
        if (input.is<AubioFMat>()) {
            in = input.as<AubioFMat&>().value;
        }
        aubio_sampler_do_multi(value, in, output.value);
    }

    uint_t get_playing() const
    {
        return aubio_sampler_get_playing(value);
    }

    uint_t set_playing(uint_t playing)
    {
        return aubio_sampler_set_playing(value, playing);
    }

    uint_t play()
    {
        return aubio_sampler_play(value);
    }

    uint_t stop()
    {
        return aubio_sampler_stop(value);
    }

    aubio_sampler_t* value = nullptr;
};

struct AubioWavetable {
    AubioWavetable(uint_t samplerate, uint_t hop_size)
        : value(ensure_handle(new_aubio_wavetable(samplerate, hop_size), "wavetable"))
    {
    }

    AubioWavetable(AubioWavetable&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioWavetable& operator=(AubioWavetable&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_wavetable(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioWavetable(const AubioWavetable&) = delete;
    AubioWavetable& operator=(const AubioWavetable&) = delete;

    ~AubioWavetable()
    {
        if (value) {
            del_aubio_wavetable(value);
        }
    }

    uint_t load(const std::string& uri)
    {
        return aubio_wavetable_load(value, uri.c_str());
    }

    void do_wavetable(sol::object input, AubioFVec& output)
    {
        const fvec_t* in = nullptr;
        if (input.is<AubioFVec>()) {
            in = input.as<AubioFVec&>().value;
        }
        aubio_wavetable_do(value, in, output.value);
    }

    void do_wavetable_multi(sol::object input, AubioFMat& output)
    {
        const fmat_t* in = nullptr;
        if (input.is<AubioFMat>()) {
            in = input.as<AubioFMat&>().value;
        }
        aubio_wavetable_do_multi(value, in, output.value);
    }

    uint_t get_playing() const
    {
        return aubio_wavetable_get_playing(value);
    }

    uint_t set_playing(uint_t playing)
    {
        return aubio_wavetable_set_playing(value, playing);
    }

    uint_t play()
    {
        return aubio_wavetable_play(value);
    }

    uint_t stop()
    {
        return aubio_wavetable_stop(value);
    }

    uint_t set_freq(smpl_t freq)
    {
        return aubio_wavetable_set_freq(value, freq);
    }

    smpl_t get_freq() const
    {
        return aubio_wavetable_get_freq(value);
    }

    uint_t set_amp(smpl_t amp)
    {
        return aubio_wavetable_set_amp(value, amp);
    }

    smpl_t get_amp() const
    {
        return aubio_wavetable_get_amp(value);
    }

    aubio_wavetable_t* value = nullptr;
};

struct AubioParameter {
    AubioParameter(smpl_t min_value, smpl_t max_value, uint_t steps)
        : value(ensure_handle(new_aubio_parameter(min_value, max_value, steps), "parameter"))
    {
    }

    AubioParameter(AubioParameter&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioParameter& operator=(AubioParameter&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_parameter(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioParameter(const AubioParameter&) = delete;
    AubioParameter& operator=(const AubioParameter&) = delete;

    ~AubioParameter()
    {
        if (value) {
            del_aubio_parameter(value);
        }
    }

    uint_t set_target_value(smpl_t value_in)
    {
        return aubio_parameter_set_target_value(value, value_in);
    }

    smpl_t get_next_value()
    {
        return aubio_parameter_get_next_value(value);
    }

    smpl_t get_current_value() const
    {
        return aubio_parameter_get_current_value(value);
    }

    uint_t set_current_value(smpl_t value_in)
    {
        return aubio_parameter_set_current_value(value, value_in);
    }

    uint_t set_steps(uint_t steps)
    {
        return aubio_parameter_set_steps(value, steps);
    }

    uint_t get_steps() const
    {
        return aubio_parameter_get_steps(value);
    }

    uint_t set_min_value(smpl_t min_value)
    {
        return aubio_parameter_set_min_value(value, min_value);
    }

    smpl_t get_min_value() const
    {
        return aubio_parameter_get_min_value(value);
    }

    uint_t set_max_value(smpl_t max_value)
    {
        return aubio_parameter_set_max_value(value, max_value);
    }

    smpl_t get_max_value() const
    {
        return aubio_parameter_get_max_value(value);
    }

    aubio_parameter_t* value = nullptr;
};

struct AubioScale {
    AubioScale(smpl_t flow, smpl_t fhig, smpl_t ilow, smpl_t ihig)
        : value(ensure_handle(new_aubio_scale(flow, fhig, ilow, ihig), "scale"))
    {
    }

    AubioScale(AubioScale&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioScale& operator=(AubioScale&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_scale(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioScale(const AubioScale&) = delete;
    AubioScale& operator=(const AubioScale&) = delete;

    ~AubioScale()
    {
        if (value) {
            del_aubio_scale(value);
        }
    }

    void do_scale(AubioFVec& input)
    {
        aubio_scale_do(value, input.value);
    }

    uint_t set_limits(smpl_t ilow, smpl_t ihig, smpl_t olow, smpl_t ohig)
    {
        return aubio_scale_set_limits(value, ilow, ihig, olow, ohig);
    }

    aubio_scale_t* value = nullptr;
};

struct AubioHist {
    AubioHist(smpl_t flow, smpl_t fhig, uint_t nelems)
        : value(ensure_handle(new_aubio_hist(flow, fhig, nelems), "hist"))
    {
    }

    AubioHist(AubioHist&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    AubioHist& operator=(AubioHist&& other) noexcept
    {
        if (this == &other) {
            return *this;
        }
        if (value) {
            del_aubio_hist(value);
        }
        value = other.value;
        other.value = nullptr;
        return *this;
    }

    AubioHist(const AubioHist&) = delete;
    AubioHist& operator=(const AubioHist&) = delete;

    ~AubioHist()
    {
        if (value) {
            del_aubio_hist(value);
        }
    }

    void do_hist(AubioFVec& input)
    {
        aubio_hist_do(value, input.value);
    }

    void do_hist_notnull(AubioFVec& input)
    {
        aubio_hist_do_notnull(value, input.value);
    }

    smpl_t mean() const
    {
        return aubio_hist_mean(value);
    }

    void weight()
    {
        aubio_hist_weight(value);
    }

    void dyn_notnull(AubioFVec& input)
    {
        aubio_hist_dyn_notnull(value, input.value);
    }

    aubio_hist_t* value = nullptr;
};

} // namespace lua_aubio

#endif // SPACE_LUA_AUBIO_TYPES_H
