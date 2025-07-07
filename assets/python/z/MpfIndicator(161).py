class MpfIndicator:
    def __init__(self):
        self.label = z.ContextButton(label=' ' * 11, color=(0.3, 0.3, 1, 0.9), focusable=False, hud=True)
        world.apps['Hud'].top_panel.add(self.label)

    def reset(self, t):
        self.frame_times = []
        self.last_second_timestamp = t

    def update(self, now, delta):
        self.frame_times.append(delta)
        if now - self.last_second_timestamp >= 3000:
            self.update_label()
            self.reset(now)

    def update_label(self):
        if self.frame_times:
            min_time = min(self.frame_times)
            max_time = max(self.frame_times)
            avg_time = sum(self.frame_times) / len(self.frame_times)
            text = f"{min_time:3.0f} {avg_time:3.0f} {max_time:3.0f}"
            self.label.set_label(text)

    def drop(self):
        pass
