class SqliteView:
    def __init__(self):
        self.focus = world.focus.add_child(self)
        self.name = z.ReactiveValue('sqlite-browser')
        actions = [
            ('create database', self.create_database_triggered),
            ('open database', self.open_database_triggered),
        ]
        self.buttons = []
        for name, func in actions:
            button = z.Button(name, focus_parent=self.focus)
            button.clicked.connect(lambda f,i,d: func())
            self.buttons.append(button)

        self.column = z.Flex(children=[z.FlexChild(x) for x in self.buttons],
                                     axis='y', xalign='largest')
        self.layout = self.column.layout

    def create_database_triggered(self):
        picker = world.classes['FileSystemView']()
        picker.submitted.connect(lambda path: world.floaties.add(SqliteDatabaseView(path)))
        world.floaties.add(picker)

    def open_database_triggered(self):
        picker = world.classes['FileSystemView']()
        picker.submitted.connect(lambda path: world.floaties.add(SqliteDatabaseView(path)))
        world.floaties.add(picker)

    def drop(self):
        self.column.drop()
        for button in self.buttons:
            button.drop()
        self.focus.drop()