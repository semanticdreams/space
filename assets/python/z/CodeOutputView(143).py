class CodeOutputView:
    def __init__(self):
        self.focus = world.focus.add_child(self)
        self.name = z.ReactiveValue('code-output')
        self.input = z.Input(focus_parent=self.focus)
        self.layout = self.input.layout
        self.dropped = z.Signal()

    def set_output(self, output):
        self.input.set_text(output)

    def drop(self):
        self.input.drop()
        self.focus.drop()
        self.dropped.emit()