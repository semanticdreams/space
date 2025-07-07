import psutil

class MemoryUsageIndicator:

    def __init__(self):
        self.button = z.ContextButton(hud=True, color=[0, 0.6, 0, 1])
        world.hud.top_panel.add(self.button)
        self.interval = world.apps['Time'].set_interval(self.update, 1000, True)

    def update(self):
        mb = psutil.Process().memory_info().rss / 1024 ** 2
        return self.button.set_label(str(round(mb)))
