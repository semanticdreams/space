class LayoutsVimMode(z.VimMode):
    def __init__(self):
        super().__init__('layouts')
        self.add_action_group(z.VimActionGroup('default', [
            z.VimAction('leave', self.leave, sdl2.SDLK_ESCAPE),
            z.VimAction('snap-to-min-z-axis-aligned-plane', self.snap_to_min_z_axis_aligned_plane,
                                sdl2.SDLK_z),
            z.VimAction('enter-selector', self.enter_selector,
                                sdl2.SDLK_s),
        ]))
        
    def leave(self):
        world.vim.set_current_mode('normal')

    def snap_to_min_z_axis_aligned_plane(self):
        nodes = world.float.objs
        min_z = min(x.layout.position[2] for x in nodes)
        for node in nodes:
            node.layout.set_position((node.layout.position[0], node.layout.position[1], min_z))
        world.vim.set_current_mode('normal')

    def enter_selector(self):
        world.states.transit(state_id=world.float.selector_state_id)
        world.vim.set_current_mode('normal')