class ProjectView:
    def __init__(self, project):
        self.projects = world.classes.get_class(name='Projects')()
        self.project = project
        self.focus = world.focus.add_child(self)
        self.name = z.ReactiveValue(self.make_name())

        self.name_input = z.Input(text=self.project['name'] or '',
                                          focus_parent=self.focus)
        self.name_input.submitted.connect(self.on_name_submitted)
        actions = [
            ('folder', self.folder_triggered),
        ]
        self.actions_panel = z.ActionsPanel(actions, self.focus)
        self.head = z.Flex(children=[
            z.FlexChild(self.name_input.layout),
            z.FlexChild(self.actions_panel.layout)
        ])

        self.column = z.Flex([z.FlexChild(self.head.layout)], axis='y', xalign='largest')

        self.layout = self.column.layout

    def folder_triggered(self):
        folder = self.projects.ensure_folder(self.project)
        world.floaties.add(z.FolderView(folder))

    def on_name_submitted(self):
        value = self.name_input.text
        self.projects.update_project_name(self.project['id'], value)

    def make_name(self):
        return f'project: {self.project["name"]}'

    def drop(self):
        self.column.drop()
        self.head.drop()
        self.name_input.drop()
        self.actions_panel.drop()
        self.focus.drop()