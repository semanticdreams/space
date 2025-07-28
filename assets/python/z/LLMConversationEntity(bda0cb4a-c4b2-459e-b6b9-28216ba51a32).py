class LLMConversationEntity(z.Entity):
    def __init__(self, id, title, temperature, max_tokens):
        super().__init__('llm-conversation', id)
        self.title = title
        self.temperature = temperature
        self.max_tokens = max_tokens
        self.view = z.LLMConversationEntityView
        self.preview = z.LLMConversationEntityPreview
        self.color = [0.9521337793457223, 0.4603437382113039, 0.005419754066727123, 1.0]
        self.label = self.title

    @classmethod
    def create(cls, title='', temperature=0.6, max_tokens=1024, id=None):
        id = super().create(
            'llm-conversation',
            {'title': title, 'temperature': temperature, 'max_tokens': max_tokens},
            id=id
        )
        return cls(id, title)

    @classmethod
    def load(cls, id, data):
        return cls(id, data['title'], data.get('temperature', 0.6), data.get('max_tokens', 1024))

    def clone(self):
        return LLMConversationEntity.create(title=self.title, temperature=self.temperature, max_tokens=self.max_tokens)

    def dump_data(self):
        return {'title': self.title, 'temperature': self.temperature, 'max_tokens': self.max_tokens}

    def get_message_entities(self):
        messages = []
        n = self
        while True:
            edges = G.get_outgoing(n)
            entities = [z.Entity.get(x['target_id']) for x in edges]
            llm_message_entities = [x for x in entities if x.type == 'llm-message']
            if llm_message_entities:
                assert len(llm_message_entities) == 1
                target_entity = llm_message_entities[0]
                messages.append(target_entity)
                n = target_entity
            else:
                break
        return messages

    def send(self):
        world.aio.create_task(self.send_async())

    async def send_async(self):
        message_entities = self.get_message_entities()
        messages = []
        system = ''
        for e in message_entities:
            if e.role == 'system':
                system += '\n' + e.content
            else:
                messages.append({
                    'role': e.role,
                    'content': e.content
                })
        response = await world.apps['Claude'].send(
            messages=messages, system=system, max_tokens=self.max_tokens,
            temperature=self.temperature)
        for item in response.content:
            if item.type == 'text':
                new_entity = z.LLMMessageEntity.create(content=item.text,
                                                       role=response.role)
                G.add_node(new_entity)
                G.add_edge(e, new_entity)
        G.save()
