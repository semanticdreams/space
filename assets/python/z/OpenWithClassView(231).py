class OpenWithClassView:
    def __init__(self, obj):
        self.obj = obj
        self.focus = world.focus.add_child(obj=self)
        class_names = [x['name'] for x in world.classes.codes.values()]
        items = zip(class_names, class_names)
        self.search_view = z.SearchView(items=items, focus_parent=self.focus, show_head=False)
        self.search_view.submitted.connect(self.submit_triggered)
        self.layout = self.search_view.layout

    def submit_triggered(self, o):
        class_name = o[0]
        world.apps['DefaultViews'].set_default_view(type(self.obj).__name__, class_name)
        world.floaties.drop_obj(self)
        cls = world.classes.get_class(name=class_name)
        try:
            world.floaties.add(cls(self.obj))
        except Exception as e:
            world.floaties.add(PyErrorView(e))

    def drop(self):
        self.search_view.drop()
        self.focus.drop()
