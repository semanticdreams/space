class PyDictView:
    def __init__(self, obj, focus_parent=world.focus):
        self.obj = obj
        self.name = z.ReactiveValue(self.make_name())
        self.focus = focus_parent.add_child(obj=self)

        actions = [
            ('reload', self.reload),
        ]
        self.actions_panel = z.ActionsPanel(actions, self.focus)
        self.search_view = z.SearchView([], focus_parent=self.focus, builder=self.builder, show_head=False)
        self.column = z.Flex([z.FlexChild(self.actions_panel.layout),
        z.FlexChild(self.search_view.layout)], axis='y', xalign='largest')

        self.layout = self.column.layout

        self.reload()

    def builder(self, item, context):
        (key, value), label = item
        return z.ContextButton(label=f'{str(key)}: {str(value)[:30]}', focus_parent=context['focus_parent'])

    def reload(self):
        items = sorted([(x, str(x[0])) for x in self.obj.items()], key=lambda x: x[1])
        self.search_view.set_items(items)

    def make_name(self):
        return f'dict: {id(self.obj)}'

    def drop(self):
        self.column.drop()
        self.actions_panel.drop()
        self.search_view.drop()
        self.focus.drop()