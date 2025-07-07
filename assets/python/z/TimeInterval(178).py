import time
class TimeInterval:
    def __init__(self, app, func, interval, call_now):
        self.app = app
        self.func = func
        self.interval = interval
        if call_now:
            self.func()
        self.start()

    def start(self):
        self.started = time.time() * 1000

    def update(self):
        if time.time() * 1000 - self.started > self.interval:
            self.func()
            self.start()

    def drop(self):
        self.app.remove_interval(self)