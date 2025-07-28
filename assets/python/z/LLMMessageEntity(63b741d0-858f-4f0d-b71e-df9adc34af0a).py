class LLMMessageEntity(z.Entity):
    def __init__(self, id, content='', role=''):
        super().__init__('llm-message', id)
        self.content = content
        self.role = role
        self.view = z.LLMMessageEntityView
        self.preview = z.LLMMessageEntityPreview
        self.color = [0.5381836070451079, 0.9754526587123803, 0.8095292012151875, 1.0]
        self.label = self.content

    @classmethod
    def create(cls, content='', role='', id=None):
        id = super().create('llm-message', {'content': content, 'role': role}, id=id)
        return cls(id, content, role)

    @classmethod
    def load(cls, id, data):
        return cls(id, data['content'], data['role'])

    def clone(self):
        return LLMMessageEntity.create(value=self.value)

    def dump_data(self):
        return {'content': self.content, 'role': self.role}
