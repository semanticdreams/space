class PyObjAttr:
    def __init__(self, item, context):
        self.obj, self.attr = item
        self.value = getattr(self.obj, self.attr)
        self.button = z.ContextButton(
            label=f'{self.attr[:15].ljust(15)}: {str(self.value)[:30]}',
            focus_parent=context['focus_parent'],
            actions=[
                ('get', self.get_triggered),
                ('get with view', self.get_with_view_triggered),
                ('get with default view', self.get_with_default_view_triggered),
            ]
        )
        self.spatiolator = self.button.spatiolator
        self.layout = self.button.layout

    def get_triggered(self):
        world.floaties.add(z.PyObjView(self.value))

    def get_with_view_triggered(self):
        world.floaties.add(z.OpenWithClassView(self.value))

    def get_with_default_view_triggered(self):
        views = world.apps['DefaultViews'].get_views(type(self.value).__name__)
        cls = world.classes.get_class(name=views[0])
        world.floaties.add(cls(self.value))

    def drop(self):
        self.button.drop()
