class QuitVimMode(z.VimMode):
    def __init__(self):
        super().__init__('quit')
        self.add_action_group(z.VimActionGroup('default', [
            z.VimAction('leave', self.set_current_mode_normal, sdl2.SDLK_ESCAPE),
            z.VimAction('close-window', self.close_window, sdl2.SDLK_q),
        ]))

    def set_current_mode_normal(self):
        world.vim.set_current_mode('normal')

    def close_window(self):
        space.quit()
