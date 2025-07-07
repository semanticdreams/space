class CodeGrepView:
    def __init__(self):
        self.focus = world.focus.add_child(self)
        self.name = z.ReactiveValue('CodeGrep')
        self.input = z.Input(focus_parent=self.focus)
        self.input.submitted.connect(self.input_submitted)
        self.result_list = z.ListView([], focus_parent=self.focus, builder=self.item_builder)
        self.column = z.Flex([
            z.FlexChild(self.input.layout),
            z.FlexChild(self.result_list.layout),
        ],
        axis='y', xalign='largest')
        self.layout = self.column.layout

    def item_builder(self, item, context):
        return z.ContextButton(
            label=f'{item["id"]} {item["name"]}',
            actions=[
                ('get', lambda: world.floaties.add(world.classes['CodeView'](item)))
            ]
        )

    def drop(self):
        self.column.drop()
        self.result_list.drop()
        self.input.drop()
        self.focus.drop()

    def input_submitted(self):
        codes = world.codes.grep(self.input.text)
        self.result_list.set_items(codes)