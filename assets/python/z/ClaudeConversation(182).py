import time
import json
import jinja2

macros = """
{% macro class(name) %}
  {{ world.classes.get_class_code(name=name)['code'] }}
{% endmacro %}
{% macro classes(names) %}
  {% for name in names %}
    {{ world.classes.get_class_code(name=name)['code'] }}
  {% endfor %}
{% endmacro %}
"""

class ClaudeConversation:
    def __init__(self, data):
        self.data = data

    def insert_message(self, content, role='user', num_tokens=None,
                       type='text', tool_use_id=None):
        message = {'role': role, 'content': content, 'claude_conversation_id': self.data['id'],
                   'num_tokens': num_tokens, 'type': type, 'tool_use_id': tool_use_id}
        with world.db:
            cur = world.db.execute(
                'insert into claude_conversation_messages (claude_conversation_id, role, content, num_tokens, type, tool_use_id, created_at)'
                ' values (?, ?, ?, ?, ?, ?, ?)', (message['claude_conversation_id'], message['role'], message['content'], message['num_tokens'], type, tool_use_id, time.time()))
        message['id'] = cur.lastrowid
        return message

    def add_tool(self, definition, code_id):
        with world.db:
            cur = world.db.execute(
                'insert into claude_conversation_tools (claude_conversation_id, definition, code_id)'
                ' values (?, ?, ?)',
                (self.data['id'], json.dumps(definition), code_id))
            id = cur.lastrowid
        return dict(id=id, definition=definition, code_id=code_id)

    def get_tools(self):
        tools = list(map(dict, world.db.execute(
                        'select * from claude_conversation_tools'
                        ' where claude_conversation_id = ?',
                        (self.data['id'],)).fetchall()))
        for tool in tools:
            tool['definition'] = json.loads(tool['definition'])
        return tools

    def set_temperature(self, value):
        with world.db:
            world.db.execute('update claude_conversations set temperature = ? where id = ?',
                             (value, self.data['id']))
        self.data['temperature'] = value

    def set_system(self, value):
        with world.db:
            world.db.execute('update claude_conversations set system = ? where id = ?',
                             (value, self.data['id']))
        self.data['system'] = value

    def set_max_tokens(self, value):
        with world.db:
            world.db.execute('update claude_conversations set max_tokens = ? where id = ?',
                             (value, self.data['id']))
        self.data['max_tokens'] = value

    def set_name(self, value):
        with world.db:
            world.db.execute('update claude_conversations set name = ? where id = ?',
                             (value, self.data['id']))
        self.data['name'] = value

    def set_message_role(self, message_id, role):
        assert role in ('user', 'assistant'), role
        with world.db:
            world.db.execute('update claude_conversation_messages set role = ? where id = ?',
                             (role, message_id))

    def set_message_content(self, message_id, content):
        with world.db:
            world.db.execute('update claude_conversation_messages set content = ? where id = ?',
                             (content, message_id))

    def set_message_num_tokens(self, message_id, num_tokens):
        with world.db:
            world.db.execute('update claude_conversation_messages set num_tokens = ? where id = ?',
                             (num_tokens, message_id))

    def clone(self):
        with world.db:
            cur = world.db.execute('insert into claude_conversations (name, created_at) values (?, ?)',
                                   (self.data['name'], time.time()))
            new_conversation_id = cur.lastrowid
            for message in self.messages:
                world.db.execute('insert into claude_conversation_messages'
                                 ' (claude_conversation_id, role, content, created_at) values (?, ?, ?, ?)',
                                 (new_conversation_id, message['role'], message['content'], time.time()))
        conversation = {**self.data, 'id': new_conversation_id}
        return z.ClaudeConversation(conversation)

    def render_messages(self, messages, template_args=None):
        result = []
        for x in messages:
            if x['type'] == 'tool_result':
                result.append(dict(role=x['role'], content=[dict(type='tool_result', tool_use_id=x['tool_use_id'], content=x['content'])]))
            else:
                result.append(dict(role=x['role'], content=jinja2.Template(macros + x['content']).render(world=world, **(template_args or {}))))
                if x['tool_uses']:
                    for use in json.loads(x['tool_uses']):
                        result.append(dict(role=x['role'], content=[dict(type='tool_use', id=use['id'], name=use['name'], input=use['input'])]))
        return result

    def add_tool_use(self, message_id, tool_use_id, name, input):
        message = self.get_message(message_id)
        tool_uses = []
        if message['tool_uses'] is not None:
            tool_uses = json.loads(message['tool_uses'])
        tool_uses.append(dict(id=tool_use_id, name=name, input=input))
        with world.db:
            world.db.execute('update claude_conversation_messages'
                ' set tool_uses = ? where id = ?',
                (json.dumps(tool_uses), message_id))

    async def send(self, template_args=None):
        messages = self.render_messages(self.get_messages(), template_args=template_args)
        tools = self.get_tools()
        response = await world.apps['Claude'].send(
                messages=messages, system=self.data['system'],
                tools=[x['definition'] for x in tools],
                max_tokens=self.data['max_tokens'],
                temperature=self.data['temperature'])
        message = None
        for item in response.content:
            if item.type == 'text':
                message = self.insert_message(item.text, response.role,
                    response.usage.output_tokens)
            elif item.type == 'tool_use':
                self.add_tool_use(message['id'], item.id, item.name, item.input)
                tool = one([x for x in tools if x['definition']['name'] == item.name])
                code = world.codes.get_code(tool['code_id'])
                kernel = world.kernels.ensure_kernel(code['kernel'])
                kernel.send_code(code, catch_errors=True)
                func = kernel.env.pop(code['name'])
                result = func(**item.input)
                self.insert_message(str(result) if result is not None else None, 'user',
                                    type='tool_result', tool_use_id=item.id)
                if result is not None:
                    return await self.send(template_args)
            else:
                assert False, item.type
        return message

    async def auto_name(self):
        messages = self.get_messages()
        assert messages
        #msg = 'SYSTEM: {self.data["system"]}\nMESSAGES: {"\n".join((x['content'] for x in [messages[0]]))}'
        msg = 'SYSTEM: {}\nMESSAGES: {}'.format(self.data['system'], '\n'.join((x['content'] for x in [messages[0]])))
        system = ('You generate short (max 8 words) titles of entire conversations with you.')
        resp = await world.apps['Claude'].send(
            [{'role': 'user', 'content': msg},
             {'role': 'assistant', 'content': 'The title is:'}],
            system=system, max_tokens=100, temperature=0.6)
        value = '> ' + resp.content[0].text.strip().strip('"')
        self.set_name(value)
        return value

    def update_num_tokens(self, message_id):
        # need to retrieve message, prep it like in send,
        # then send it to world.apps['Claude'].count_tokens same way like send
        # and use result to update db with self.set_message_num_tokens
        pass

    def set_archived(self):
        self.data['archived_at'] = time.time()
        with world.db:
            world.db.execute('update claude_conversations set archived_at = ? where id = ?',
                             (self.data['archived_at'], self.data['id']))

    def archive_message(self, message_id):
        with world.db:
            world.db.execute('update claude_conversation_messages set archived_at = ? where id = ?',
                             (time.time(), message_id))
