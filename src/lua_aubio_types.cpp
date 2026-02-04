#include "lua_aubio_bindings.h"
#include "lua_aubio_types.h"

namespace lua_aubio {

void ensure_types_registered(sol::state_view lua)
{
    sol::table registry = lua.registry();
    sol::optional<bool> registered = registry["aubio_types_registered"];
    if (registered && *registered) {
        return;
    }

    sol::table scratch = lua.create_table();
    scratch.new_usertype<AubioFVec>("FVec",
        sol::no_constructor,
        "length", &AubioFVec::length,
        "data", &AubioFVec::data_ptr,
        "get", &AubioFVec::get,
        "set", &AubioFVec::set,
        "set-all", &AubioFVec::set_all,
        "zeros", &AubioFVec::zeros,
        "ones", &AubioFVec::ones,
        "rev", &AubioFVec::rev,
        "weight", &AubioFVec::weight,
        "copy", &AubioFVec::copy,
        "weighted-copy", &AubioFVec::weighted_copy,
        "print", &AubioFVec::print,
        "set-window", &AubioFVec::set_window);

    scratch.new_usertype<AubioCVec>("CVec",
        sol::no_constructor,
        "length", &AubioCVec::length,
        "norm-data", &AubioCVec::norm_data_ptr,
        "phas-data", &AubioCVec::phas_data_ptr,
        "get-norm", &AubioCVec::get_norm,
        "get-phas", &AubioCVec::get_phas,
        "set-norm", &AubioCVec::set_norm,
        "set-phas", &AubioCVec::set_phas,
        "norm-set-all", &AubioCVec::norm_set_all,
        "phas-set-all", &AubioCVec::phas_set_all,
        "norm-zeros", &AubioCVec::norm_zeros,
        "phas-zeros", &AubioCVec::phas_zeros,
        "norm-ones", &AubioCVec::norm_ones,
        "phas-ones", &AubioCVec::phas_ones,
        "zeros", &AubioCVec::zeros,
        "logmag", &AubioCVec::logmag,
        "copy", &AubioCVec::copy,
        "print", &AubioCVec::print);

    scratch.new_usertype<AubioFMat>("FMat",
        sol::no_constructor,
        "length", &AubioFMat::length,
        "height", &AubioFMat::height,
        "data", &AubioFMat::data_ptr,
        "channel-data", &AubioFMat::channel_data_ptr,
        "get", &AubioFMat::get,
        "set", &AubioFMat::set,
        "get-channel", &AubioFMat::get_channel,
        "print", &AubioFMat::print,
        "set-all", &AubioFMat::set_all,
        "zeros", &AubioFMat::zeros,
        "ones", &AubioFMat::ones,
        "rev", &AubioFMat::rev,
        "weight", &AubioFMat::weight,
        "copy", &AubioFMat::copy,
        "vecmul", &AubioFMat::vecmul);

    scratch.new_usertype<AubioFMatView>("FMatView",
        sol::no_constructor,
        "length", &AubioFMatView::length,
        "height", &AubioFMatView::height,
        "data", &AubioFMatView::data_ptr,
        "channel-data", &AubioFMatView::channel_data_ptr,
        "get", &AubioFMatView::get,
        "set", &AubioFMatView::set,
        "get-channel", &AubioFMatView::get_channel,
        "print", &AubioFMatView::print);

    scratch.new_usertype<AubioLVec>("LVec",
        sol::no_constructor,
        "length", &AubioLVec::length,
        "data", &AubioLVec::data_ptr,
        "get", &AubioLVec::get,
        "set", &AubioLVec::set,
        "set-all", &AubioLVec::set_all,
        "zeros", &AubioLVec::zeros,
        "ones", &AubioLVec::ones,
        "print", &AubioLVec::print);

    scratch.new_usertype<AubioLVecView>("LVecView",
        sol::no_constructor,
        "length", &AubioLVecView::length,
        "data", &AubioLVecView::data_ptr,
        "get", &AubioLVecView::get,
        "set", &AubioLVecView::set,
        "print", &AubioLVecView::print);

    registry["aubio_types_registered"] = true;
}

} // namespace lua_aubio
