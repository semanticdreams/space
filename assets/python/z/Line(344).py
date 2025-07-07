class Line:
    def __init__(self, start=(0, 0, 0), end=(10, 10, 10),
                 color=(0.1, 0.1, 0.1), update=True):
        self.start = np.asarray(start, float)
        self.end = np.asarray(end, float)
        self.color = np.asarray(color, float)

        self.handle = world.renderers.line_vector.allocate(12)
        
        if update:
            self.update()

    def set_start(self, start, update=True):
        self.start = np.asarray(start, float)
        if update:
            self.update_position()

    def set_end(self, end, update=True):
        self.end = np.asarray(end, float)
        if update:
            self.update_position()

    def set_color(self, color, update=True):
        self.color = np.asarray(color, float)
        if update:
            self.update_color()

    def drop(self):
        world.renderers.line_vector.delete(self.handle)

    def update_color(self):
        v = world.renderers.line_vector.view(self.handle)
        v[3:6] = self.color
        v[9:12] = self.color

    def update_position(self):
        v = world.renderers.line_vector.view(self.handle)
        v[0:3] = self.start
        v[6:9] = self.end

    def update(self):
        self.update_position()
        self.update_color()
