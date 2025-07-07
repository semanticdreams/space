class TasksIndicator:
    def __init__(self):
        self.tasks = world.apps.ensure_app('Tasks')
        self.label = z.ContextButton(hud=True,
            focusable=False,
            label='',#TODO self.make_label(),
            color=world.themes.theme.yellow[800],
            actions=[
                ('open', lambda: world.floaties.add(z.TasksView())),
            ]
        )
        world.apps['Hud'].top_panel.add(self.label)

    def update_label(self):
        self.label.set_label(self.make_label())

    def make_label(self):
        return f'{self.tasks.get_total_points_last_24h()}|{self.tasks.get_total_points_last_7d()}|{self.tasks.get_total_points()}'

    def drop(self):
        world.apps['Hud'].top_panel.remove(self.label)
        self.label.drop()
