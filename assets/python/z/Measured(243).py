class Measured:
    """Use measure as size"""
    def __init__(self, child):
        self.layout = Layout(children=[child], measurer=self.measurer, layouter=self.layouter, name='measured')

    def measurer(self):
        self.layout.children[0].measurer()
        self.layout.measure = self.layout.children[0].measure

    def layouter(self):
        for child in self.layout.children:
            child.size = self.layout.measure
            child.depth_offset_index = self.layout.depth_offset_index
            child.position = self.layout.position
            child.rotation = self.layout.rotation
            child.layouter()
