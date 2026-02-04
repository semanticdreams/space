#include "terminal.h"

#include <vterm.h>

#include <algorithm>
#include <cerrno>
#include <cctype>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <optional>
#include <chrono>
#include <pty.h>
#include <stdexcept>
#include <string>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <utmp.h>
#include <unistd.h>
#include <vector>
#include <deque>
#include <limits>

namespace {

std::string trim_copy(const std::string& value)
{
    std::string result = value;
    result.erase(result.begin(),
        std::find_if(result.begin(), result.end(), [](unsigned char ch) { return !std::isspace(ch); }));
    result.erase(std::find_if(result.rbegin(), result.rend(), [](unsigned char ch) { return !std::isspace(ch); }).base(),
        result.end());
    return result;
}

std::vector<std::string> split_command(const std::string& value)
{
    std::vector<std::string> parts;
    std::string current;
    bool inWord = false;
    for (char ch : value) {
        if (std::isspace(static_cast<unsigned char>(ch))) {
            if (inWord) {
                parts.push_back(current);
                current.clear();
                inWord = false;
            }
        } else {
            current.push_back(ch);
            inWord = true;
        }
    }
    if (!current.empty()) {
        parts.push_back(current);
    }
    return parts;
}

} // namespace

struct Terminal::Impl {
    Terminal& owner;
    VTerm* vt = nullptr;
    VTermScreen* screen = nullptr;
    VTermState* state = nullptr;
    int ptyMaster = -1;
    pid_t childPid = -1;
    Size size;
    Cursor cursor;
    std::optional<std::string> title;
    std::string titleBuffer;
    bool screenChanged = false;
    bool ptyAvailable = false;
    std::deque<std::vector<VTermScreenCell>> scrollback;
    int scrollbackLineLimit = 8000;
    size_t scrollbackByteLimit = 16 * 1024 * 1024;
    size_t scrollbackBytes = 0;
    bool inAltScreen = false;
    struct DirtyRow {
        bool dirty = false;
        int left = 0;
        int right = 0;
    };
    std::vector<DirtyRow> dirtyRows;

    explicit Impl(Terminal& ownerRef, int rows, int cols)
        : owner(ownerRef)
    {
        size.rows = rows;
        size.cols = cols;
        cursor.row = 0;
        cursor.col = 0;
        cursor.visible = true;
        cursor.blinking = false;

        vt = vterm_new(rows, cols);
        if (!vt) {
            throw std::runtime_error("Failed to create vterm instance");
        }
        state = vterm_obtain_state(vt);
        screen = vterm_obtain_screen(vt);
        vterm_set_utf8(vt, 1);
        vterm_output_set_callback(vt, &Impl::handleOutput, this);

        static const VTermScreenCallbacks callbacks = {
            &Impl::handleDamage,
            &Impl::handleMoveRect,
            &Impl::handleMoveCursor,
            &Impl::handleSetTermProp,
            &Impl::handleBell,
            &Impl::handleResize,
            &Impl::handleScrollbackPushLine,
            &Impl::handleScrollbackPopLine,
            &Impl::handleScrollbackClear};

        vterm_screen_set_callbacks(screen, &callbacks, this);
        vterm_screen_set_damage_merge(screen, VTERM_DAMAGE_ROW);
        vterm_screen_enable_altscreen(screen, 1);
        vterm_screen_reset(screen, 1);
        vterm_screen_flush_damage(screen);
        resetDirty();

        try {
            openPtyAndSpawn();
            ptyAvailable = true;
        } catch (const std::exception&) {
            // If the environment cannot open a PTY (e.g., restricted sandbox), keep the virtual
            // terminal alive without a backing child so the UI tests can still exercise layout.
            ptyAvailable = false;
        }
    }

    ~Impl()
    {
        if (ptyMaster >= 0) {
            close(ptyMaster);
        }
        if (childPid > 0) {
            kill(childPid, SIGHUP);
            int status = 0;
            waitpid(childPid, &status, WNOHANG);
        }
        if (vt) {
            vterm_free(vt);
        }
    }

    static Terminal::Rect toRect(const VTermRect& rect)
    {
        return {rect.start_row, rect.start_col, rect.end_row - 1, rect.end_col - 1};
    }

    static uint32_t firstCodepoint(const VTermScreenCell& cell)
    {
        if (cell.chars[0] != 0) {
            return cell.chars[0];
        }
        return U' ';
    }

