class TriangleLine:
    def __init__(self, start_position, end_position, color=(0.3, 0.3, 0.3, 1)):
        self.start_position = np.asarray(start_position, float)
        self.end_position = np.asarray(end_position, float)
        self.thickness = 2
        self.color = np.asarray(color, float)
        self.triangle_vector = world.renderers.scene_triangle_vector
        self.handle = self.triangle_vector.allocate(24)

    def set_start_position(self, position):
        self.start_position = np.asarray(position, float)

    def set_end_position(self, position):
        self.end_position = np.asarray(position, float)

    def update(self):
        v = self.triangle_vector.view(self.handle)
        d = self.end_position - self.start_position
        t = np.array((-d[1], d[0], d[2]))
        t = t / np.linalg.norm(t)
        v[0:3] = self.start_position - self.thickness * t
        v[8:11] = self.start_position + self.thickness * t
        v[16:19] = self.end_position
        for i in range(0, v.size, 8):
            v[i+3:i+7] = self.color
            v[i+2] -= 0.05

    def drop(self):
        self.triangle_vector.delete(self.handle)
