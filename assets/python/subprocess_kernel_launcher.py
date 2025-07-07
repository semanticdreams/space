import zmq
import os
import sys
import json
import traceback
from io import StringIO


class JSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime):
            return {"date": obj.isoformat()}
        return json.JSONEncoder.default(self, obj)


def parse_json_obj(obj):
    for key, value in obj.items():
        if isinstance(value, dict) and 'date' in value:
            try:
                obj[key] = datetime.fromisoformat(value['date'])
            except ValueError:
                pass
    return obj


class SubprocessKernelLauncher:
    def __init__(self):
        self.env = dict()

        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.REP)
        self.socket.bind("tcp://127.0.0.1:*")

        self.endpoint = self.socket.getsockopt(zmq.LAST_ENDPOINT).decode('utf-8')

        self.connection_file = os.environ.pop('KERNEL_CONNECTION_FILE')
        with open(self.connection_file, 'w') as f:
            json.dump(dict(endpoint=self.endpoint), f)

    def run(self):
        while True:
            message = self.socket.recv_json()

            if message == "STOP":
                break

            output = StringIO()  # Buffer to capture output
            sys.stdout = output  # Redirect stdout to the buffer
            sys.stderr = output  # Redirect stderr to the same buffer
            error = None

            registers = message['registers']

            self.env['_registers'] = json.loads(registers, object_hook=parse_json_obj)

            try:
                exec(message['code'], self.env)
                registers = json.dumps(self.env['_registers'], cls=JSONEncoder)
            except SystemExit:
                error = traceback.format_exc()
            except Exception:
                if message['catch_errors']:
                    error = traceback.format_exc()
                else:
                    raise

            sys.stdout = sys.__stdout__  # Restore stdout
            sys.stderr = sys.__stderr__  # Restore stderr

            response = {
                'output': output.getvalue(),
                'error': error,
                'registers': registers
            }

            self.socket.send_json(response)

        self.socket.close()
        self.context.term()

if __name__ == '__main__':
    SubprocessKernelLauncher().run()

