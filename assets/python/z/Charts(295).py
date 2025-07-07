class Charts:
    def __init__(self):
        self.charts = []

    def create_chart(self, *args, **kwargs):
        chart = z.Chart(*args, **kwargs)
        self.charts.append(chart)
        return chart

    def drop_chart(self, chart):
        self.charts.remove(chart)
        return chart.drop()

    def drop(self):
        for chart in self.charts:
            self.drop_chart(chart)