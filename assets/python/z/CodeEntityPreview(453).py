class CodeEntityPreview:
    def __init__(self, entity, focus_parent=None):
        self.entity = entity
        name_display = self.entity.name if self.entity.name else f"Code {self.entity.id}"

        self.button = z.ContextButton(
            label=f"code: {name_display} ({self.entity.lang})",
            focus_parent=focus_parent,
            font_scale=5,
            actions=[
                ('view', lambda: world.floaties.add(
                    self.entity.view(self.entity))),
                ('run', lambda: self.entity.run()),
                ('edit', self.edit_code),
            ]
        )
        self.layout = self.button.layout

    def edit_code(self):
        new_code = world.dialogs.edit_string(self.entity.code_str).strip()
        if new_code != self.entity.code_str:
            self.entity.code_str = new_code
            self.entity.save()

    def drop(self):
        self.button.drop()
