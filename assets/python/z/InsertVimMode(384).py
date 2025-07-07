class InsertVimMode(z.VimMode):
    def __init__(self):
        super().__init__('insert')
        self.input = None

    def set_input(self, input):
        self.input = input

    def on_enter(self):
        self.input.set_inserting(True)

    def on_leave(self):
        self.input.set_inserting(False)

    def on_character(self, key):
        self.input.insert_char(chr(key))

    def on_keyboard(self, key, scancode, action, mods):
        if action == 1:
            if key == sdl2.SDLK_ESCAPE:
                world.vim.set_current_mode('normal')
                return
            elif key == sdl2.SDLK_RETURN and mods == 64:
                self.input.submit()
                world.vim.set_current_mode('normal')
                return
            elif key == sdl2.SDLK_v and mods == 64:
                for char in world.apps['Clipboard'].get_text():
                    self.input.insert_char(char)
                return
        if action in (1, 2):
            if key == sdl2.SDLK_BACKSPACE:
                self.input.delete_char()
            elif key == sdl2.SDLK_RETURN:
                if self.input.multiline:
                    self.input.insert_char('\n')
                    self.input.match_indent()
                else:
                    self.input.submitted.emit()
                    world.vim.set_current_mode('normal')
            elif key == sdl2.SDLK_TAB:
                if self.input.tabs:
                    if self.input.expandtab:
                        for _ in range(self.input.tabstop):
                            self.input.insert_char(' ')
                    else:
                        self.input.insert_char('\t')
                else:
                    world.vim.set_current_mode('normal')
                    world.focus.focus_next()
            elif key == sdl2.SDLK_RIGHT:
                self.input.move_caret('right')
            elif key == sdl2.SDLK_LEFT:
                self.input.move_caret('left')
