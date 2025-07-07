class ClaudeVimMode(z.VimMode):
    def __init__(self):
        super().__init__('claude')
        self.add_action_group(z.VimActionGroup('claude', [
            z.VimAction('list', self.open_claude, sdl2.SDLK_l),
            z.VimAction('create', self.create_conversation, sdl2.SDLK_c),
        ]))
        
    def open_claude(self):
        world.vim.set_current_mode('normal')
        world.floaties.add(z.ClaudeView())
        
    def create_conversation(self):
        world.vim.set_current_mode('normal')
        world.floaties.add(z.ClaudeConversationView(
            world.apps['Claude'].create_conversation()))
