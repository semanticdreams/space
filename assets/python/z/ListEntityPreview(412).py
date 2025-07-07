class ListEntityPreview:
    def __init__(self, entity, focus_parent=None):
        self.entity = entity
        self.button = z.ContextButton(
            label=f'list with {len(self.entity.list_items)} items',
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
