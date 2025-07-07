class GamepadsView:
    def __init__(self):
        self.focus = world.focus.add_child(self)
        self.head = z.ContextButton(
            label='gamepads', focus_parent=self.focus, focusable=False,
            actions=[
                ('reload', self.reload),
            ]
        )
        self.listview = z.ListView(world.gamepads.gamepads, builder=self.gamepad_item_builder,
                                           focus_parent=self.focus, show_head=False)
        self.column = z.Flex([self.head, self.listview], axis='y', xalign='largest')
        self.layout = self.column.layout
        self.spatiolator = z.Spatiolator(self.layout, self.head.spatiolator.handle)

    def reload(self):
        world.gamepads.reload()
        self.listview.set_items(world.gamepads.gamepads)

    def gamepad_item_builder(self, item, context):
        return z.ContextButton(
            label=item.name,
            focus_parent=context['focus_parent'],
            actions=[
                ('gamepad', lambda: world.floaties.add(z.GamepadView(item))),
                ('pyobj', lambda: world.floaties.add(z.PyObjView(item))),
            ]
        )

    def drop(self):
        self.column.drop()
        self.listview.drop()
        self.head.drop()
        self.focus.drop()