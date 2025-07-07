class Rectangle(z.Droppable):
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

    def __init__(self, color=(1, 0, 0, 1), hud=False):
        super().__init__()
        self.dropped = False
        self.color = np.asarray(color)
        self.hud = hud
        if self.hud:
            self.triangle_vector = world.renderers.hud_triangle_vector
        else:
            self.triangle_vector = world.renderers.scene_triangle_vector
        self.handle = self.triangle_vector.allocate(self.vertices.size)

        self.hidden = False

        self.layout = z.Layout(measurer=self.measurer, layouter=self.layouter, name='rectangle')

        self.dirty = {'color'}

    def set_hud(self, hud):
        if hud != self.hud:
            self.triangle_vector.delete(self.handle)
            self.handle = None
            if hud:
                self.triangle_vector = world.renderers.hud_triangle_vector
            else:
                self.triangle_vector = world.renderers.scene_triangle_vector
            self.handle = self.triangle_vector.allocate(self.vertices.size)
            self.hud = hud

    def clone(self):
        return self.__class__(color=self.color, hud=self.hud)

    def __mul__(self, value):
        return [self] + [self.clone() for _ in range(value - 1)]

    def measurer(self):
        self.measure = np.array((0, 0, 0), float)

    def layouter(self):
        self.update_color()
        v = self.triangle_vector.view(self.handle)
        rotation_matrix = transformations.quaternion_matrix(
            self.layout.rotation)[:-1, :-1]
        size = np.array((self.layout.size[0], self.layout.size[1], 0))
        for i in range(0, v.size, 8):
            if self.hidden:
                v[i:i+3] = np.array((0, 0, 0))
            else:
                b = self.vertices[i:i+3]
                v[i:i+3] = np.matmul(rotation_matrix, (size * b)) + self.layout.position
                v[i+7] = self.layout.depth_offset_index

    def aabb(self):
        v = self.triangle_vector.view(self.handle)
        vertices = [v[0:3], v[8:11], v[16:19], v[24:27], v[32:36], v[40:43]]
        return np.array((np.amin(vertices, axis=0), np.amax(vertices, axis=0)))

    def intersect(self, ray):
        return self.layout.intersect(ray)

    def update_color(self):
        if 'color' in self.dirty:
            v = self.triangle_vector.view(self.handle)
            for i in range(0, v.size, 8):
                v[i+3:i+7] = self.color
            self.dirty.remove('color')

    def set_color(self, color):
        self.color = np.asarray(color, float)
        self.dirty.add('color')
        self.layout.mark_layout_dirty()

    def show(self):
        self.hidden = False
        self.layout.mark_layout_dirty()

    def hide(self):
        self.hidden = True
        self.layout.mark_layout_dirty()

    def drop(self):
        self.layout.drop()
        self.triangle_vector.delete(self.handle)
        self.dropped = True
