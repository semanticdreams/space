class EntitiesVimMode(z.VimMode):
    def __init__(self):
        super().__init__('entities')
        self.add_action_group(z.VimActionGroup('entities', [
            z.VimAction('leave', self.leave, sdl2.SDLK_ESCAPE),
            z.VimAction('graph', self.graph, sdl2.SDLK_g),
            z.VimAction('create', self.create, sdl2.SDLK_c),
        ]))

    def graph(self):
        self.leave()
        world.floaties.add(G.view(G))

    def create(self):
        self.leave()
        world.floaties.add(z.CreateEntityView())

    def leave(self):
        world.vim.set_current_mode('normal')
