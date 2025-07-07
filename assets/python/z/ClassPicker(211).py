class ClassPicker:
    def __init__(self):
        self.focus = world.focus.add_child(self)
        self.name = z.ReactiveValue('ClassPicker')
        self.submitted = z.Signal()
        self.search_view = z.SearchView(
            [(x, x['name'])for x in world.classes.codes.values()],
            focus_parent=self.focus, show_head=False
        )
        self.search_view.submitted.connect(lambda item: self.submitted.emit(item[0]))
        self.layout = self.search_view.layout

    def drop(self):
        self.search_view.drop()
        self.focus.drop()