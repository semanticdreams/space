class AppsBrowser:
    def __init__(self, apps):
        self.apps = apps
        self.list_view = None
        self.focus = world.focus.add_child(obj=self)

        def builder(app, context):
            return z.ContextButton(
                label=app.__class__.__name__, focus_parent=context['focus_parent'],
                color=(0, 1, 0, 1), actions=[
                    ('pyobj', lambda: world.floaties.add(z.PyObjView(app))),
                    ('reload', lambda: world.apps.reload_app(app.__class__.__name__)),
                    ('close', lambda: world.apps.drop_app(app))
                ]
            )

        self.list_view = z.ListView(list(self.apps.names.values()), builder, focus_parent=self.focus, show_head=False)
        self.layout = self.list_view.layout

        self.apps.apps_changed.connect(self.apps_changed)

    def apps_changed(self):
        self.list_view.set_items(list(self.apps.names.values()))

    def drop(self):
        self.apps.apps_changed.disconnect(self.apps_changed)
        self.list_view.drop()
        self.focus.drop()
