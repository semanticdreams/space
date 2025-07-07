class LayoutsApp:
    def __init__(self):
        world.vim.add_mode(z.LayoutsVimMode())
        world.vim.modes['normal'].add_action_group(z.VimActionGroup('layouts', [
            z.VimAction('layouts', self.set_current_vim_mode_layouts, sdl2.SDLK_l),
        ]))

    def set_current_vim_mode_layouts(self):
        world.vim.set_current_mode('layouts')
