class Sized:
    """Fixed size layout"""
    def __init__(self, child, size):
        self.size = np.asarray(size, float)
        self.layout = Layout(children=[child], measurer=self.measurer, layouter=self.layouter, name='sized')

    def set_size(self, size):
        self.size = np.asarray(size, float)
        self.layout.mark_measure_dirty()

    def measurer(self):
        self.layout.children[0].measurer()
        self.layout.measure = self.size

    def layouter(self):
        for child in self.layout.children:
            child.depth_offset_index = self.layout.depth_offset_index
            child.size = self.layout.size
            child.position = self.layout.position
            child.rotation = self.layout.rotation
            child.layouter()
