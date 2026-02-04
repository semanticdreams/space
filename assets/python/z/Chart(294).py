class Chart:
    def __init__(self, color=(0.2, 0.2, 0.2, 1), focus_parent=None, series=None):
        self.color = color
        self.axes = [ValueAxis(), ValueAxis()]
        self.series = []
        self.rectangle = z.Rectangle(color=self.color)
        self.layout = z.Layout(name='chart', layouter=self.layouter, measurer=self.measurer)
        self.focus = (focus_parent or world.focus).add_child(obj=self)
        if series:
            for serie in series:
                self.add_series(serie)

    def measurer(self):
        self.layout.measure = np.array((15, 10, 0))

    def layouter(self):
        self.rectangle.layout.size = self.layout.size
        self.rectangle.layout.position = self.layout.position
        self.rectangle.layout.rotation = self.layout.rotation
        self.rectangle.layout.layouter()
        offset = [0, 0, 0.1]
        for serie in self.series:
            serie.set_scale(self.layout.size)
            serie.set_position(offset + self.layout.position)

    def drop(self):
        self.layout.drop()
        self.rectangle.drop()
        for serie in self.series:
            serie.drop()

    def add_series(self, series):
        series.attach_x_axis(self.axes[0]) if not series.x_axis else None
        series.attach_y_axis(self.axes[1]) if not series.y_axis else None
        self.series.append(series)
        self.layout.mark_measure_dirty()
