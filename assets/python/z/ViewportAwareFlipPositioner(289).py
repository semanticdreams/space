class ViewportAwareFlipPositioner:
    def __init__(self, child):
        self.layout = z.Layout([child],
                                       layouter=self.layouter, measurer=self.measurer, name='viewport-aware-flip-positioner')

    def measurer(self):
        self.layout.children[0].measurer()
        self.layout.measure = self.layout.children[0].measure

    def layouter(self):
        child = self.layout.children[0]
        child.rotation = self.layout.rotation
        child.depth_offset_index = self.layout.depth_offset_index
        child.size = self.layout.size
        # TODO rather just flipping y axis, need to consider viewport and projection
        offset = np.array([0, -child.size[1], 0])
        child.position = self.layout.position + transformations.rotate_vector(child.rotation, offset)
        child.layouter()
        child.position = self.layout.position + transformations.rotate_vector(child.rotation, offset)

    def drop(self):
        self.layout.drop()
