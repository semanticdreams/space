class Aligned:
    def __init__(self, child, axis='x', alignment='start'):
        self.child = child
        self.axis = z.Layout.parse_axis(axis)
        self.alignment = alignment
        self.layout = z.Layout(children=[child], measurer=self.measurer, layouter=self.layouter, name='aligned')

    def measurer(self):
        self.child.measurer()
        self.layout.measure = self.child.measure

    def layouter(self):
        self.child.depth_offset_index = self.layout.depth_offset_index

        self.child.size = self.layout.size.copy()
        if self.alignment != 'stretch':
            self.child.size[self.axis] = self.child.measure[self.axis]

        self.child.position = self.layout.position.copy()
        self.child.rotation = self.layout.rotation

        if self.alignment == 'center':
            self.child.position[self.axis] += (self.layout.size[self.axis] - self.child.measure[self.axis]) / 2
        elif self.alignment == 'end':
            self.child.position[self.axis] += self.layout.size[self.axis] - self.child.measure[self.axis]
        elif self.alignment == 'stretch':
            pass

        # TODO offset rotation

        self.child.layouter()

    def drop(self):
        self.layout.drop()
