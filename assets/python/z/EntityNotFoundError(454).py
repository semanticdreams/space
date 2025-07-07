class EntityNotFoundError(Exception):
    def __init__(self, entity_id):
        super().__init__(f'Entity {entity_id} not found.')