class BoolEntityPreview:
    def __init__(self, entity, focus_parent=None):
        self.entity = entity
        self.button = z.ContextButton(
            label=f'bool: {self.entity.value}',
            focus_parent=focus_parent,
            actions=[
                ('view', lambda: world.floaties.add(
                    self.entity.view(self.entity))),
            ]
        )
        self.layout = self.button.layout

    def drop(self):
        self.button.drop()

