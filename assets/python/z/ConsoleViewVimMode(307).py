class ConsoleViewVimMode(z.VimMode):
    def __init__(self, console_view):
        super().__init__('console')
        self.console_view = console_view
        self.console = console_view.console

    def on_keyboard(self, key, scancode, action, mods):
        if action in (1, 2):
            if key == sdl2.SDLK_RETURN:
                self.console.ret()
            elif key == sdl2.SDLK_BACKSPACE:
                self.console.backspace()
            elif key == sdl2.SDLK_UP:
                self.console.browse_history('up')
            elif key == sdl2.SDLK_DOWN:
                self.console.browse_history('down')
            elif key == sdl2.SDLK_ESCAPE:
                world.vim.set_current_mode('normal')

    def on_character(self, key):
        self.console.write(chr(key))