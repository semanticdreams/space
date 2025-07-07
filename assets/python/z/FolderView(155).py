class FolderView:
    def __init__(self, folder):
        self.folder = folder
        self.children = world.folders.get_children(self.folder['id'])
        self.name = z.ReactiveValue(self.make_name())
        self.focus = world.focus.add_child(self)
        self.name_input = z.Input(text=self.folder['name'] or '', focus_parent=self.focus)
        self.name_input.submitted.connect(self.name_submitted)
        actions = [
            ('create child', self.create_child_folder_triggered),
            ('delete', self.delete_triggered),
            ('reload', self.reload_children),
        ]
        self.actions_panel = z.ActionsPanel(actions, self.focus)
        self.row = z.Flex(children=[
            z.FlexChild(self.name_input.layout),
            z.FlexChild(self.actions_panel.layout),
        ])

        self.list_view = z.ListView(self.children, focus_parent=self.focus, show_head=False, builder=self.item_builder)

        self.column = z.Flex(xalign='largest', axis='y', children=[
            z.FlexChild(self.row.layout),
            z.FlexChild(self.list_view.layout)
        ])
        self.layout = self.column.layout

    def make_name(self):
        return f'folder: {self.folder["name"]} ({self.folder["id"]})'

    def item_builder(self, item, context):
        label = str(item)
        actions = []
        locator = world.locators.get_locator(item['locator_id'])
        label = f'({locator["item_type"]}, {locator["item_id"]}): '
        if locator['item_type'] == 'folder':
            folder = world.folders.get_folder(locator['item_id'])
            actions.append(('get', lambda item=item: world.floaties.add(z.FolderView(folder))))
            label += folder['name'] or ''
        elif locator['item_type'] == 'note':
            note = world.notes.get_note(locator['item_id'])
            actions.append(('get', lambda: world.floaties.add(z.EditNoteView(note))))
            label += z.truncate_string_with_ellipsis(note['text'], 10)
        return z.ContextButton(
            label=label, focus_parent=context['focus_parent'],
            actions=actions)

    def reload_children(self):
        self.children = world.folders.get_children(self.folder['id'])
        self.list_view.set_items(self.children)

    def create_child_folder_triggered(self):
        child_folder = world.folders.create_child_folder(self.folder['id'])
        self.reload_children()

    def delete_triggered(self):
        world.folders.delete_folder(self.folder['id'])
        world.floaties.drop_obj(self)

    def name_submitted(self):
        self.folder['name'] = self.name_input.text
        world.folders.update_name(self.folder['id'], self.folder['name'])
        self.name.set(self.make_name())

    def drop(self):
        self.column.drop()
        self.row.drop()
        self.list_view.drop()
        self.name_input.drop()
        self.actions_panel.drop()
        self.focus.drop()