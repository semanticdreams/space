#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <map>
#include <memory>
#include <string>
#include <string_view>
#include <utility>

#include "webbrowser.hpp"

#if defined(_WIN32)

#define NOMINMAX
#include <shellapi.h>
#include <windows.h>

#elif defined(__APPLE__)

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>

#else

#include <sys/wait.h>
#include <unistd.h>

#endif

namespace webbrowser {
namespace detail {
namespace {

bool has_control_chars(std::string_view s)
{
    for (unsigned char c : s) {
        if (c < 0x20 || c == 0x7F) {
            return true;
        }
    }
    return false;
}

bool has_scheme(std::string_view s)
{
    if (s.empty() || !std::isalpha(static_cast<unsigned char>(s[0]))) {
        return false;
    }
    for (char c : s) {
        if (c == ':') {
            return true;
        }
        if (!(std::isalnum(static_cast<unsigned char>(c)) || c == '+' || c == '-' || c == '.')) {
            return false;
        }
    }
    return false;
}

bool looks_like_path(std::string_view s)
{
#ifdef _WIN32
    if (s.size() >= 2 && std::isalpha(static_cast<unsigned char>(s[0])) && s[1] == ':') {
        return true;
    }
#endif
    return s.rfind("/", 0) == 0 || s.rfind("./", 0) == 0 || s.rfind("../", 0) == 0;
}

std::string percent_encode_path(std::string_view p)
{
    static const char hex[] = "0123456789ABCDEF";
    std::string out;
    for (unsigned char c : p) {
        if (std::isalnum(c) || c == '/' || c == '-' || c == '_' || c == '.' || c == '~') {
            out.push_back(static_cast<char>(c));
        } else {
            out.push_back('%');
            out.push_back(hex[c >> 4]);
            out.push_back(hex[c & 0xF]);
        }
    }
    return out;
}

std::string file_url_from_path(const std::filesystem::path& p)
{
    std::filesystem::path abs = std::filesystem::absolute(p).lexically_normal();
    std::string s = abs.generic_string();

#ifdef _WIN32
    return "file:///" + percent_encode_path(s);
#else
    return "file://" + percent_encode_path(s);
#endif
}

} // namespace

std::string normalize_input(std::string_view input)
{
    if (has_control_chars(input)) {
        return {};
    }

    if (has_scheme(input)) {
        return std::string(input);
    }

    if (input.rfind("www.", 0) == 0) {
        return "https://" + std::string(input);
    }

    if (looks_like_path(input)) {
        return file_url_from_path(std::filesystem::path(input));
    }

    return std::string(input);
}

} // namespace detail

namespace {

std::map<std::string, std::shared_ptr<Browser>>& registry()
{
    static std::map<std::string, std::shared_ptr<Browser>> r;
    return r;
}

#if defined(_WIN32)

class DefaultBrowser : public Browser {
public:
    bool open(std::string_view url, open_mode mode, bool autoraise) override
    {
        (void)mode;
        (void)autoraise;

        std::wstring wurl;
        int len = MultiByteToWideChar(CP_UTF8, 0, url.data(), static_cast<int>(url.size()), nullptr, 0);
        if (len <= 0) {
            return false;
        }
        wurl.resize(static_cast<std::size_t>(len));
        MultiByteToWideChar(CP_UTF8, 0, url.data(), static_cast<int>(url.size()), wurl.data(), len);

        auto r = ShellExecuteW(nullptr, L"open", wurl.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
        return reinterpret_cast<intptr_t>(r) > 32;
    }
};

#elif defined(__APPLE__)

class DefaultBrowser : public Browser {
public:
    bool open(std::string_view url, open_mode mode, bool autoraise) override
    {
        (void)mode;
        (void)autoraise;

        CFStringRef s = CFStringCreateWithBytes(
            nullptr,
            reinterpret_cast<const UInt8*>(url.data()),
            static_cast<CFIndex>(url.size()),
            kCFStringEncodingUTF8,
            false);
        if (!s) {
            return false;
        }

        CFURLRef cfurl = CFURLCreateWithString(nullptr, s, nullptr);
        CFRelease(s);
        if (!cfurl) {
            return false;
        }

        OSStatus st = LSOpenCFURLRef(cfurl, nullptr);
        CFRelease(cfurl);
        return st == noErr;
    }
};

#else

class DefaultBrowser : public Browser {
public:
    bool open(std::string_view url, open_mode mode, bool autoraise) override
    {
        (void)mode;
        (void)autoraise;

        std::string url_str(url);
        pid_t pid = fork();
        if (pid == 0) {
            execlp("xdg-open", "xdg-open", url_str.c_str(), nullptr);
            execlp("gio", "gio", "open", url_str.c_str(), nullptr);
            execlp("sensible-browser", "sensible-browser", url_str.c_str(), nullptr);
            _exit(127);
        }
        if (pid < 0) {
            return false;
        }
        int st = 0;
        if (waitpid(pid, &st, 0) < 0) {
            return false;
        }
        return WIFEXITED(st) && WEXITSTATUS(st) == 0;
    }
};

#endif

} // namespace

std::shared_ptr<Browser> default_browser()
{
    static auto b = std::make_shared<DefaultBrowser>();
    return b;
}

Browser& get(const std::string& name)
{
    if (!name.empty()) {
        auto it = registry().find(name);
        if (it != registry().end()) {
            return *it->second;
        }
    }

    if (const char* env = std::getenv("BROWSER")) {
        auto it = registry().find(env);
        if (it != registry().end()) {
            return *it->second;
        }
    }

    return *default_browser();
}

void register_browser(const std::string& name, std::shared_ptr<Browser> browser)
{
    registry()[name] = std::move(browser);
}

bool open(std::string_view input, open_mode mode, bool autoraise)
{
    std::string url = detail::normalize_input(input);
    if (url.empty()) {
        return false;
    }
    return get().open(url, mode, autoraise);
}

bool open_new(std::string_view url)
{
    return open(url, new_window);
}

bool open_new_tab(std::string_view url)
{
    return open(url, new_tab);
}

} // namespace webbrowser
