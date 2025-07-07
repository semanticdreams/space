from util import perspective


class Projection:
    def __init__(self, viewport):
        self.viewport = viewport
        self.value = None
        self.fov = 45.0
        self.near = 10
        self.far = 2000.0

        self.update()

        self.changed = z.Signal()

    def update(self):
        self.aspect = self.viewport[2] / float(self.viewport[3])
        self.value = perspective(self.fov, self.aspect,
                                         self.near, self.far)

    def viewport_changed(self, value):
        self.viewport = value
        self.update()
        self.changed.emit()
