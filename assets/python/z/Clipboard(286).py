class Clipboard:
    def has_text(self):
        return sdl2.SDL_HasClipboardText()

    def get_text(self):
        return sdl2.SDL_GetClipboardText().decode()

    def set_text(self, text):
        return sdl2.SDL_SetClipboardText(text.encode())

    def drop(self):
        pass
