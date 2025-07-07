import io, traceback
class PyObjView:
    def __init__(self, obj, reloadable=False, focus_parent=world.focus,
                 show_console=True):
        self.obj = obj
        self.reloadable = reloadable
        self.show_underscored = False
        self.show_console = show_console
        self.name = z.ReactiveValue(self.make_name())
        self.focus = focus_parent.add_child(obj=self)

        self.obj_type = type(obj)

        self.type_button = z.Button(str(self.obj_type),
                                            wrap=None, focus_parent=self.focus)
        self.type_button.clicked.connect(lambda f, i, d: world.floaties.add(PyObjView(self.obj_type)))

        self.class_button = z.Button('class',
                                            focus_parent=self.focus)
        def get_class_clicked(f, i, d):
            ClassView = world.classes['ClassView']
            class_view = ClassView(world.classes.get_class_code(name=self.obj.__class__.__name__), self.obj)
            #if self.reloadable:
            #    def on_class_changed(_):
            #        world.floaties.reload(self.obj)
            #    class_view.changed.connect(on_class_changed)
            world.floaties.add(class_view)
        self.class_button.clicked.connect(get_class_clicked)

        self.inspect_panel = z.Flex([
            z.FlexChild(self.type_button.layout),
            z.FlexChild(self.class_button.layout),
        ], yalign='largest')

        self.actions_panel = world.classes.get_class(name='ActionsPanel')(actions=[
            ('reload', self.update_items),
            ('__', self.toggle_underscore_attrs_triggered),
            ('call', self.call_triggered),
            ('call with args', self.call_with_args_triggered),
            ('with view', self.custom_view_class_triggered),
            ('with default view', self.with_default_view_triggered),
        ],
            focus_parent=self.focus
        )

        self.search_view = z.SearchView([], builder=z.PyObjAttr, show_head=False, focus_parent=self.focus)

        if self.show_console:
            self.code_input = z.Input(focus_parent=self.focus, multiline=True, max_lines=5,
                min_lines=5)
            self.code_input.submitted.connect(self.code_submitted)
            self.code_output = z.ContextButton(focus_parent=self.focus)

        them = [
            z.FlexChild(self.inspect_panel.layout),
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.search_view.layout),
        ]
        if self.show_console:
            them.extend([
                    z.FlexChild(self.code_input.layout),
                    z.FlexChild(self.code_output.layout)
            ])
        self.column = z.Flex(them, axis='y', xalign='largest')

        self.layout = self.column.layout

        self.update_items()

    def code_submitted(self):
        code_str = self.code_input.text
        out, err = io.StringIO(), io.StringIO()
        error = None
        with z.Redirected(out=out, err=err):
            out.flush; err.flush()
            try:
                exec(code_str, {'self': self.obj})
            except:
                error = traceback.format_exc()
            output = out.getvalue()
        self.code_output.set_label((error or output).strip())

    def make_name(self):
        return f'pyobj: {self.obj}'

    def update_items(self):
        objs = [(self.obj, x) for x in dir(self.obj)
                if not x.startswith('__') or self.show_underscored]
        self.search_view.set_items(objs)

    def drop(self):
        self.column.drop()
        self.inspect_panel.drop()
        self.type_button.drop()
        self.class_button.drop()
        self.search_view.drop()
        if self.show_console:
            self.code_input.drop()
            self.code_output.drop()
        self.actions_panel.drop()
        self.focus.drop()

    def custom_view_class_triggered(self):
        world.floaties.add(z.OpenWithClassView(self.obj))

    def with_default_view_triggered(self):
        view_class_names = world.apps['DefaultViews'].get_views(type(self.obj).__name__)
        cls = world.classes.get_class(name=view_class_names[0])
        world.floaties.add(cls(self.obj))

    def toggle_underscore_attrs_triggered(self):
        self.show_underscored = not self.show_underscored
        self.update_items()

    def call_triggered(self):
        try:
            result = self.obj()
        except Exception as e:
            world.floaties.add(z.PyErrorView(e))
        else:
            world.floaties.add(PyObjView(result))

    def call_with_args_triggered(self):
        world.floaties.add(PyCallView(self.obj))