    Terminal::Cell toCell(const VTermScreenCell& cell) const
    {
        Terminal::Cell out;
        out.codepoint = firstCodepoint(cell);
        out.bold = cell.attrs.bold;
        out.underline = cell.attrs.underline != VTERM_UNDERLINE_OFF;
        out.italic = cell.attrs.italic;
        out.reverse = cell.attrs.reverse;

        VTermColor fg = cell.fg;
        VTermColor bg = cell.bg;
        vterm_screen_convert_color_to_rgb(screen, &fg);
        vterm_screen_convert_color_to_rgb(screen, &bg);
        out.fg_r = fg.rgb.red;
        out.fg_g = fg.rgb.green;
        out.fg_b = fg.rgb.blue;
        out.bg_r = bg.rgb.red;
        out.bg_g = bg.rgb.green;
        out.bg_b = bg.rgb.blue;

        return out;
    }

    size_t lineByteCost(const std::vector<VTermScreenCell>& line) const
    {
        return line.size() * sizeof(VTermScreenCell);
    }

    void trimScrollback()
    {
        while (!scrollback.empty()
            && (static_cast<int>(scrollback.size()) > scrollbackLineLimit || scrollbackBytes > scrollbackByteLimit)) {
            scrollbackBytes -= lineByteCost(scrollback.front());
            scrollback.pop_front();
        }
    }

    void pushScrollbackLine(int cols, const VTermScreenCell* cells)
    {
        if (inAltScreen || cols <= 0 || cells == nullptr) {
            return;
        }
        std::vector<VTermScreenCell> line;
        line.reserve(static_cast<size_t>(cols));
        for (int i = 0; i < cols; ++i) {
            line.push_back(cells[i]);
        }
        scrollbackBytes += lineByteCost(line);
        scrollback.push_back(std::move(line));
        trimScrollback();
    }

    int popScrollbackLine(int cols, VTermScreenCell* cells)
    {
        if (inAltScreen || cols <= 0 || cells == nullptr || scrollback.empty()) {
            return 0;
        }
        std::vector<VTermScreenCell> line = std::move(scrollback.back());
        scrollback.pop_back();
        scrollbackBytes -= lineByteCost(line);
        int copyCols = std::min(cols, static_cast<int>(line.size()));
        for (int i = 0; i < copyCols; ++i) {
            cells[i] = line[static_cast<size_t>(i)];
        }
        return 1;
    }

    void clearScrollback()
    {
        scrollback.clear();
        scrollbackBytes = 0;
    }

    std::vector<Terminal::Cell> scrollbackLineToCells(int index) const
    {
        if (index < 0 || index >= static_cast<int>(scrollback.size())) {
            throw std::out_of_range("Scrollback index outside bounds");
        }
        const std::vector<VTermScreenCell>& line = scrollback[static_cast<size_t>(index)];
        std::vector<Terminal::Cell> out;
        out.reserve(line.size());
        for (const auto& cell : line) {
            out.push_back(toCell(cell));
        }
        return out;
    }

    Terminal::Cell readCell(int row, int col) const
    {
        VTermPos pos{row, col};
        VTermScreenCell cell{};
        if (!vterm_screen_get_cell(screen, pos, &cell)) {
            throw std::out_of_range("Cell coordinates outside terminal bounds");
        }
        return toCell(cell);
    }

    void resetDirty()
    {
        dirtyRows.assign(static_cast<size_t>(std::max(size.rows, 0)), DirtyRow{});
        screenChanged = false;
    }

    void markDamage(const Rect& region)
    {
        if (size.rows <= 0 || size.cols <= 0) {
            return;
        }
        int top = std::max(0, std::min(region.top, size.rows - 1));
        int bottom = std::max(0, std::min(region.bottom, size.rows - 1));
        int left = std::max(0, std::min(region.left, size.cols - 1));
        int right = std::max(0, std::min(region.right, size.cols - 1));
        if (top > bottom || left > right) {
            return;
        }
        if (dirtyRows.size() != static_cast<size_t>(size.rows)) {
            dirtyRows.assign(static_cast<size_t>(size.rows), DirtyRow{});
        }
        for (int row = top; row <= bottom; ++row) {
            DirtyRow& dr = dirtyRows[static_cast<size_t>(row)];
            if (!dr.dirty) {
                dr.dirty = true;
                dr.left = left;
                dr.right = right;
            } else {
                dr.left = std::min(dr.left, left);
                dr.right = std::max(dr.right, right);
            }
        }
        screenChanged = true;
    }

