class FunkyTriangle:
    vertices = np.array([
        0, 0, 0,
        1, 0, 0, 1,
        0, 1, 0,
        0, 1, 0, 1,
        1, 1, 0,
        0, 0, 1, 1,
    ], np.float32)

    def __init__(self):
        self.name = z.ReactiveValue('funky-triangle')
        self.focus = world.focus.add_child(self)
        self.triangle_vector = world.render_configurations['triangles'].vector
        self.handle = self.triangle_vector.allocate(self.vertices.size)

        self.layout = z.Layout(measurer=self.measurer, layouter=self.layouter, name='funky-triangle',
                                       transformer=self.update_positions)

        #self.layout.set_constraints(z.BoxConstraints(min=self.size, max=self.size))

        #self.spatiolator = z.Spatiolator(self.layout, self)

        self.update_color()

    def drop(self):
        self.layout.drop()
        self.triangle_vector.delete(self.handle)
        self.focus.drop()

    def update_positions(self):
        v = self.triangle_vector.view(self.handle)
        rotation_matrix = transformations.quaternion_matrix(
            self.layout.rotation)[:-1, :-1]
        size = np.array((self.size[0], self.size[1], 0))
        for i in range(0, v.size, 7):
            b = self.vertices[i:i+3]
            v[i:i+3] = np.matmul(rotation_matrix, (size * b)) + self.layout.position

    def update_color(self):
        v = self.triangle_vector.view(self.handle)
        for i in range(0, v.size, 7):
            v[i+3:i+7] = z.random_color()

    def measurer(self):
        return np.array((30, 30, 0))

    def layouter(self, constraints):
        #self.size = constraints.min
        self.size = np.array((constraints.max[0], constraints.max[1], 0))
        return self.size
        #return np.pad(self.size, (0, 1))

    def aabb(self):
        v = self.triangle_vector.view(self.handle)
        vertices = [v[0:3], v[7:10], v[14:17]]
        return np.array((np.amin(vertices, axis=0), np.amax(vertices, axis=0)))

    def intersect(self, ray):
        v = self.triangle_vector.view(self.handle)
        t1 = np.array((v[0:3], v[7:10], v[14:17]))
        return z.ray_triangle_intersect(ray, t1)