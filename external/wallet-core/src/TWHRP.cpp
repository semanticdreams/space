// SPDX-License-Identifier: Apache-2.0
//
// Copyright 9 2017 Trust Wallet.
//
// This is a GENERATED FILE from \registry.json, changes made here WILL BE LOST.
//

#include <TrustWalletCore/TWHRP.h>

#include <cstring>

const char* stringForHRP(enum TWHRP hrp) {
    switch (hrp) {
    case TWHRPBitcoin:
        return HRP_BITCOIN;
    case TWHRPLitecoin:
        return HRP_LITECOIN;
    case TWHRPViacoin:
        return HRP_VIACOIN;
    case TWHRPGroestlcoin:
        return HRP_GROESTLCOIN;
    case TWHRPDigiByte:
        return HRP_DIGIBYTE;
    case TWHRPMonacoin:
        return HRP_MONACOIN;
    case TWHRPSyscoin:
        return HRP_SYSCOIN;
    case TWHRPVerge:
        return HRP_VERGE;
    case TWHRPCosmos:
        return HRP_COSMOS;
    case TWHRPStargaze:
        return HRP_STARGAZE;
    case TWHRPJuno:
        return HRP_JUNO;
    case TWHRPStride:
        return HRP_STRIDE;
    case TWHRPAxelar:
        return HRP_AXELAR;
    case TWHRPCrescent:
        return HRP_CRESCENT;
    case TWHRPKujira:
        return HRP_KUJIRA;
    case TWHRPComdex:
        return HRP_COMDEX;
    case TWHRPNeutron:
        return HRP_NEUTRON;
    case TWHRPSommelier:
        return HRP_SOMMELIER;
    case TWHRPFetchAI:
        return HRP_FETCHAI;
    case TWHRPMars:
        return HRP_MARS;
    case TWHRPUmee:
        return HRP_UMEE;
    case TWHRPNoble:
        return HRP_NOBLE;
    case TWHRPSei:
        return HRP_SEI;
    case TWHRPTia:
        return HRP_TIA;
    case TWHRPCoreum:
        return HRP_COREUM;
    case TWHRPQuasar:
        return HRP_QUASAR;
    case TWHRPPersistence:
        return HRP_PERSISTENCE;
    case TWHRPAkash:
        return HRP_AKASH;
    case TWHRPZcash:
        return HRP_ZCASH;
    case TWHRPBitcoinCash:
        return HRP_BITCOINCASH;
    case TWHRPBitcoinGold:
        return HRP_BITCOINGOLD;
    case TWHRPIoTeX:
        return HRP_IOTEX;
    case TWHRPNervos:
        return HRP_NERVOS;
    case TWHRPZilliqa:
        return HRP_ZILLIQA;
    case TWHRPTerra:
        return HRP_TERRA;
    case TWHRPTerraV2:
        return HRP_TERRAV2;
    case TWHRPKava:
        return HRP_KAVA;
    case TWHRPBluzelle:
        return HRP_BLUZELLE;
    case TWHRPBandChain:
        return HRP_BAND;
    case TWHRPMultiversX:
        return HRP_ELROND;
    case TWHRPBinance:
        return HRP_BINANCE;
    case TWHRPTBinance:
        return HRP_TBINANCE;
    case TWHRPBitcoinDiamond:
        return HRP_BITCOINDIAMOND;
    case TWHRPHarmony:
        return HRP_HARMONY;
    case TWHRPOasis:
        return HRP_OASIS;
    case TWHRPCardano:
        return HRP_CARDANO;
    case TWHRPQtum:
        return HRP_QTUM;
    case TWHRPTHORChain:
        return HRP_THORCHAIN;
    case TWHRPCryptoOrg:
        return HRP_CRYPTOORG;
    case TWHRPSecret:
        return HRP_SECRET;
    case TWHRPOsmosis:
        return HRP_OSMOSIS;
    case TWHRPECash:
        return HRP_ECASH;
    case TWHRPNativeEvmos:
        return HRP_NATIVEEVMOS;
    case TWHRPStratis:
        return HRP_STRATIS;
    case TWHRPAgoric:
        return HRP_AGORIC;
    case TWHRPDydx:
        return HRP_DYDX;
    case TWHRPNativeInjective:
        return HRP_NATIVEINJECTIVE;
    case TWHRPNativeCanto:
        return HRP_NATIVECANTO;
    case TWHRPNativeZetaChain:
        return HRP_ZETACHAIN;
    case TWHRPPactus:
        return HRP_PACTUS;
    default: return nullptr;
    }
}

