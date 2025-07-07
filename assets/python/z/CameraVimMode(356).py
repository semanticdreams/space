class CameraVimMode(z.VimMode):
    def __init__(self):
        super().__init__('camera')
        self.add_action_group(z.VimActionGroup('camera', [
            z.VimAction('leave', self.set_current_vim_mode_normal, sdl2.SDLK_ESCAPE),
            z.VimAction('enable-fpc', self.enable_fpc, sdl2.SDLK_f),
            z.VimAction('approach1', self.approach1, sdl2.SDLK_1),
            z.VimAction('approach2', self.approach2, sdl2.SDLK_2),
            z.VimAction('approach3', self.approach3, sdl2.SDLK_3),
            z.VimAction('reset', self.reset, sdl2.SDLK_0),
            z.VimAction('snap-to-grid', self.snap_to_grid, sdl2.SDLK_9),
            z.VimAction('box-selector', self.box_selector, sdl2.SDLK_b),
        ]))

    def set_current_vim_mode_normal(self):
        world.vim.set_current_mode('normal')

    def enable_fpc(self):
        world.states.transit(state_name='fpc')
        world.vim.set_current_mode('normal')

    def approach(self, closeness):
        node = world.focus.current
        if not node or not node.obj:
            return
        world.camera['default'].approach(node.obj.layout, closeness)
        world.vim.set_current_mode('normal')

    def approach1(self):
        self.approach(100)

    def approach2(self):
        self.approach(200)

    def approach3(self):
        self.approach(300)

    def reset(self):
        world.camera.camera.set_position([0, 0, 0])
        world.camera.camera.set_rotation([1, 0, 0, 0])
        world.vim.set_current_mode('normal')

    def snap_to_grid(self):
        # snap position
        grid_unit_size = 1
        self.world.camera.camera.set_position(
            np.round(self.world.camera.camera.position / grid_unit_size) * grid_unit_size)
        # snap rotation
        grid_unit_angle = 90
        r = self.world.camera.camera.rotation
        theta = np.arccos(r[0]) * 2
        sin_theta_over_2 = np.sqrt(1 - r[0]**2)
        axis = r[1:] / (sin_theta_over_2 + 1e-10)
        theta_deg = np.degrees(theta)
        snapped_theta_deg = round(theta_deg / grid_unit_angle) * grid_unit_angle
        snapped_theta = np.radians(snapped_theta_deg)
        new_w = np.cos(snapped_theta / 2)
        new_xyz = axis * np.sin(snapped_theta / 2)
        world.camera.camera.set_rotation([new_w, new_xyz[0], new_xyz[1], new_xyz[2]])
        world.vim.set_current_mode('normal')

    def box_selector(self):
        world.states.transit(state_name='camera-box-selector')
        world.vim.set_current_mode('normal')