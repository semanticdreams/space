class Spacer:
    def __init__(self):
        self.layout = z.Layout(measurer=self.measurer, layouter=self.layouter, name='spacer')

    def measurer(self):
        self.layout.measure = np.array((0, 0, 0), float)

    def layouter(self):
        pass

    def drop(self):
        self.layout.drop()