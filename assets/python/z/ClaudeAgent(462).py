class ClaudeAgent:
    def __init__(self):
        conv = world.apps['Claude'].create_conversation()
        conv.set_system('you are a helpful assistant')
        conv.set_name('entity-assistant-test')
        user_message_entity = z.StringEntity.load(5)
        user_message = user_message_entity.value
        conv.insert_message(user_message, 'user')
        resp = await conv.send()
        assistant_message = resp['content']
        result_entity = z.StringEntity.create(assistant_message)
        graph = z.GraphEntity.load(1)
        graph.add_node(result_entity)
        graph.add_edge(user_message_entity, result_entity)
        graph.save()