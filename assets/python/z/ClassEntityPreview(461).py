class ClassEntityPreview:
    def __init__(self, entity, focus_parent=None):
        self.entity = entity
        name_display = self.entity.name if self.entity.name else f"Class {self.entity.id}"

        self.button = z.ContextButton(
            label=f"class: {name_display}",
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
