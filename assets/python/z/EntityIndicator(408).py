class EntityIndicator:
    def __init__(self):
        self.label = z.ContextButton(hud=True,
            focusable=False,
            label='entity',
            color=world.themes.theme.green[500],
            actions=[
                ('root', self.root_triggered),
                ('create', lambda: world.floaties.add(z.CreateEntityView())),
                ('morph', lambda: world.floaties.add(z.EntityMorphView())),
                ('sync-classes', lambda: z.ClassEntity.sync_z()),
            ]
        )
        world.apps['Hud'].top_panel.add(self.label)

    def root_triggered(self):
        entity = world.apps['Entities'].get_entity('2')
        world.floaties.add(entity.view(entity))

    def drop(self):
        world.apps['Hud'].top_panel.remove(self.label)
        self.label.drop()