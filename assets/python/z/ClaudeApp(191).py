class ClaudeApp:
    def __init__(self):
        self.claude = world.apps['Claude']

        world.vim.add_mode(z.ClaudeVimMode())
        world.vim.modes['apps'].add_action_group(
            z.VimActionGroup('claude', [
                z.VimAction('claude', lambda: world.vim.set_current_mode('claude'), sdl2.SDLK_c),
            ]))

    def drop(self):
        world.vim.modes['apps'].remove_action_group('claude')
        world.vim.remove_mode('claude')
