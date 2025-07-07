import os


class Editor:
    def __init__(self, path):
        self.path = path
        self.changed = False
        self.name = z.ReactiveValue(self.make_name())
        self.focus = world.focus.add_child(self)
        self.input = z.Input(focus_parent=self.focus, multiline=True)
        self.input.submitted.connect(self.on_submitted)
        self.input.changed.connect(self.on_input_changed)
        self.layout = self.input.layout

        with open(self.path) as f:
            self.content = f.read()
        self.input.set_text(self.content)

    def make_name(self):
        return f'editor: {"*" if self.changed else ""}{os.path.basename(self.path)}'

    def update_name(self):
        self.name.set(self.make_name())

    def on_submitted(self):
        self.content = self.input.text
        with open(self.path, 'w') as f:
            f.write(self.content)
        self.changed = False
        self.update_name()

    def on_input_changed(self, text):
        if text != self.content and not self.changed:
            self.changed = True
            self.update_name()

    def drop(self):
        self.input.drop()
        self.focus.drop()