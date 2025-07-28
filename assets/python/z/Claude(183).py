import os
import anthropic
import pypika

client = anthropic.AsyncAnthropic(api_key=os.getenv('ANTHROPIC_API_KEY'))
model = 'claude-3-7-sonnet-latest'

class Claude:
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
