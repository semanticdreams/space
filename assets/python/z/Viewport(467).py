class Viewport:
    def __init__(self):
        self.value = [0, 0, 0, 0]
        self.changed = z.Signal()

    def viewport_changed(self, value):
        self.value = value
        self.changed.emit()