enum TWHRP hrpForString(const char *_Nonnull string) {
    if (std::strcmp(string, HRP_BITCOIN) == 0) {
        return TWHRPBitcoin;
    } else if (std::strcmp(string, HRP_LITECOIN) == 0) {
        return TWHRPLitecoin;
    } else if (std::strcmp(string, HRP_VIACOIN) == 0) {
        return TWHRPViacoin;
    } else if (std::strcmp(string, HRP_GROESTLCOIN) == 0) {
        return TWHRPGroestlcoin;
    } else if (std::strcmp(string, HRP_DIGIBYTE) == 0) {
        return TWHRPDigiByte;
    } else if (std::strcmp(string, HRP_MONACOIN) == 0) {
        return TWHRPMonacoin;
    } else if (std::strcmp(string, HRP_SYSCOIN) == 0) {
        return TWHRPSyscoin;
    } else if (std::strcmp(string, HRP_VERGE) == 0) {
        return TWHRPVerge;
    } else if (std::strcmp(string, HRP_COSMOS) == 0) {
        return TWHRPCosmos;
    } else if (std::strcmp(string, HRP_STARGAZE) == 0) {
        return TWHRPStargaze;
    } else if (std::strcmp(string, HRP_JUNO) == 0) {
        return TWHRPJuno;
    } else if (std::strcmp(string, HRP_STRIDE) == 0) {
        return TWHRPStride;
    } else if (std::strcmp(string, HRP_AXELAR) == 0) {
        return TWHRPAxelar;
    } else if (std::strcmp(string, HRP_CRESCENT) == 0) {
        return TWHRPCrescent;
    } else if (std::strcmp(string, HRP_KUJIRA) == 0) {
        return TWHRPKujira;
    } else if (std::strcmp(string, HRP_COMDEX) == 0) {
        return TWHRPComdex;
    } else if (std::strcmp(string, HRP_NEUTRON) == 0) {
        return TWHRPNeutron;
    } else if (std::strcmp(string, HRP_SOMMELIER) == 0) {
        return TWHRPSommelier;
    } else if (std::strcmp(string, HRP_FETCHAI) == 0) {
        return TWHRPFetchAI;
    } else if (std::strcmp(string, HRP_MARS) == 0) {
        return TWHRPMars;
    } else if (std::strcmp(string, HRP_UMEE) == 0) {
        return TWHRPUmee;
    } else if (std::strcmp(string, HRP_NOBLE) == 0) {
        return TWHRPNoble;
    } else if (std::strcmp(string, HRP_SEI) == 0) {
        return TWHRPSei;
    } else if (std::strcmp(string, HRP_TIA) == 0) {
        return TWHRPTia;
    } else if (std::strcmp(string, HRP_COREUM) == 0) {
        return TWHRPCoreum;
    } else if (std::strcmp(string, HRP_QUASAR) == 0) {
        return TWHRPQuasar;
    } else if (std::strcmp(string, HRP_PERSISTENCE) == 0) {
        return TWHRPPersistence;
    } else if (std::strcmp(string, HRP_AKASH) == 0) {
        return TWHRPAkash;
    } else if (std::strcmp(string, HRP_ZCASH) == 0) {
        return TWHRPZcash;
    } else if (std::strcmp(string, HRP_BITCOINCASH) == 0) {
        return TWHRPBitcoinCash;
    } else if (std::strcmp(string, HRP_BITCOINGOLD) == 0) {
        return TWHRPBitcoinGold;
    } else if (std::strcmp(string, HRP_IOTEX) == 0) {
        return TWHRPIoTeX;
    } else if (std::strcmp(string, HRP_NERVOS) == 0) {
        return TWHRPNervos;
    } else if (std::strcmp(string, HRP_ZILLIQA) == 0) {
        return TWHRPZilliqa;
    } else if (std::strcmp(string, HRP_TERRA) == 0) {
        return TWHRPTerra;
    } else if (std::strcmp(string, HRP_TERRAV2) == 0) {
        return TWHRPTerraV2;
    } else if (std::strcmp(string, HRP_KAVA) == 0) {
        return TWHRPKava;
    } else if (std::strcmp(string, HRP_BLUZELLE) == 0) {
        return TWHRPBluzelle;
    } else if (std::strcmp(string, HRP_BAND) == 0) {
        return TWHRPBandChain;
    } else if (std::strcmp(string, HRP_ELROND) == 0) {
        return TWHRPMultiversX;
    } else if (std::strcmp(string, HRP_BINANCE) == 0) {
        return TWHRPBinance;
    } else if (std::strcmp(string, HRP_TBINANCE) == 0) {
        return TWHRPTBinance;
    } else if (std::strcmp(string, HRP_BITCOINDIAMOND) == 0) {
        return TWHRPBitcoinDiamond;
    } else if (std::strcmp(string, HRP_HARMONY) == 0) {
        return TWHRPHarmony;
    } else if (std::strcmp(string, HRP_OASIS) == 0) {
        return TWHRPOasis;
    } else if (std::strcmp(string, HRP_CARDANO) == 0) {
        return TWHRPCardano;
    } else if (std::strcmp(string, HRP_QTUM) == 0) {
        return TWHRPQtum;
    } else if (std::strcmp(string, HRP_THORCHAIN) == 0) {
        return TWHRPTHORChain;
    } else if (std::strcmp(string, HRP_CRYPTOORG) == 0) {
        return TWHRPCryptoOrg;
    } else if (std::strcmp(string, HRP_SECRET) == 0) {
        return TWHRPSecret;
    } else if (std::strcmp(string, HRP_OSMOSIS) == 0) {
        return TWHRPOsmosis;
    } else if (std::strcmp(string, HRP_ECASH) == 0) {
        return TWHRPECash;
    } else if (std::strcmp(string, HRP_NATIVEEVMOS) == 0) {
        return TWHRPNativeEvmos;
    } else if (std::strcmp(string, HRP_STRATIS) == 0) {
        return TWHRPStratis;
    } else if (std::strcmp(string, HRP_AGORIC) == 0) {
        return TWHRPAgoric;
    } else if (std::strcmp(string, HRP_DYDX) == 0) {
        return TWHRPDydx;
    } else if (std::strcmp(string, HRP_NATIVEINJECTIVE) == 0) {
        return TWHRPNativeInjective;
    } else if (std::strcmp(string, HRP_NATIVECANTO) == 0) {
        return TWHRPNativeCanto;
    } else if (std::strcmp(string, HRP_ZETACHAIN) == 0) {
        return TWHRPNativeZetaChain;
    } else if (std::strcmp(string, HRP_PACTUS) == 0) {
        return TWHRPPactus;
    } else {
        return TWHRPUnknown;
    }
}