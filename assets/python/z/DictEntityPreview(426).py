class DictEntityPreview:
    def __init__(self, entity, focus_parent=None):
        self.entity = entity
        self.button = z.ContextButton(
            label=f'dict with {len(self.entity.dict_items)} pairs',
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

