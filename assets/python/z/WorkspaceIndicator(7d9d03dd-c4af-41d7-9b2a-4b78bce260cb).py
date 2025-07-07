class WorkspaceIndicator:
    def __init__(self):
        self.workspaces = world.apps['Workspaces']
        actions = [(x.name, lambda x=x: self.set_workspace(x))
                    for x in self.workspaces.workspaces.values()]
        self.label = z.ContextButton(
            hud=True,
            focusable=False,
            label=self.get_label(),
            color=world.themes.theme.indigo,
            actions=actions
        )
        world.apps['Hud'].top_panel.add(self.label)

        self.workspaces.workspace_changed.connect(self.on_workspace_changed)

    def get_label(self):
        w = self.workspaces.active_workspace
        name = w.name if w else 'None'
        return f'ws: {name:10}'

    def set_workspace(self, workspace):
        self.workspaces.set_workspace(workspace.name)

    def on_workspace_changed(self, old, new):
        self.label.set_label(self.get_label())

    def drop(self):
        world.apps['Hud'].top_panel.remove(self.label)
        self.label.drop()
        self.workspaces.workspace_changed.disconnect(self.on_workspace_changed)
