class RRectangle:
    vertices = np.array([
        0, 0, 0,
        0, 0, 0, 1,
        0,
        0, 1, 0,
        0, 0, 0, 1,
        0,
        1, 1, 0,
        0, 0, 0, 1,
        0,
        1, 1, 0,
        0, 0, 0, 1,
        0,
        1, 0, 0,
        0, 0, 0, 1,
        0,
        0, 0, 0,
        0, 0, 0, 1,
        0,
    ], np.float32)

    def __init__(self, color=(1, 0, 0, 1), position=(0, 0, 0), size=(10, 10),
                 rotation=(1, 0, 0, 0), depth_offset_index=0,
                 hidden=False, hud=False):
        self.color = np.asarray(color, float)
        self.rotation = np.asarray(rotation, float)
        self.position = np.asarray(position, float)
        self.depth_offset_index = depth_offset_index
        self.size = np.asarray(size, float)
        self.hidden = hidden
        self.hud = hud
        if self.hud:
            self.triangle_vector = world.renderers.hud_triangle_vector
        else:
            self.triangle_vector = world.renderers.scene_triangle_vector
        self.handle = self.triangle_vector.allocate(self.vertices.size)
        self.dirty = {'color', 'positions'}

    def clone(self):
        return self.__class__(color=self.color, position=self.position, size=self.size,
                              rotation=self.rotation, hidden=self.hidden, hud=self.hud,
                              depth_offset_index=self.depth_offset_index)

    def __mul__(self, value):
        return [self] + [self.clone() for _ in range(value - 1)]

    __rmul__ = __mul__

    def update_color(self):
        if 'color' in self.dirty:
            v = self.triangle_vector.view(self.handle)
            for i in range(0, v.size, 8):
                v[i+3:i+7] = self.color
            self.dirty.remove('color')

    def update_positions(self):
        if 'positions' in self.dirty:
            v = self.triangle_vector.view(self.handle)
            rotation_matrix = transformations.quaternion_matrix(
                self.rotation)[:-1, :-1]
            size = np.array((self.size[0], self.size[1], 0))
            for i in range(0, v.size, 8):
                if self.hidden:
                    v[i:i+3] = np.array((0, 0, 0))
                else:
                    b = self.vertices[i:i+3]
                    v[i:i+3] = np.matmul(rotation_matrix, (size * b)) + self.position
                    v[i+7] = self.depth_offset_index
            self.dirty.remove('positions')

    def aabb(self):
        v = self.triangle_vector.view(self.handle)
        #vertices = [v[0:3], v[7:10], v[14:17], v[21:24], v[28:31], v[35:38]]
        vertices = [v[0:3], v[8:11], v[16:19], v[24:27], v[32:36], v[40:43]]
        return np.array((np.amin(vertices, axis=0), np.amax(vertices, axis=0)))

    def update(self):
        self.update_color()
        self.update_positions()

    def set_color(self, color):
        self.color = np.asarray(color, float)
        self.dirty.add('color')

    def set_depth_offset_index(self, depth_offset_index):
        self.depth_offset_index = depth_offset_index
        self.dirty.add('positions')

    def set_position(self, position):
        self.position = np.asarray(position, float)
        self.dirty.add('positions')

    def set_rotation(self, rotation):
        self.rotation = np.asarray(rotation, float)
        self.dirty.add('positions')

    def set_size(self, size):
        self.size = np.asarray(size, float)
        self.dirty.add('positions')

    def show(self):
        self.hidden = False
        self.dirty.add('positions')

    def hide(self):
        self.hidden = True
        self.dirty.add('positions')

    def drop(self):
        self.triangle_vector.delete(self.handle)
