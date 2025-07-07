import os
import datetime

class DaysSinceBirthIndicator:
    def __init__(self):
        self.label = z.ContextButton(hud=True,
            focusable=False,
            label=self.get_formatted_value(),
            color=world.themes.theme.turquoise,
            actions=[
            ]
        )
        world.apps['Hud'].top_panel.add(self.label)
        self.interval = world.apps['Time'].set_interval(self.on_interval, 865)

    def on_interval(self):
        self.label.set_label(self.get_formatted_value())

    def get_formatted_value(self):
        return f'{self.get_xth_day():.2f}'

    def get_xth_day(self):
        fixed_date = datetime.datetime.strptime(os.getenv('SPACE_BIRTHDATE', '2000-01-01'), "%Y-%m-%d")
        now = datetime.datetime.now()
        days_diff = (now - fixed_date).days
        seconds_today = (now - datetime.datetime.combine(now.date(), datetime.datetime.min.time())).total_seconds()
        fraction_of_day = seconds_today / 86400  # 86400 seconds in a day
        xth_day = days_diff + 1 + fraction_of_day
        return xth_day

    def drop(self):
        self.interval.drop()
        world.apps['Hud'].top_panel.remove(self.label)
        self.label.drop()
