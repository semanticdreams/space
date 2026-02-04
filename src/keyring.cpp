#include "keyring.h"

#include <stdexcept>
#include <string>

#if defined(_WIN32)
#define NOMINMAX
#include <Windows.h>
#include <Wincred.h>
#elif defined(__APPLE__)
#include <Security/Security.h>
#elif defined(__linux__)
#include <libsecret/secret.h>
#endif

namespace {

void validate_inputs(const std::string& service, const std::string& account)
{
    if (service.empty()) {
        throw std::runtime_error("keyring requires a service name");
    }
    if (account.empty()) {
        throw std::runtime_error("keyring requires an account name");
    }
}

std::string make_label(const std::string& service, const std::string& account)
{
    return "space/" + service + "/" + account;
}

#if defined(_WIN32)
std::wstring to_wstring(const std::string& input)
{
    return std::wstring(input.begin(), input.end());
}

std::string windows_error(DWORD code)
{
    LPVOID buffer = nullptr;
    DWORD size = FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                                nullptr,
                                code,
                                MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                                reinterpret_cast<LPSTR>(&buffer),
                                0,
                                nullptr);
    std::string message;
    if (size != 0 && buffer != nullptr) {
        message.assign(static_cast<char*>(buffer), size);
        LocalFree(buffer);
        while (!message.empty() && (message.back() == '\r' || message.back() == '\n')) {
            message.pop_back();
        }
    } else {
        message = "Unknown error";
    }
    return message;
}
#elif defined(__linux__)
const SecretSchema* keyring_schema()
{
    static const SecretSchema schema = { "space-keyring",
                                         SECRET_SCHEMA_NONE,
                                         { { "service", SECRET_SCHEMA_ATTRIBUTE_STRING },
                                           { "account", SECRET_SCHEMA_ATTRIBUTE_STRING },
                                           { nullptr, SECRET_SCHEMA_ATTRIBUTE_STRING } } };
    return &schema;
}

std::string build_error(const char* prefix, GError* error)
{
    std::string msg(prefix);
    if (error != nullptr && error->message != nullptr) {
        msg += ": ";
        msg += error->message;
        g_error_free(error);
    }
    return msg;
}
#endif

} // namespace

bool Keyring::set_password(const std::string& service, const std::string& account, const std::string& secret)
{
    validate_inputs(service, account);

#if defined(_WIN32)
    std::string target = make_label(service, account);
    std::wstring target_w = to_wstring(target);
    std::wstring account_w = to_wstring(account);

    CREDENTIALW cred {};
    cred.Type = CRED_TYPE_GENERIC;
    cred.TargetName = const_cast<LPWSTR>(target_w.c_str());
    cred.UserName = const_cast<LPWSTR>(account_w.c_str());
    cred.CredentialBlobSize = static_cast<DWORD>(secret.size());
    cred.CredentialBlob = reinterpret_cast<LPBYTE>(const_cast<char*>(secret.data()));
    cred.Persist = CRED_PERSIST_LOCAL_MACHINE;

    if (!CredWriteW(&cred, 0)) {
        DWORD err = GetLastError();
        throw std::runtime_error("keyring set_password failed: " + windows_error(err));
    }
    return true;
#elif defined(__APPLE__)
    SecKeychainItemRef item = nullptr;
    OSStatus status = SecKeychainFindGenericPassword(nullptr,
                                                     static_cast<UInt32>(service.size()),
                                                     service.data(),
                                                     static_cast<UInt32>(account.size()),
                                                     account.data(),
                                                     nullptr,
                                                     nullptr,
                                                     &item);
    if (status == errSecSuccess && item != nullptr) {
        status = SecKeychainItemModifyAttributesAndData(item,
                                                        nullptr,
                                                        static_cast<UInt32>(secret.size()),
                                                        secret.data());
        CFRelease(item);
    } else if (status == errSecItemNotFound) {
        status = SecKeychainAddGenericPassword(nullptr,
                                               static_cast<UInt32>(service.size()),
                                               service.data(),
                                               static_cast<UInt32>(account.size()),
                                               account.data(),
                                               static_cast<UInt32>(secret.size()),
                                               secret.data(),
                                               nullptr);
    }

    if (status != errSecSuccess) {
        throw std::runtime_error("keyring set_password failed with status " + std::to_string(status));
    }
    return true;
#elif defined(__linux__)
    const SecretSchema* schema = keyring_schema();
    GError* error = nullptr;
    std::string label = make_label(service, account);
    gboolean ok = secret_password_store_sync(schema,
                                             SECRET_COLLECTION_DEFAULT,
                                             label.c_str(),
                                             secret.c_str(),
                                             nullptr,
                                             &error,
                                             "service",
                                             service.c_str(),
                                             "account",
                                             account.c_str(),
                                             nullptr);
    if (!ok) {
        throw std::runtime_error(build_error("keyring set_password failed", error));
    }
    return true;
#else
    (void)secret;
    throw std::runtime_error("keyring backend unsupported on this platform");
#endif
}

