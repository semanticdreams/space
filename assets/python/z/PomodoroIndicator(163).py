import time
class PomodoroIndicator:
    def __init__(self):
        self.button = z.ContextButton(label='pomodoro', color=(0.3, 0.6, 0.9, 0.9),
                                              focusable=False,
                                              hud=True,
                                              actions=[
                                                  ('toggle', self.toggle),
                                                  ('restart', self.start_new),
                                              ])
        world.hud.top_panel.add(self.button)

        world.pomodoro.recover_sessions()
        self.current = world.pomodoro.get_most_recently_created_session()
        self.update()

    def toggle(self):
        if self.current is None:
            self.start_new()
        else:
            if self.current['started_at']:
                self.stop()
            else:
                self.resume()

    def update(self):
        self.button.set_label(
            str(round(self.current['duration'] - (self.current['elapsed'] + ((time.time() - self.current['started_at']) if self.current['started_at'] is not None else 0)))))

    def refetch_session(self):
        self.current = world.pomodoro.get_session(self.current['id'])
        self.update()

    def start_new(self):
        self.current = world.pomodoro.get_session(world.pomodoro.create_session())
        self.resume()

    def resume(self):
        world.pomodoro.start_session(self.current['id'])
        self.interval = world.apps['Time'].set_interval(self.update, 1000)
        self.refetch_session()

    def stop(self):
        self.interval.drop()
        world.pomodoro.stop_session(self.current['id'])
        self.refetch_session()

    def drop(self):
        if self.current and self.current['started_at'] is not None:
            self.stop()
        world.hud.top_panel.remove(self.button)
