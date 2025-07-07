class HudPanel:
    def __init__(self, color=None):
        self.children = []
        self.flexes = []
        self.row = z.Flex([], name='hud-panel', yalign='largest')

        self.padding = z.Padding(self.row.layout, (0.5, 0.5))

        self.top_rectangle = z.Rectangle(color=color, hud=True)
        self.top_stack = z.Stack([self.top_rectangle.layout, self.padding.layout], name='hud-panel')

        #self.layout = z.Layout(children=[self.top_stack.layout], measurer=self.measurer,
        #                               layouter=self.layouter, name='hud-panel')
        self.layout = self.top_stack.layout

    def update_children(self):
        self.row.set_children([
            z.FlexChild(
                x.layout, flex=self.flexes[i]
            )
            for i, x in enumerate(self.children)
        ])

    def add(self, child, flex=0):
        self.children.append(child)
        self.flexes.append(flex)
        self.update_children()

    def remove(self, child):
        self.flexes.pop(self.children.index(child))
        self.children.remove(child)
        self.update_children()

    def drop(self):
        self.layout.drop()
        self.top_stack.drop()
        self.top_rectangle.drop()
        self.padding.drop()
        self.row.drop()
