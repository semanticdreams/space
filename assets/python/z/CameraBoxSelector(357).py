class CameraBoxSelector:
    def __init__(self):
        self.world = world
        self.box_selector = z.BoxSelector()
        self.box_selector.changed.connect(self.box_selected)
        self.box_selector.exited.connect(self.box_exited)

        world.states.create_state(name='camera-box-selector',
                                  on_enter=self.on_enter, on_leave=self.on_leave)

    def on_enter(self):
        world.window.mouse_button.connect(self.box_selector.on_mouse_button)
        world.window.mouse_motion.connect(self.box_selector.on_mouse_motion)
        world.window.keyboard.connect(self.box_selector.on_keyboard)

    def on_leave(self):
        world.window.mouse_button.disconnect(self.box_selector.on_mouse_button)
        world.window.mouse_motion.disconnect(self.box_selector.on_mouse_motion)
        world.window.keyboard.disconnect(self.box_selector.on_keyboard)

    def box_selected(self, box):
        p1, p2 = box
        u1 = self.world.unproject((*p1, 0.9))
        u2 = self.world.unproject((*p2, 0.9))
        center = (u1 + u2) / 2
        camera_direction = normalize(center - self.world.camera.camera.position)
        distance = 60
        new_camera_position = center + camera_direction * distance
        self.world.camera.camera.set_position(new_camera_position)

    def box_exited(self):
        self.world.states.transit_back()