std::optional<std::string> Keyring::get_password(const std::string& service, const std::string& account)
{
    validate_inputs(service, account);

#if defined(_WIN32)
    std::string target = make_label(service, account);
    std::wstring target_w = to_wstring(target);
    PCREDENTIALW cred = nullptr;
    if (!CredReadW(target_w.c_str(), CRED_TYPE_GENERIC, 0, &cred)) {
        DWORD err = GetLastError();
        if (err == ERROR_NOT_FOUND) {
            return std::nullopt;
        }
        throw std::runtime_error("keyring get_password failed: " + windows_error(err));
    }
    std::string result;
    if (cred->CredentialBlob != nullptr && cred->CredentialBlobSize > 0) {
        result.assign(reinterpret_cast<const char*>(cred->CredentialBlob),
                      reinterpret_cast<const char*>(cred->CredentialBlob) + cred->CredentialBlobSize);
    }
    CredFree(cred);
    return result;
#elif defined(__APPLE__)
    void* data = nullptr;
    UInt32 length = 0;
    SecKeychainItemRef item = nullptr;
    OSStatus status = SecKeychainFindGenericPassword(nullptr,
                                                     static_cast<UInt32>(service.size()),
                                                     service.data(),
                                                     static_cast<UInt32>(account.size()),
                                                     account.data(),
                                                     &length,
                                                     &data,
                                                     &item);
    if (status == errSecItemNotFound) {
        return std::nullopt;
    }
    if (status != errSecSuccess) {
        throw std::runtime_error("keyring get_password failed with status " + std::to_string(status));
    }
    std::string result;
    if (data != nullptr && length > 0) {
        result.assign(static_cast<const char*>(data), static_cast<const char*>(data) + length);
    }
    SecKeychainItemFreeContent(nullptr, data);
    if (item != nullptr) {
        CFRelease(item);
    }
    return result;
#elif defined(__linux__)
    const SecretSchema* schema = keyring_schema();
    GError* error = nullptr;
    gchar* password = secret_password_lookup_sync(schema,
                                                  nullptr,
                                                  &error,
                                                  "service",
                                                  service.c_str(),
                                                  "account",
                                                  account.c_str(),
                                                  nullptr);
    if (error != nullptr) {
        throw std::runtime_error(build_error("keyring get_password failed", error));
    }
    if (password == nullptr) {
        return std::nullopt;
    }
    std::string result(password);
    secret_password_free(password);
    return result;
#else
    throw std::runtime_error("keyring backend unsupported on this platform");
#endif
}

bool Keyring::delete_password(const std::string& service, const std::string& account)
{
    validate_inputs(service, account);

#if defined(_WIN32)
    std::string target = make_label(service, account);
    std::wstring target_w = to_wstring(target);
    if (CredDeleteW(target_w.c_str(), CRED_TYPE_GENERIC, 0)) {
        return true;
    }
    DWORD err = GetLastError();
    if (err == ERROR_NOT_FOUND) {
        return false;
    }
    throw std::runtime_error("keyring delete_password failed: " + windows_error(err));
#elif defined(__APPLE__)
    SecKeychainItemRef item = nullptr;
    OSStatus status = SecKeychainFindGenericPassword(nullptr,
                                                     static_cast<UInt32>(service.size()),
                                                     service.data(),
                                                     static_cast<UInt32>(account.size()),
                                                     account.data(),
                                                     nullptr,
                                                     nullptr,
                                                     &item);
    if (status == errSecItemNotFound) {
        return false;
    }
    if (status != errSecSuccess) {
        throw std::runtime_error("keyring delete_password failed with status " + std::to_string(status));
    }
    OSStatus delete_status = SecKeychainItemDelete(item);
    CFRelease(item);
    if (delete_status == errSecSuccess) {
        return true;
    }
    throw std::runtime_error("keyring delete_password failed with status " + std::to_string(delete_status));
#elif defined(__linux__)
    const SecretSchema* schema = keyring_schema();
    GError* error = nullptr;
    gboolean cleared = secret_password_clear_sync(schema,
                                                  nullptr,
                                                  &error,
                                                  "service",
                                                  service.c_str(),
                                                  "account",
                                                  account.c_str(),
                                                  nullptr);
    if (error != nullptr) {
        if (error->domain == SECRET_ERROR && error->code == SECRET_ERROR_NO_SUCH_OBJECT) {
            g_error_free(error);
            return false;
        }
        throw std::runtime_error(build_error("keyring delete_password failed", error));
    }
    return cleared;
#else
    throw std::runtime_error("keyring backend unsupported on this platform");
#endif
}
