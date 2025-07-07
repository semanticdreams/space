class JsonEntityPreview:
    def __init__(self, entity, focus_parent=None):
        self.entity = entity
        summary = json.dumps(self.entity.get_data(), separators=(',', ':'), ensure_ascii=False)
        summary = summary[:40] + '…' if len(summary) > 40 else summary

        self.button = z.ContextButton(
            label=f'json: {summary}',
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

