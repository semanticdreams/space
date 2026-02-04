#include "lua_wallet_core.h"

#include <memory>
#include <string>

#include <TrustWalletCore/TWAnySigner.h>
#include <TrustWalletCore/TWCoinType.h>
#include <TrustWalletCore/TWData.h>
#include <TrustWalletCore/TWHDWallet.h>
#include <TrustWalletCore/TWMnemonic.h>
#include <TrustWalletCore/TWPrivateKey.h>
#include <TrustWalletCore/TWString.h>

namespace {

struct TWStringHolder
{
    explicit TWStringHolder(const std::string& value)
        : handle(TWStringCreateWithUTF8Bytes(value.c_str()))
    {
    }

    ~TWStringHolder()
    {
        if (handle != nullptr) {
            TWStringDelete(handle);
        }
    }

    TWString* get() const { return handle; }

private:
    TWString* handle { nullptr };
};

std::string consume_tw_string(TWString* value)
{
    if (value == nullptr) {
        return {};
    }
    const char* bytes = TWStringUTF8Bytes(value);
    std::string output = bytes ? bytes : "";
    TWStringDelete(value);
    return output;
}

class HDWallet
{
public:
    explicit HDWallet(TWHDWallet* handle_ref)
        : handle(handle_ref)
    {
    }

    HDWallet(const HDWallet&) = delete;
    HDWallet& operator=(const HDWallet&) = delete;

    ~HDWallet()
    {
        drop();
    }

    void drop()
    {
        if (handle != nullptr) {
            TWHDWalletDelete(handle);
            handle = nullptr;
        }
    }

    bool is_closed() const { return handle == nullptr; }

    std::string mnemonic() const
    {
        ensure_open("mnemonic");
        return consume_tw_string(TWHDWalletMnemonic(handle));
    }

    std::string address_for_coin(uint32_t coin_type) const
    {
        ensure_open("address-for-coin");
        return consume_tw_string(TWHDWalletGetAddressForCoin(handle, static_cast<TWCoinType>(coin_type)));
    }

    std::string sign_json(uint32_t coin_type, const std::string& json) const
    {
        ensure_open("sign-json");
        TWCoinType coin = static_cast<TWCoinType>(coin_type);
        if (!TWAnySignerSupportsJSON(coin)) {
            throw sol::error("wallet-core.AnySigner does not support JSON for coin");
        }
        TWPrivateKey* key = TWHDWalletGetKeyForCoin(handle, coin);
        if (key == nullptr) {
            throw sol::error("wallet-core.HDWallet failed to derive key");
        }
        TWData* key_data = TWPrivateKeyData(key);
        TWStringHolder json_value(json);
        std::string output = consume_tw_string(TWAnySignerSignJSON(json_value.get(), key_data, coin));
        TWDataDelete(key_data);
        TWPrivateKeyDelete(key);
        return output;
    }

private:
    void ensure_open(const std::string& action) const
    {
        if (handle == nullptr) {
            throw sol::error("wallet-core.HDWallet is closed: " + action);
        }
    }

    TWHDWallet* handle { nullptr };
};

sol::table create_wallet_core_table(sol::state_view lua)
{
    sol::table wallet_core_table = lua.create_table();

    wallet_core_table.new_usertype<HDWallet>("HDWallet",
        sol::no_constructor,
        "mnemonic", &HDWallet::mnemonic,
        "address-for-coin", &HDWallet::address_for_coin,
        "sign-json", &HDWallet::sign_json,
        "drop", &HDWallet::drop,
        "is-closed", &HDWallet::is_closed);

    wallet_core_table.set_function("HDWallet", [](sol::table opts) {
        std::string mnemonic = opts.get_or<std::string>("mnemonic", "");
        if (mnemonic.empty()) {
            throw sol::error("wallet-core.HDWallet requires mnemonic");
        }
        std::string passphrase = opts.get_or<std::string>("passphrase", "");
        TWStringHolder mnemonic_value(mnemonic);
        TWStringHolder passphrase_value(passphrase);
        TWHDWallet* wallet = TWHDWalletCreateWithMnemonic(mnemonic_value.get(), passphrase_value.get());
        if (wallet == nullptr) {
            throw sol::error("wallet-core.HDWallet invalid mnemonic");
        }
        return std::make_shared<HDWallet>(wallet);
    });

    wallet_core_table.set_function("mnemonic-valid", [](const std::string& mnemonic) {
        TWStringHolder mnemonic_value(mnemonic);
        return TWMnemonicIsValid(mnemonic_value.get());
    });

    wallet_core_table.set_function("generate-mnemonic", [](sol::table opts) {
        sol::optional<int> strength_opt = opts["strength"];
        int strength = strength_opt.value_or(128);
        std::string passphrase = opts.get_or<std::string>("passphrase", "");
        TWStringHolder passphrase_value(passphrase);
        TWHDWallet* wallet = TWHDWalletCreate(strength, passphrase_value.get());
        if (wallet == nullptr) {
            throw sol::error("wallet-core.generate-mnemonic invalid strength");
        }
        std::string mnemonic = consume_tw_string(TWHDWalletMnemonic(wallet));
        TWHDWalletDelete(wallet);
        return mnemonic;
    });

    wallet_core_table.set_function("sign-json", [](sol::table opts) {
        std::string json = opts.get_or<std::string>("json", "");
        sol::optional<uint32_t> coin_opt = opts["coin"];
        std::string key_hex = opts.get_or<std::string>("key", "");
        if (json.empty()) {
            throw sol::error("wallet-core.sign-json requires json");
        }
        if (!coin_opt) {
            throw sol::error("wallet-core.sign-json requires coin");
        }
        if (key_hex.empty()) {
            throw sol::error("wallet-core.sign-json requires key");
        }
        TWStringHolder key_hex_value(key_hex);
        TWData* key_data = TWDataCreateWithHexString(key_hex_value.get());
        if (key_data == nullptr) {
            throw sol::error("wallet-core.sign-json invalid key");
        }
        TWCoinType coin = static_cast<TWCoinType>(*coin_opt);
        if (!TWAnySignerSupportsJSON(coin)) {
            TWDataDelete(key_data);
            throw sol::error("wallet-core.AnySigner does not support JSON for coin");
        }
        TWStringHolder json_value(json);
        std::string output = consume_tw_string(TWAnySignerSignJSON(json_value.get(), key_data, coin));
        TWDataDelete(key_data);
        return output;
    });

    wallet_core_table.set_function("supports-json", [](uint32_t coin_type) {
        return TWAnySignerSupportsJSON(static_cast<TWCoinType>(coin_type));
    });

    sol::table coin_types = lua.create_table();
    coin_types["bitcoin"] = static_cast<uint32_t>(TWCoinTypeBitcoin);
    coin_types["ethereum"] = static_cast<uint32_t>(TWCoinTypeEthereum);
    coin_types["arbitrum"] = static_cast<uint32_t>(TWCoinTypeArbitrum);
    coin_types["arbitrumnova"] = static_cast<uint32_t>(TWCoinTypeArbitrumNova);
    coin_types["solana"] = static_cast<uint32_t>(TWCoinTypeSolana);
    wallet_core_table["coin-types"] = coin_types;

    return wallet_core_table;
}

} // namespace

void lua_bind_wallet_core(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("wallet-core", [](sol::this_state state) {
        sol::state_view lua_state(state);
        return create_wallet_core_table(lua_state);
    });
}
