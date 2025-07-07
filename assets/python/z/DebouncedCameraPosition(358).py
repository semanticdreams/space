class DebouncedCameraPosition:
    def __init__(self, interval=10):
        self.world = world
        self.interval = interval
        self.changed = z.Signal()
        self.position = self.world.camera.camera.position.copy()
        self.world.camera.camera.changed.connect(self.camera_changed)

    def camera_changed(self):
        new_position = self.world.camera.camera.position
        if np.linalg.norm(new_position - self.position) > self.interval:
            self.position = new_position.copy()
            self.changed.emit()

    def drop(self):
        self.world.camera.camera.changed.disconnect(self.camera_changed)
        self.changed.clear_callbacks()