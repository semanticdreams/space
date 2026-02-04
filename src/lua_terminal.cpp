#include <sol/sol.hpp>

#include <memory>
#include <optional>

#include "terminal.h"

namespace {

sol::table create_terminal_table(sol::state_view lua)
{
    sol::table terminal_table = lua.create_table();
    terminal_table.new_usertype<Terminal::Cell>("TerminalCell",
        "codepoint", &Terminal::Cell::codepoint,
        "fg-r", &Terminal::Cell::fg_r,
        "fg-g", &Terminal::Cell::fg_g,
        "fg-b", &Terminal::Cell::fg_b,
        "bg-r", &Terminal::Cell::bg_r,
        "bg-g", &Terminal::Cell::bg_g,
        "bg-b", &Terminal::Cell::bg_b,
        "bold", &Terminal::Cell::bold,
        "underline", &Terminal::Cell::underline,
        "italic", &Terminal::Cell::italic,
        "reverse", &Terminal::Cell::reverse);

    terminal_table.new_usertype<Terminal::Rect>("TerminalRect",
        "top", &Terminal::Rect::top,
        "left", &Terminal::Rect::left,
        "bottom", &Terminal::Rect::bottom,
        "right", &Terminal::Rect::right);

    terminal_table.new_usertype<Terminal::Size>("TerminalSize",
        "rows", &Terminal::Size::rows,
        "cols", &Terminal::Size::cols);

    terminal_table.new_usertype<Terminal::Cursor>("TerminalCursor",
        "row", &Terminal::Cursor::row,
        "col", &Terminal::Cursor::col,
        "visible", &Terminal::Cursor::visible,
        "blinking", &Terminal::Cursor::blinking);

    sol::usertype<Terminal> terminal_type = terminal_table.new_usertype<Terminal>("Terminal",
        sol::no_constructor);

    terminal_type.set_function("get-row", &Terminal::getRow);
    terminal_type.set_function("get-cell", &Terminal::getCell);
    terminal_type.set_function("get-screen", &Terminal::getScreen);
    terminal_type.set_function("get-dirty-regions", &Terminal::getDirtyRegions);
    terminal_type.set_function("clear-dirty-regions", &Terminal::clearDirtyRegions);
    terminal_type.set_function("get-size", &Terminal::getSize);
    terminal_type.set_function("get-cursor", &Terminal::getCursor);
    terminal_type.set_function("get-title", [](Terminal& self) -> sol::optional<std::string> {
        std::optional<std::string> title = self.getTitle();
        if (title.has_value()) {
            return title.value();
        }
        return sol::nullopt;
    });
    terminal_type.set_function("is-alt-screen", &Terminal::isAltScreen);
    terminal_type.set_function("is-pty-available", &Terminal::isPtyAvailable);
    terminal_type.set_function("get-scrollback-size", &Terminal::getScrollbackSize);
    terminal_type.set_function("get-scrollback-line", &Terminal::getScrollbackLine);
    terminal_type.set_function("send-text", &Terminal::sendText);
    terminal_type.set_function("send-key", &Terminal::sendKey);
    terminal_type.set_function("send-mouse", &Terminal::sendMouse);
    terminal_type.set_function("resize", &Terminal::resize);
    terminal_type.set_function("set-scrollback-limit", &Terminal::setScrollbackLimit);
    terminal_type.set_function("inject-output", &Terminal::injectOutput);
    terminal_type.set_function("update", &Terminal::update);
    terminal_type["on-screen-updated"] = &Terminal::onScreenUpdated;
    terminal_type["on-cursor-moved"] = &Terminal::onCursorMoved;
    terminal_type["on-title-changed"] = &Terminal::onTitleChanged;
    terminal_type["on-bell"] = &Terminal::onBell;

    terminal_table.set_function("Terminal", [](int rows, int cols) {
        return std::make_unique<Terminal>(rows, cols);
    });
    return terminal_table;
}

} // namespace

void lua_bind_terminal(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("terminal", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_terminal_table(lua);
    });
}
