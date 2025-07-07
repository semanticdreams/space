import datetime


class ClockView:
    def __init__(self):
        self.focus = world.focus.add_child(self)

        self.label = z.Label()

        self.on_interval()

        self.interval = world.apps['Time'].set_interval(self.on_interval, 1000)

        self.layout = self.label.layout

    def get_name(self):
        return 'clock'

    def on_interval(self):
        t = datetime.datetime.now().strftime('%H:%M:%S')
        self.label.text.set(t)

    def drop(self):
        self.interval.drop()
        self.label.drop()
        self.focus.drop()
