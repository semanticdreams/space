class TasksView:
    def __init__(self, focus_parent=None):
        self.tasks = world.apps.ensure_app('Tasks')
        self.focus = focus_parent.add_child(self) if focus_parent else world.focus.add_child(self)

        self.tree = z.TreeView(
            top_level_items=self.build_tree_items(),
            builder=self.tree_view_item_builder,
            focus_parent=self.focus
        )
        self.layout = self.tree.layout

    def build_tree_items(self):
        items = []
        stack = [(None, None)]  # (task_data, parent_item)

        while stack:
            task_data, parent_item = stack.pop()

            if task_data is None:
                tasks = self.tasks.get_root_tasks()
                stack.extend((task, None) for task in reversed(tasks))
            else:
                item = z.TreeViewItem(item=task_data)
                if parent_item:
                    parent_item.children.append(item)
                else:
                    items.append(item)

                children = self.tasks.get_child_tasks(task_data['id'])
                if children:
                    stack.extend((child, item) for child in reversed(children))

        return items

    def tree_view_item_builder(self, task_data, context):
        return z.ContextButton(
            label=f"{task_data['label']} ({task_data['points']})",
            focus_parent=context['focus_parent'],
            color=world.themes.theme.dialog_background_color,
            foreground_color=world.themes.theme.gray[100],
            #padding_insets=(0.5, 0.5),
            actions=[
                ('-', lambda: None),
                ('done', lambda: self.done(task_data)),
                ('edit label', lambda: self.edit_task_label(task_data)),
                ('edit points', lambda: self.edit_task_points(task_data)),
                ('add subtask', lambda: self.add_subtask(task_data)),
                ('archive', lambda: self.archive(task_data)),
            ]
        )

    def done(self, task):
        self.tasks.set_task_done(task['id'], True)
        self.refresh()

    def archive(self, task):
        self.tasks.set_task_archived(task['id'], True)
        self.refresh()

    def edit_task_label(self, task):
        input = z.Input(text=task['label'], multiline=True)
        def on_submit():
            self.tasks.update_task_label(task['id'], input.text)
            self.refresh()
        input.submitted.connect(on_submit)
        world.floaties.add(input)

    def edit_task_points(self, task):
        input = z.Input(text=str(task['points']), multiline=True)
        def on_submit():
            try:
                points = int(input.text)
                self.tasks.update_task_points(task['id'], points)
                self.refresh()
            except ValueError:
                pass
        input.submitted.connect(on_submit)
        world.floaties.add(input)

    def add_subtask(self, parent):
        input = z.Input(multiline=True)
        def on_submit():
            self.tasks.create_task(input.text, 1, parent['id'])
            self.refresh()
        input.submitted.connect(on_submit)
        world.floaties.add(input)

    def refresh(self):
        self.tree.set_top_level_items(self.build_tree_items())
        world.apps['TasksIndicator'].update_label()

    def drop(self):
        self.tree.drop()
        if self.focus:
            self.focus.drop()
