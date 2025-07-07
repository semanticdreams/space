class Time:
    def __init__(self):
        world.updated.connect(self.on_update)

        self.intervals = []

    def on_update(self, delta):
        for interval in self.intervals:
            interval.update()

    def remove_interval(self, interval):
        self.intervals.remove(interval)

    def set_interval(self, func, delay, call_now=False):
        interval = z.TimeInterval(self, func, delay, call_now)
        self.intervals.append(interval)
        return interval

    def drop(self):
        for interval in self.intervals:
            interval.drop()