    std::vector<Rect> collectDirtyRegions()
    {
        std::vector<Rect> regions;
        if (dirtyRows.empty()) {
            return regions;
        }
        Rect current{0, 0, -1, 0};
        bool hasCurrent = false;
        for (int row = 0; row < size.rows; ++row) {
            const DirtyRow& dr = dirtyRows[static_cast<size_t>(row)];
            if (!dr.dirty) {
                continue;
            }
            Rect candidate{row, dr.left, row, dr.right};
            if (hasCurrent && candidate.left == current.left && candidate.right == current.right
                && candidate.top == current.bottom + 1) {
                current.bottom = candidate.bottom;
            } else {
                if (hasCurrent) {
                    regions.push_back(current);
                }
                current = candidate;
                hasCurrent = true;
            }
        }
        if (hasCurrent) {
            regions.push_back(current);
        }
        return regions;
    }

    void flushDamage()
    {
        vterm_screen_flush_damage(screen);
        if (screenChanged && owner.onScreenUpdated) {
            owner.onScreenUpdated();
        }
        screenChanged = false;
    }

    void drainPty()
    {
        if (ptyMaster < 0 || !ptyAvailable) {
            return;
        }
        // Avoid spinning forever when a child floods stdout (e.g., `yes`).
        constexpr size_t kMaxBytesPerDrain = 64 * 1024;
        constexpr int kMaxReadIterations = 128;
        constexpr auto kMaxDrainDuration = std::chrono::milliseconds(2);
        const auto start = std::chrono::steady_clock::now();
        size_t drainedBytes = 0;
        int iterations = 0;
        char buffer[4096];
        while (drainedBytes < kMaxBytesPerDrain && iterations < kMaxReadIterations) {
            ssize_t nread = ::read(ptyMaster, buffer, sizeof(buffer));
            if (nread > 0) {
                vterm_input_write(vt, buffer, static_cast<size_t>(nread));
                drainedBytes += static_cast<size_t>(nread);
                ++iterations;
                if (drainedBytes >= kMaxBytesPerDrain) {
                    break;
                }
                if (iterations >= kMaxReadIterations) {
                    break;
                }
                const auto elapsed = std::chrono::steady_clock::now() - start;
                if (elapsed >= kMaxDrainDuration) {
                    break;
                }
                continue;
            }
            if (nread == 0) {
                break;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                break;
            }
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        flushDamage();
        if (childPid > 0) {
            int status = 0;
            if (waitpid(childPid, &status, WNOHANG) > 0) {
                childPid = -1;
            }
        }
    }

    void openPtyAndSpawn()
    {
        int masterFd = -1;
        int slaveFd = -1;
        if (openpty(&masterFd, &slaveFd, nullptr, nullptr, nullptr) == -1) {
            throw std::runtime_error("Failed to open pty");
        }

        pid_t pid = fork();
        if (pid == -1) {
            close(masterFd);
            close(slaveFd);
            throw std::runtime_error("Failed to fork for terminal");
        }

        if (pid == 0) {
            close(masterFd);
            setsid();
            if (ioctl(slaveFd, TIOCSCTTY, 0) == -1) {
                _exit(1);
            }
            dup2(slaveFd, STDIN_FILENO);
            dup2(slaveFd, STDOUT_FILENO);
            dup2(slaveFd, STDERR_FILENO);
            if (slaveFd > STDERR_FILENO) {
                close(slaveFd);
            }

            setenv("TERM", "xterm-256color", 1);

            // Default to bash so line editing/history keys (arrows, etc.) work out of the box.
            std::string cmd = "/bin/bash";
            const char* envCmd = std::getenv("SPACE_TERMINAL_PROGRAM");
            if (envCmd) {
                std::string fromEnv = trim_copy(envCmd);
                if (!fromEnv.empty()) {
                    cmd = fromEnv;
                }
            }

            std::vector<std::string> parts = split_command(cmd);
            if (parts.empty()) {
                parts.push_back("/bin/sh");
            }

            std::vector<char*> argv;
            for (auto& part : parts) {
                argv.push_back(part.data());
            }
            argv.push_back(nullptr);
            execvp(argv[0], argv.data());
            _exit(127);
        }

        close(slaveFd);
        ptyMaster = masterFd;
        childPid = pid;

        int flags = fcntl(ptyMaster, F_GETFL, 0);
        fcntl(ptyMaster, F_SETFL, flags | O_NONBLOCK);

        struct winsize ws {
        };
        ws.ws_row = static_cast<unsigned short>(size.rows);
        ws.ws_col = static_cast<unsigned short>(size.cols);
        ioctl(ptyMaster, TIOCSWINSZ, &ws);
    }

    void writeToPty(const std::string& bytes)
    {
        if (ptyMaster < 0 || !ptyAvailable) {
            return;
        }
        const char* data = bytes.data();
        size_t remaining = bytes.size();
        while (remaining > 0) {
            ssize_t written = ::write(ptyMaster, data, remaining);
            if (written > 0) {
                remaining -= static_cast<size_t>(written);
                data += written;
                continue;
            }
            if (written == -1 && errno == EINTR) {
                continue;
            }
            if (written == -1 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                break;
            }
            break;
        }
    }

    static void handleOutput(const char* s, size_t len, void* user)
    {
        Impl* impl = static_cast<Impl*>(user);
        impl->writeToPty(std::string(s, len));
    }

    static int handleDamage(VTermRect rect, void* user)
    {
        Impl* impl = static_cast<Impl*>(user);
        impl->markDamage(toRect(rect));
        return 1;
    }

    static int handleMoveRect(VTermRect dest, VTermRect /*src*/, void* user)
    {
        Impl* impl = static_cast<Impl*>(user);
        impl->markDamage(toRect(dest));
        return 1;
    }

    static int handleMoveCursor(VTermPos pos, VTermPos /*oldpos*/, int visible, void* user)
    {
        Impl* impl = static_cast<Impl*>(user);
        impl->cursor.row = pos.row;
        impl->cursor.col = pos.col;
        impl->cursor.visible = visible != 0;
        if (impl->owner.onCursorMoved) {
            impl->owner.onCursorMoved(pos.row, pos.col);
        }
        return 1;
    }

    static int handleSetTermProp(VTermProp prop, VTermValue* val, void* user)
    {
        Impl* impl = static_cast<Impl*>(user);
        if (prop == VTERM_PROP_TITLE) {
            if (val->string.initial) {
                impl->titleBuffer.clear();
            }
            impl->titleBuffer.append(val->string.str, val->string.len);
            if (val->string.final) {
                impl->title = impl->titleBuffer;
                if (impl->owner.onTitleChanged) {
                    impl->owner.onTitleChanged(*impl->title);
                }
            }
        } else if (prop == VTERM_PROP_ALTSCREEN) {
            impl->inAltScreen = val->boolean != 0;
            int rows = std::max(impl->size.rows, 1);
            int cols = std::max(impl->size.cols, 1);
            impl->markDamage(Rect{0, 0, rows - 1, cols - 1});
        }
        return 1;
    }

    static int handleBell(void* user)
    {
        Impl* impl = static_cast<Impl*>(user);
        if (impl->owner.onBell) {
            impl->owner.onBell();
        }
        return 1;
    }

    static int handleResize(int rows, int cols, void* user)
    {
        Impl* impl = static_cast<Impl*>(user);
        impl->size.rows = rows;
        impl->size.cols = cols;
        impl->resetDirty();
        impl->markDamage(Rect{0, 0, rows - 1, cols - 1});
        return 1;
    }

    static int handleScrollbackPushLine(int cols, const VTermScreenCell* cells, void* user)
    {
        Impl* impl = static_cast<Impl*>(user);
        impl->pushScrollbackLine(cols, cells);
        return 1;
    }

    static int handleScrollbackPopLine(int cols, VTermScreenCell* cells, void* user)
    {
        Impl* impl = static_cast<Impl*>(user);
        return impl->popScrollbackLine(cols, cells);
    }

    static int handleScrollbackClear(void* user)
    {
        Impl* impl = static_cast<Impl*>(user);
        impl->clearScrollback();
        return 1;
    }
};

Terminal::Terminal(int rows, int cols)
    : impl(new Impl(*this, rows, cols))
{
}

Terminal::~Terminal()
{
    delete impl;
}

std::vector<Terminal::Cell> Terminal::getRow(int row) const
{
    if (row < 0 || row >= impl->size.rows) {
        throw std::out_of_range("Row outside terminal bounds");
    }
    std::vector<Cell> result;
    result.reserve(static_cast<size_t>(impl->size.cols));
    for (int col = 0; col < impl->size.cols; ++col) {
        result.push_back(impl->readCell(row, col));
    }
    return result;
}

Terminal::Cell Terminal::getCell(int row, int col) const
{
    if (row < 0 || row >= impl->size.rows || col < 0 || col >= impl->size.cols) {
        throw std::out_of_range("Cell outside terminal bounds");
    }
    return impl->readCell(row, col);
}

std::vector<std::vector<Terminal::Cell>> Terminal::getScreen() const
{
    std::vector<std::vector<Cell>> rows;
    rows.reserve(static_cast<size_t>(impl->size.rows));
    for (int r = 0; r < impl->size.rows; ++r) {
        rows.push_back(getRow(r));
    }
    return rows;
}

std::vector<Terminal::Rect> Terminal::getDirtyRegions() const
{
    return impl->collectDirtyRegions();
}

void Terminal::clearDirtyRegions()
{
    impl->resetDirty();
}

Terminal::Size Terminal::getSize() const
{
    return impl->size;
}

Terminal::Cursor Terminal::getCursor() const
{
    return impl->cursor;
}

std::optional<std::string> Terminal::getTitle() const
{
    return impl->title;
}

bool Terminal::isAltScreen() const
{
    return impl->inAltScreen;
}

bool Terminal::isPtyAvailable() const
{
    return impl->ptyAvailable;
}

int Terminal::getScrollbackSize() const
{
    return static_cast<int>(impl->scrollback.size());
}

std::vector<Terminal::Cell> Terminal::getScrollbackLine(int index) const
{
    return impl->scrollbackLineToCells(index);
}

void Terminal::sendText(const std::string& utf8)
{
    impl->writeToPty(utf8);
}

namespace {

std::string to_lower_copy(const std::string& value)
{
    std::string out = value;
    std::transform(out.begin(), out.end(), out.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return out;
}

std::optional<VTermKey> map_key(const std::string& name)
{
    std::string key = to_lower_copy(name);
    if (key == "enter" || key == "return") {
        return VTERM_KEY_ENTER;
    }
    if (key == "backspace" || key == "bs") {
        return VTERM_KEY_BACKSPACE;
    }
    if (key == "tab") {
        return VTERM_KEY_TAB;
    }
    if (key == "escape" || key == "esc") {
        return VTERM_KEY_ESCAPE;
    }
    if (key == "up") {
        return VTERM_KEY_UP;
    }
    if (key == "down") {
        return VTERM_KEY_DOWN;
    }
    if (key == "left") {
        return VTERM_KEY_LEFT;
    }
    if (key == "right") {
        return VTERM_KEY_RIGHT;
    }
    if (key == "home") {
        return VTERM_KEY_HOME;
    }
    if (key == "end") {
        return VTERM_KEY_END;
    }
    if (key == "insert") {
        return VTERM_KEY_INS;
    }
    if (key == "delete" || key == "del") {
        return VTERM_KEY_DEL;
    }
    if (key == "pageup" || key == "page_up" || key == "pgup") {
        return VTERM_KEY_PAGEUP;
    }
    if (key == "pagedown" || key == "page_down" || key == "pgdown" || key == "pgdn") {
        return VTERM_KEY_PAGEDOWN;
    }
    if (!key.empty() && key[0] == 'f' && key.size() <= 3) {
        int idx = 0;
        try {
            idx = std::stoi(key.substr(1));
        } catch (...) {
            idx = 0;
        }
        if (idx > 0 && idx <= 24) {
            return static_cast<VTermKey>(VTERM_KEY_FUNCTION(idx));
        }
    }
    return std::nullopt;
}

} // namespace

void Terminal::sendKey(const std::string& keyName)
{
    std::optional<VTermKey> maybeKey = map_key(keyName);
    if (maybeKey.has_value()) {
        vterm_keyboard_key(impl->vt, maybeKey.value(), VTERM_MOD_NONE);
        impl->flushDamage();
        return;
    }

    if (!keyName.empty()) {
        unsigned char ch = static_cast<unsigned char>(keyName[0]);
        vterm_keyboard_unichar(impl->vt, ch, VTERM_MOD_NONE);
        impl->flushDamage();
    }
}

void Terminal::sendMouse(int row, int col, int button, bool pressed)
{
    vterm_mouse_move(impl->vt, row, col, VTERM_MOD_NONE);
    vterm_mouse_button(impl->vt, button, pressed, VTERM_MOD_NONE);
    impl->flushDamage();
}

void Terminal::resize(int rows, int cols)
{
    impl->size.rows = rows;
    impl->size.cols = cols;
    vterm_set_size(impl->vt, rows, cols);
    if (impl->ptyMaster >= 0) {
        struct winsize ws {
        };
        ws.ws_row = static_cast<unsigned short>(rows);
        ws.ws_col = static_cast<unsigned short>(cols);
        ioctl(impl->ptyMaster, TIOCSWINSZ, &ws);
    }
    impl->flushDamage();
}

void Terminal::setScrollbackLimit(int lines)
{
    impl->scrollbackLineLimit = std::max(0, lines);
    impl->trimScrollback();
}

void Terminal::injectOutput(const std::string& utf8)
{
    vterm_input_write(impl->vt, utf8.data(), utf8.size());
    impl->flushDamage();
}

void Terminal::update()
{
    impl->drainPty();
}
