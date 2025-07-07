class CodesApp:
    def __init__(self):
        world.vim.add_mode(world.classes['CodesVimMode']())
        world.vim.modes['leader'].add_action_group(z.VimActionGroup('codes', [
            z.VimAction('codes', self.set_codes_vim_mode, sdl2.SDLK_c),
        ]))

    def set_codes_vim_mode(self):
        world.vim.set_current_mode('codes')


    def drop(self):
        pass
