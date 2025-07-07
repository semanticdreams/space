class SystemCursors:
    def __init__(self):
        self.cursors = {
            'arrow': sdl2.SDL_CreateSystemCursor(sdl2.SDL_SYSTEM_CURSOR_ARROW),
            'hand': sdl2.SDL_CreateSystemCursor(sdl2.SDL_SYSTEM_CURSOR_HAND),
            'ibeam': sdl2.SDL_CreateSystemCursor(sdl2.SDL_SYSTEM_CURSOR_IBEAM),
        }

    def set_cursor(self, name):
        sdl2.SDL_SetCursor(self.cursors[name])

    def drop(self):
        for cursor in self.cursors.values():
            sdl2.SDL_FreeCursor(cursor)