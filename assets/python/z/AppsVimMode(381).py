class AppsVimMode(z.VimMode):
    def __init__(self):
        super().__init__('apps')
        self.add_action_group(z.VimActionGroup('default', [
            z.VimAction('leave', self.set_current_mode_normal, sdl2.SDLK_ESCAPE),
            z.VimAction('agent-one', self.agent_one, sdl2.SDLK_a),
        ]))

    def agent_one(self):
        world.vim.set_current_mode('normal')
        world.floaties.add(z.AgentOneView())

    def set_current_mode_normal(self):
        world.vim.set_current_mode('normal')
