#pragma once

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <vector>
#include <deque>

class Terminal
{
public:
    struct Cell {
        uint32_t codepoint = U' ';
        uint8_t fg_r = 255;
        uint8_t fg_g = 255;
        uint8_t fg_b = 255;
        uint8_t bg_r = 0;
        uint8_t bg_g = 0;
        uint8_t bg_b = 0;
        bool bold = false;
        bool underline = false;
        bool italic = false;
        bool reverse = false;

        bool operator==(const Cell& other) const
        {
            return codepoint == other.codepoint
                && fg_r == other.fg_r && fg_g == other.fg_g && fg_b == other.fg_b
                && bg_r == other.bg_r && bg_g == other.bg_g && bg_b == other.bg_b
                && bold == other.bold && underline == other.underline
                && italic == other.italic && reverse == other.reverse;
        }
    };

    struct Size {
        int rows = 0;
        int cols = 0;
    };

    struct Cursor {
        int row = 0;
        int col = 0;
        bool visible = true;
        bool blinking = false;
    };

    struct Rect {
        int top;
        int left;
        int bottom;
        int right;
    };

    Terminal(int rows, int cols);
    ~Terminal();

    Terminal(const Terminal&) = delete;
    Terminal& operator=(const Terminal&) = delete;

    std::vector<Cell> getRow(int row) const;
    Cell getCell(int row, int col) const;
    std::vector<std::vector<Cell>> getScreen() const;
    std::vector<Rect> getDirtyRegions() const;
    void clearDirtyRegions();
    Size getSize() const;
    Cursor getCursor() const;
    std::optional<std::string> getTitle() const;
    bool isAltScreen() const;
    bool isPtyAvailable() const;
    bool isScrollbackSupported() const;
    int getScrollbackSize() const;
    std::vector<Cell> getScrollbackLine(int index) const;

    void sendText(const std::string& utf8);
    void sendKey(const std::string& keyName);
    void sendMouse(int row, int col, int button, bool pressed);
    void resize(int rows, int cols);
    void update();
    void setScrollbackLimit(int lines);
    void injectOutput(const std::string& utf8);

    std::function<void()> onScreenUpdated;
    std::function<void(int row, int col)> onCursorMoved;
    std::function<void(const std::string&)> onTitleChanged;
    std::function<void()> onBell;

private:
    struct Impl;
    Impl* impl;
};
