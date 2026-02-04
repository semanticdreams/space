#pragma once
#include <memory>
#include <string>
#include <string_view>

/*
  webbrowser.hpp — Python webbrowser-like module for C++
  Includes Python-equivalent file:// path normalization
*/

namespace webbrowser {

enum open_mode {
    same_window = 0,
    new_window  = 1,
    new_tab     = 2
};

class Browser {
public:
    virtual ~Browser() = default;
    virtual bool open(std::string_view url, open_mode mode = same_window, bool autoraise = true) = 0;
};

std::shared_ptr<Browser> default_browser();
Browser& get(const std::string& name = "");
void register_browser(const std::string& name, std::shared_ptr<Browser> browser);

bool open(std::string_view input, open_mode mode = same_window, bool autoraise = true);
bool open_new(std::string_view url);
bool open_new_tab(std::string_view url);

namespace detail {
std::string normalize_input(std::string_view input);
} // namespace detail

} // namespace webbrowser
