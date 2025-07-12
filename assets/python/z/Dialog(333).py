class Dialog:
    def __init__(self, title, child, on_inspector=None, actions=None, color=None):
        self.child = child
        if on_inspector:
            self.on_inspector = on_inspector
        self.closed = z.Signal()
        self.inspector = None
        if actions is None:
            actions = []
            #actions.extend([
            #    ('icon:code', self.on_inspector),
            #    ('icon:close', self.closed.emit),
            #])
        self.title_bar = z.TitleBar(title, actions=actions, color=color)

        self.padding = z.Padding(self.child.layout, (0.5, 0.5))


        self.rectangle = z.Rectangle(color=world.themes.theme.dialog_background_color)

        self.stack = z.Stack([self.rectangle.layout, self.padding.layout], name='dialog')

        self.column = z.Flex([
            z.FlexChild(self.title_bar.layout),
            z.FlexChild(self.stack.layout, flex=1)
        ],
            axis='y', xalign='largest', yspacing=0)

        #self.sides = [z.Rectangle(color=world.themes.theme.dialog_background_color)
        #              for _ in range(5)]

        #self.cuboid = z.CuboidLayout(objs=[self.column, *self.sides])
        #self.layout = self.cuboid.layout
        self.layout = self.column.layout

        self.spatiolator = z.Spatiolator(self.layout, self.title_bar.label)

    #def on_inspector(self):
    #    self.inspector = z.PyObjView(self.child, reloadable=False)
    #    world.floaties.add(self.inspector)

    def reset_child(self, child):
        self.padding.layout.clear_children()
        self.child.drop()
        self.child = child
        #if self.inspector:
        #    self.inspector.set_obj(self.child)
        self.padding.layout.add_child(child.layout)
        self.layout.mark_measure_dirty()

    def drop(self):
        #self.cuboid.drop()
        #for side in self.sides:
        #    side.drop()
        self.column.drop()
        self.stack.drop()
        self.rectangle.drop()
        self.padding.drop()
        self.title_bar.drop()
