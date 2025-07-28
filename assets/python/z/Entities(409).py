import uuid
import json
import pypika


class Entities:
    type_class_map = {
        'int': z.IntEntity,
        'list': z.ListEntity,
        'float': z.FloatEntity,
        'string': z.StringEntity,
        'bool': z.BoolEntity,
        'dict': z.DictEntity,
        'json': z.JsonEntity,
        'tag': z.TagEntity,
        'graph': z.GraphEntity,
        'code': z.CodeEntity,
        'class': z.ClassEntity,
        'task': z.TaskEntity,
        'workspace': z.Workspace,
        'workspaces': z.Workspaces,
        'dynamic-graph': z.DynamicGraphEntity,
        'shader': z.ShaderEntity,
        'fs-folder': z.FSFolderEntity,
        'llm-message': z.LLMMessageEntity,
        'llm-conversation': z.LLMConversationEntity,
    }

    morphs = {
        'string': [
            ('code', z.String2CodeEntityMorph),
            ('dict', z.String2DictEntityMorph),
            ('json', z.String2JsonEntityMorph),
            ('task', z.String2TaskEntityMorph),
            ('llm-message', z.String2LLMMessageEntityMorph),
            ('llm-conversation', z.String2LLMConversationEntityMorph),
        ],
        'code': [
            ('class', z.Code2ClassEntityMorph)
        ],
        'dict': [
            ('json', z.Dict2JsonEntityMorph),
        ],
    }

    def get_entity_class(self, type):
        return self.type_class_map[type]

    def get_entity(self, entity_id):
        assert isinstance(entity_id, str)
        entities = world.db.execute('select * from entities where id = ?', (str(entity_id),)).fetchall()
        if not entities:
            raise z.EntityNotFoundError(entity_id)
        data = dict(entities[0])
        cls = self.get_entity_class(data['type'])
        return cls.load(str(entity_id), json.loads(data['data']))

    def get_entities(self, type=None):
        t = pypika.Table('entities')
        q = pypika.Query.from_(t).select('*')
        if type is not None:
            q = q.where(t.type == type)
        entities = world.db.execute(str(q)).fetchall()
        return [self.get_entity_class(x['type']).load(
            str(x['id']),
            json.loads(x['data']))
            for x in entities]

    #def get_entities(self):
    #    entities = world.db.execute('select * from entities').fetchall()
    #    return [self.get_entity_class(x['type']).load(x['item_id']) for x in entities]

    def delete_entity(self, entity_id):
        with world.db:
            world.db.execute('delete from entities where id = ?', (str(entity_id),))

    #def find_entity(self, type, item_id):
    #    return dict(world.db.execute('select * from entities where type = ? and item_id = ?', (type, item_id)).fetchall()[0])

    def create_entity(self, type, data=None, id=None):
        id = str(uuid.uuid4()) if id is None else id
        now = time.time()
        with world.db:
            world.db.execute(
                'insert into entities (id, type, data, created_at, updated_at)'
                ' values (?, ?, ?, ?, ?)', (id, type, data, now, now))
        return id

    def update_id(self, old_id, new_id):
        assert isinstance(new_id, str)
        with world.db:
            world.db.execute(
                'update entities set id = ?, updated_at = ? where id = ?',
                (new_id, time.time(), old_id))

    #def ensure_entity(self, type, item_id):
    #    result = world.db.execute('select * from entities where type = ? and item_id = ?', (type, item_id)).fetchall()
    #    if result:
    #        entity = dict(result[0])
    #    else:
    #        entity_id = self.create_entity(type, item_id)
    #        entity = dict(id=entity_id,
    #                       type=type, item_id=item_id)
    #    return entity

    #def discard_entity(self, type, item_id):
    #    with world.db:
    #        world.db.execute('delete from entities where type = ? and item_id = ?', (type, item_id))

    def drop(self):
        pass
