import time
class SnackbarHost:
    def __init__(self):
        self.column = z.Flex([], axis='y', xalign='largest', yspacing=0.3)
        self.layout = self.column.layout
        self.buttons = []
        self.messages = []
        self.interval = world.apps['Time'].set_interval(self.update_snackbars, 1000)

    def update_snackbars(self):
        self.clear()
        t = time.time()
        for message in list(self.messages):
            if message['duration'] \
                and t - message['start_time'] >= message['duration']:
                self.messages.remove(message)
                continue
            self.buttons.append(
                z.ContextButton(
                    label=message['text'],
                    focusable=False, hud=True
                )
            )
        self.column.set_children([z.FlexChild(x.layout) for x in self.buttons])
        self.column.layout.mark_measure_dirty()

    def clear(self):
        self.column.clear_children()
        for button in self.buttons:
            button.drop()
        self.buttons.clear()

    def show_message(self, text, duration=2, color=(0, 0, 1, 1)):
        self.messages.append({
            'text': text,
            'duration': duration,
            'color': color,
            'start_time': time.time()
        })
        self.update_snackbars()

    def drop(self):
        self.interval.drop()
        self.clear()
        self.column.drop()
