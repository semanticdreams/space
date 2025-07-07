class StateVimMode(z.VimMode):
    def __init__(self):
        super().__init__('state')
        self.add_action_group(z.VimActionGroup('default', [
            z.VimAction('leave', self.set_current_mode_normal, sdl2.SDLK_ESCAPE),
            z.VimAction('spatiolation', self.set_state_spatiolation, sdl2.SDLK_t),
            z.VimAction('host', self.set_state_host, sdl2.SDLK_h),
        ]))

    def set_current_mode_normal(self):
        world.vim.set_current_mode('normal')

    def set_state_spatiolation(self):
        world.states.transit(state_name='spatiolation')
        world.vim.set_current_mode('normal')

    def set_state_host(self):
        world.states.transit(state_name='host')
        world.vim.set_current_mode('normal')