class AgentOne:
    def __init__(self):
        pass

    async def submit(self, text):
        conv = world.apps['Claude'].create_conversation()
        conv.set_system('you are a python programmer.')
        conv.set_name('agent-one')
        conv.add_tool({
            'name': 'change_clear_color',
            'description': 'Changes the clear color of the application and persists it in the settings.',
            'input_schema': {
                "type": "object",
                "properties": {
                    "color": {
                        "type": "array",
                        "description": "A list of four float values representing the RGBA color. Each value should be between 0.0 and 1.0. For example, [1.0, 0.0, 0.0, 1.0] is red with full opacity.",
                        "items": {
                            "type": "number",
                            "minimum": 0.0,
                            "maximum": 1.0
                        },
                        "minItems": 4,
                        "maxItems": 4
                    }
                },
                "required": ["color"]
            }
        })
        conv.insert_message(text, 'user')
        resp = await conv.send()
        return resp
