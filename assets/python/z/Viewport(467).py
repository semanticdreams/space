class Viewport:
    def __init__(self):
        self.value = [0, 0, 0, 0]

    def viewport_changed(self, value):
        self.value = value
