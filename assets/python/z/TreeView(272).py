class TreeView:
    def __init__(self, top_level_items=None, builder=None,
                 indentation=2.0,
                 focus_parent=world.focus):
        self.top_level_items = top_level_items or []
        self.builder = builder or self.default_builder
        self.indentation = indentation
        self.focus = focus_parent.add_child(self)
        self.objs = []
        self.items = []
        self.layout = z.Layout(
            name='tree-view', measurer=self.measurer,
            layouter=self.layouter)
        self.update_items()

    def default_builder(self, item, context):
        return z.ContextButton(
            label=str(item)[:100],
            focus_parent=context['focus_parent']
        )

    def set_top_level_items(self, items):
        self.top_level_items = items
        self.update_items()

    def update_items(self):
        self.clear()
        stack = [(item, 0) for item in reversed(self.top_level_items)]
        while stack:
            tree_item, level = stack.pop()
            self.items.append((tree_item, level))
            item_obj = self.builder(tree_item.item, {'focus_parent': self.focus, 'level': level})
            obj = z.TreeViewRow(self, tree_item, item_obj)
            self.objs.append(obj)
            if hasattr(tree_item, 'children') and tree_item.expanded:
                stack.extend((child, level + 1) for child in reversed(tree_item.children))
        self.layout.set_children([x.layout for x in self.objs])

    def measurer(self):
        if self.layout.children:
            [child.measurer() for child in self.layout.children]
            self.layout.measure[0] = max(child.measure[0] + self.indentation * level for child, (_, level) in zip(self.layout.children, self.items))
            self.layout.measure[1] = sum(child.measure[1] for child in self.layout.children)
            self.layout.measure[2] = max(child.measure[2] for child in self.layout.children)

    def layouter(self):
        if not self.layout.children:
            return
        y_offset = 0
        for i, child in enumerate(self.layout.children):
            child.depth_offset_index = self.layout.depth_offset_index

            level = self.items[i][1]
            x_offset = level * self.indentation

            child.size = child.measure.copy()
            child.size[0] = self.layout.size[0] - x_offset
            
            child.position = self.layout.position + [x_offset, 0, 0]
            child.position[1] = self.layout.position[1] + self.layout.size[1] - y_offset - child.size[1]
            child.rotation = self.layout.rotation.copy()
            child.layouter()
            
            y_offset += child.size[1]

    def clear(self):
        self.layout.clear_children()
        for obj in self.objs:
            obj.drop()
        self.objs.clear()
        self.items.clear()

    def drop(self):
        self.layout.drop()
        for obj in self.objs:
            obj.drop()
        self.objs.clear()
        if self.focus:
            self.focus.drop()
