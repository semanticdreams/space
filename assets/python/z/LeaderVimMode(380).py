class LeaderVimMode(z.VimMode):
    def __init__(self):
        super().__init__('leader')
        self.add_action_group(z.VimActionGroup('default', [
            z.VimAction('leave', self.set_current_mode_normal, sdl2.SDLK_ESCAPE),
            z.VimAction('apps', self.set_current_mode_apps, sdl2.SDLK_a),
            z.VimAction('quit', self.set_current_mode_quit, sdl2.SDLK_q),
            z.VimAction('state', self.set_current_mode_state, sdl2.SDLK_t),
            z.VimAction('entities', self.set_current_mode_entities, sdl2.SDLK_e),
        ]))

    def set_current_mode_normal(self):
        world.vim.set_current_mode('normal')

    def set_current_mode_apps(self):
        world.vim.set_current_mode('apps')

    def set_current_mode_quit(self):
        world.vim.set_current_mode('quit')

    def set_current_mode_state(self):
        world.vim.set_current_mode('state')

    def set_current_mode_entities(self):
        world.vim.set_current_mode('entities')
