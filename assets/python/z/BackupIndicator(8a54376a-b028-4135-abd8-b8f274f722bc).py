from util import backup_db
class BackupIndicator:
    def __init__(self):
        self.label = z.ContextButton(hud=True,
            focusable=False,
            label='backup',
            color=world.themes.theme.blue[800],
            actions=[
                ('backup', self.backup),
            ]
        )
        world.apps['Hud'].top_panel.add(self.label)

    def backup(self):
        backup_db()

    def drop(self):
        world.apps['Hud'].top_panel.remove(self.label)
        self.label.drop()