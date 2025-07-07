class DynamicGraphVimMode(z.VimMode):
    def __init__(self):
        super().__init__('dynamic-graph')
        self.add_action_group(z.VimActionGroup('dynamic-graph', [
            z.VimAction('leave', self.leave, sdl2.SDLK_ESCAPE),
        ]))

    def leave(self):
        world.vim.set_current_mode('normal')
