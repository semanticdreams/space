class CodesVimMode(z.VimMode):
    def __init__(self):
        super().__init__('codes')
        self.add_action_group(z.VimActionGroup('codes', [
            z.VimAction('leave', self.set_current_vim_mode_normal, sdl2.SDLK_ESCAPE),
            z.VimAction('create-code', self.create_code, sdl2.SDLK_c),
            z.VimAction('create-class', self.create_class, sdl2.SDLK_k),
            z.VimAction('classes', self.open_classes, sdl2.SDLK_l),
            z.VimAction('codes', self.open_codes, sdl2.SDLK_SLASH),
        ]))

    def set_current_vim_mode_normal(self):
        world.vim.set_current_mode('normal')

    def create_code(self):
        world.vim.set_current_mode('normal')
        code_entity = z.CodeEntity.create()
        G.add_node(code_entity)
        G.save()
        world.floaties.add(code_entity.view(code_entity))

    def create_class(self):
        world.vim.set_current_mode('normal')
        class_entity = z.ClassEntity.create()
        G.add_node(class_entity)
        G.save()
        world.floaties.add(class_entity.view(class_entity))

    def open_classes(self):
        world.vim.set_current_mode('normal')
        world.floaties.add(z.ClassesView())

    def open_codes(self):
        world.vim.set_current_mode('normal')
        world.floaties.add(z.CodesView())
