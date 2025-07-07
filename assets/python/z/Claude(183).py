import os
import anthropic
import pypika

client = anthropic.AsyncAnthropic(api_key=os.getenv('ANTHROPIC_API_KEY'))
model = 'claude-3-7-sonnet-latest'

class Claude:
    def get_conversations(self):
        return list(map(z.ClaudeConversation, map(dict, world.db.execute(
            'select * from claude_conversations'
            ' where archived_at is null'
            ' order by created_at desc'
        ).fetchall())))

    def create_conversation(self):
        with world.db:
            cur = world.db.execute('insert into claude_conversations (created_at) values (?)', (time.time(),))
        return self.get_conversation(cur.lastrowid)

    def get_conversation(self, id=None, name=None):
        t = pypika.Table('claude_conversations')
        q = pypika.Query.from_(t).select('*')
        if id is not None:
            q = q.where(t.id == id)
        if name is not None:
            q = q.where(t.name == name)
        q = q.limit(1)
        return z.ClaudeConversation(dict(one(world.db.execute(str(q)).fetchall())))

    async def send(self, messages, system=None, max_tokens=None, temperature=None, tools=None):
        args = {}
        if system:
            args['system'] = system
        if max_tokens:
            args['max_tokens'] = max_tokens
        if temperature is not None:
            args['temperature'] = temperature
        if tools is not None:
            args['tools'] = tools

        for message in messages:
            message['role'] = message.get('role', 'user')

        print(tools)
        response = await client.messages.create(model=model, messages=messages, **args)
        return response

    async def count_tokens(self, messages, system=None, max_tokens=None, temperature=None, tools=None):
        args = {}
        if system:
            args['system'] = system
        if max_tokens:
            args['max_tokens'] = max_tokens
        if temperature is not None:
            args['temperature'] = temperature
        if tools is not None:
            args['tools'] = tools

        for message in messages:
            message['role'] = message.get('role', 'user')

        response = await client.messages.count_tokens(model=model, messages=messages, **args)
        return response

    def drop(self):
        pass
