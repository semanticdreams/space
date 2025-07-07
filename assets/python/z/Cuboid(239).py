class Cuboid:
    _rotations = [np.asarray(x, float) for x in [
        (1, 0, 0, 0),
        transformations.quaternion_about_axis(math.pi, (0, 1, 0)),
        transformations.quaternion_about_axis(math.pi * 1.5, (0, 1, 0)),
        transformations.quaternion_about_axis(math.pi * 0.5, (0, 1, 0)),
        transformations.quaternion_about_axis(math.pi * 1.5, (1, 0, 0)),
        transformations.quaternion_about_axis(math.pi * 0.5, (1, 0, 0)),
    ]]

    def __init__(self, children):
        self.layout = z.Layout(children=children, measurer=self.measurer, layouter=self.layouter, name='cuboid')

    def measurer(self):
        for child in self.layout.children:
            child.measurer()
        m = [x.measure for x in self.layout.children]
        self.layout.measure = np.array((
            max(m[0][0], m[1][0], m[4][0], m[5][0]),
            max(m[0][1], m[1][1], m[2][1], m[3][1]),
            max(m[2][0], m[3][0], m[4][1], m[5][1]),
        ), float)

    def layouter(self):
        axis_mapping = {0: (0, 1, 2), 1: (0, 1, 2), 3: (2, 1, 0), 2: (2, 1, 0),
                        5: (0, 2, 1), 4: (0, 2, 1)}
        for i, child in enumerate(self.layout.children):
            child.size = np.array([self.layout.size[x] for x in axis_mapping[i]], float)
        offsets = np.array((
            (0, 0, 0),
            (-self.layout.size[0], 0, self.layout.size[2]),
            (-self.layout.size[2], 0, 0),
            (0, 0, self.layout.size[0]),
            (0, 0, self.layout.size[1]),
            (0, -self.layout.size[2], 0)
        ), float)
        for i, child in enumerate(self.layout.children):
            child.rotation = transformations.quaternion_multiply(
                self.layout.rotation, self._rotations[i])
            child.position = self.layout.position + \
                    transformations.rotate_vector(child.rotation, offsets[i])
            child.depth_offset_index = self.layout.depth_offset_index
            child.layouter()

    def drop(self):
        self.layout.drop()
