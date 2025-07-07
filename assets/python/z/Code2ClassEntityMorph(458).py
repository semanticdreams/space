import re
class Code2ClassEntityMorph:
    def __init__(self, source_entity):
        self.source_entity = source_entity

    def scrape_class_name(self, text):
        m = re.search('class\\s+(\\w+)\\s*(\\(.*\\))?:', text)
        return m.group(1) if m else None

    def __call__(self):
        name = self.source_entity.name or self.scrape_class_name(self.source_entity.code_str)
        class_entity = z.ClassEntity.create(name=name, code_str=self.source_entity.code_str)
        self.source_entity.delete()
        class_entity.update_id(self.source_entity.id)
        return class_entity
