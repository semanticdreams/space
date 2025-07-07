import json


class CameraApp:
    def __init__(self):
        self.world = world
        self.world.camera = self
        self.camera = z.Camera(np.array([0, 0, 0], float),
                             np.array([1, 0, 0, 0], float))
        self.fpc = z.FirstPersonControls(camera=self.camera, window=self.world.window)

        self.box_selector = z.CameraBoxSelector()

        self.cameras = {
            'default': self.camera,
            'identity': z.Camera(np.array([0, 0, 0], float), np.array([1, 0, 0, 0], float))
        }

        world.vim.add_mode(z.CameraVimMode())
        world.vim.modes['leader'].add_action_group(z.VimActionGroup('camera', [
            z.VimAction('camera', self.set_camera_vim_mode, sdl2.SDLK_k),
        ]))

        self.load_camera()
        self.debounced_camera_position = z.DebouncedCameraPosition()
        self.debounced_camera_position.changed.connect(self.camera_changed)

        world.audio.set_listener_position(self.camera.position.tolist())

    def set_camera_vim_mode(self):
        world.vim.set_current_mode('camera')

    def __getitem__(self, key):
        return self.cameras[key]

    def load_camera(self):
        data = world.db.execute('select * from cameras where id = 0').fetchall()[0]
        self.camera.set_position(json.loads(data['position']))
        self.camera.set_rotation(json.loads(data['rotation']))

    def camera_changed(self):
        with world.db:
            world.db.execute('update cameras set position = ?, rotation = ? where id = ?',
                       (json.dumps(self.camera.position.tolist()),
                        json.dumps(self.camera.rotation.tolist()),
                        0))
        world.audio.set_listener_position(self.camera.position.tolist())

    def drop(self):
        pass
