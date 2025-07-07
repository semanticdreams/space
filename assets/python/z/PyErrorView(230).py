import traceback
class PyErrorView:
    def __init__(self, error):
        self.error = error
        self.focus = world.focus.add_child(obj=self)
        self.button = z.ContextButton(
            color=(0.6, 0.3, 0.3, 1),
            focus_parent=self.focus,
            label="".join(traceback.TracebackException.from_exception(self.error).format())
        )
        self.spatiolator = self.button.spatiolator
        self.layout = self.button.layout

    def set_hud(self, hud):
        self.button.set_hud(hud)

    def drop(self):
        self.button.drop()
        self.focus.drop()
