class Stack:
    def __init__(self, children, axis=2, distance=0.01, name=None):
        self.name = name
        self.axis = axis
        self.distance = distance
        self.layout = z.Layout(children=children,
                             measurer=self.measurer, layouter=self.layouter, name='stack')

    def measurer(self):
        for child in self.layout.children:
            child.measurer()
        self.layout.measure = np.max([x.measure for x in self.layout.children], axis=0)

    def layouter(self):
        for i, child in enumerate(self.layout.children):
            child.size = self.layout.size.copy()
            #child.depth_offset_index = self.layout.depth_offset_index + i
            child.position = self.layout.position.copy()
            child.rotation = self.layout.rotation.copy()
            offset = np.array((0, 0, 0), float)
            offset[self.axis] += i * self.distance
            child.position += transformations.rotate_vector(child.rotation, offset)
            child.layouter()

    def drop(self):
        self.layout.drop()
