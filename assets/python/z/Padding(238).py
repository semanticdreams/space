class Padding:
    def __init__(self, child, insets=[0.5]):
        #self.child = child
        self.insets = z.EdgeInsets.auto(insets)
        self.layout = z.Layout(children=[child], measurer=self.measurer, layouter=self.layouter, name='padding')

    def measurer(self):
        for child in self.layout.children:
            child.measurer()
        self.layout.measure = np.sum([child.measure for child in self.layout.children], axis=0) + \
                self.insets[:3] + self.insets[3:]

    def layouter(self):
        for child in self.layout.children:
            child.depth_offset_index = self.layout.depth_offset_index
            child.size = self.layout.size - self.insets[:3] - self.insets[3:]
            child.rotation = self.layout.rotation
            offset = self.insets[:3]
            child.position = self.layout.position \
                    + transformations.rotate_vector(self.layout.rotation, offset)
            child.layouter()

    def drop(self):
        self.layout.drop()
