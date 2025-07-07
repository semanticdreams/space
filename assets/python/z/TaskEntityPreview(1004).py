class TaskEntityPreview:
    def __init__(self, entity, focus_parent=None):
        self.entity = entity

        self.button = z.ContextButton(
            label=f"task: {self.entity.label} ({self.entity.points})",
            focus_parent=focus_parent,
            font_scale=5,
            actions=[
                ('view', lambda: world.floaties.add(
                    self.entity.view(self.entity))),
            ]
        )
        self.layout = self.button.layout

    def drop(self):
        self.button.drop()
