import math


class ListView:
    def __init__(self, items=None, builder=None, num_per_page=10, focus_parent=None,
                 name='list-view', show_head=False, paginate=True):
        self.name = name
        self.items = items or []
        self.show_head = show_head
        self.paginate = paginate
        self.builder = builder or self.default_builder

        self.objs = []

        self.focus = focus_parent.add_child(obj=self, on_changed=self.on_focus_changed) \
                if focus_parent else world.focus.add_child(self, self.on_focus_changed)

        if self.show_head:
            self.head = z.ContextButton(label=name, focus_parent=self.focus, actions=[
                ('custom builder', self.custom_builder_triggered),
            ], color=(1, 0.5, 1, 1))

        self.column = z.Flex([], axis='y', xalign='largest')
        self.column_focus = self.focus.add_child(self.column)

        if self.paginate:
            self.pagination = z.Pagination(len(self.items), focus_parent=self.focus, per_page=num_per_page)
            self.pagination.page_changed.connect(self.on_page_changed)

        row_items = []
        if self.show_head:
            row_items.append(z.FlexChild(self.head.layout))

        row_items.append(z.FlexChild(self.column.layout))

        self.spacer = z.Spacer()
        row_items.append(z.FlexChild(self.spacer.layout, flex=1))

        if self.paginate:
            row_items.append(z.FlexChild(self.pagination.layout))

        self.row = z.Flex(row_items, axis='y', xalign='largest')

        self.layout = self.row.layout

        if self.show_head:
            self.spatiolator = z.Spatiolator(self.layout, self.head)

        if self.paginate:
            self.pagination.set_page(0)
        else:
            self.update_items()

    def default_builder(self, item, context):
        return z.ContextButton(
            label=str(item)[:100],
            focus_parent=context['focus_parent'],
            actions=[
                ('pyobj', lambda: world.floaties.add(z.PyObjView(item))),
            ]
        )

    def custom_builder_triggered(self):
        raise Exception('not implemented: need SetBuilderView')
        world.floaties.add(z.CustomClassView(lambda cls: self.set_builder(cls)))

    def set_builder(self, builder):
        self.builder = builder
        if self.paginate:
            self.pagination.set_page(self.pagination.current_page, force_update=True)
        else:
            self.update_items()

    def on_focus_changed(self, value):
        pass

    def set_items(self, items):
        self.items = items
        if self.paginate:
            self.pagination.set_num_items(len(items))
        else:
            self.update_items()

    def set_name(self, name):
        self.name = name
        if self.show_head:
            self.head.set_label(self.name)

    def drop_objs(self):
        for obj in self.objs:
            obj.drop()
        self.objs.clear()

    def update_items(self):
        self.column.clear_children()
        self.drop_objs()
        self.objs = [self.builder(item, context=dict(focus_parent=self.column_focus)) for item in self.items]
        self.column.set_children([
            z.FlexChild(obj.layout) for obj in self.objs
        ])

    def on_page_changed(self, data):
        self.column.clear_children()
        self.drop_objs()
        start_index, stop_index = data['slice']
        current_items = self.items[start_index:stop_index]
        self.objs = [self.builder(item, context=dict(focus_parent=self.column_focus)) for item in current_items]
        self.column.set_children([
            z.FlexChild(obj.layout) for obj in self.objs
        ])

    def drop(self):
        if self.focus:
            self.focus.disconnect()
        self.row.drop()
        self.spacer.drop()
        self.column.drop()
        self.drop_objs()
        if self.column_focus:
            self.column_focus.drop()
        if self.show_head:
            self.head.drop()
        if self.paginate:
            self.pagination.drop()
        if self.focus:
            self.focus.drop()
