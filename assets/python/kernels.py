import zmq
import sys
import re
import io
import os
import ast
import uuid
import json
import time
import shlex
import traceback
import subprocess
import pypika
from contextlib import contextmanager

from util import parse_json_obj, JSONEncoder


@contextmanager
def redirected(out=sys.stdout, err=sys.stderr):
    saved = sys.stdout, sys.stderr
    sys.stdout, sys.stderr = out, err
    try:
        yield
    finally:
        sys.stdout, sys.stderr = saved


class ReactiveStringIO(io.StringIO):
    def __init__(self, on_write, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._on_write = on_write

    def write(self, data):
        result = super().write(data)
        if self._on_write:
            self._on_write(data)
        return result


class InternalEnv(dict):
    def __getitem__(self, key):
        if key in self:
            return super().__getitem__(key)
        if key in world.classes.names:
            return world.classes[key]
        return super().__getitem__(key)


class InternalKernel:
    def __init__(self):
        self.id = 0
        self.name = 'internal'
        self.cmd = None
        self.cwd = None
        self.env = self.load_env()

    def load_env(self):
#        return InternalEnv()
        return {}

    def send_code(self, code, catch_errors=False, callback=None,
                  registers=None, on_write_out=None, on_write_error=None):
        out, err = ReactiveStringIO(on_write_out), ReactiveStringIO(on_write_error)
        with redirected(out=out, err=err):
            out.flush; err.flush()
            if code['lang'] not in ('py', 'hy'):
                raise Exception('unknown code lang')
            if not code.get('name'):
                code['name'] = '<unnamed>'
            if not code.get('id'):
                code['id'] = None

            self.env['_registers'] = registers

            code_code = code['code']
            coro = None

            try:
                if code.get('lang') == 'py':
                    compiled = compile(code_code, f"{code['name']} ({code['id']})", 'exec',
                                       flags=ast.PyCF_ALLOW_TOP_LEVEL_AWAIT)
                    coro = eval(compiled, self.env)
                elif code['lang'] == 'hy':
                    import hy
                    hy.eval(hy.read_many(code['code']), self.env)
            except Exception as e:
                if catch_errors:
                    print(traceback.format_exc(), file=err)
                else:
                    raise
        if coro:
            async def cb():
                with redirected(out=out, err=err):
                    try:
                        await coro
                    except:
                        if catch_errors:
                            print(traceback.format_exc(), file=err)
                        else:
                            raise
                result = {'output': out.getvalue(), 'error': err.getvalue(),
                          'registers': self.env['_registers']}
                return result
            world.aio.create_task(cb(), callback)
        else:
            result = {'output': out.getvalue(),
                      'error': err.getvalue(),
                      'registers': self.env['_registers']}
            if callback:
                callback(result)
            return result

    def drop(self):
        pass


class SubprocessKernel:
    def __init__(self, id, name, cmd, cwd, connection_file):
        self.id = id
        self.name = name
        self.cmd = cmd
        self.cwd = cwd
        self.connection_file = connection_file

        self.process = None
        self.callback = None

        self.status = 'init'

        self.changed = util.Signal()

    def update_data(self, name=None, cmd=None, cwd=None):
        t = pypika.Table('kernels')
        q = pypika.Query.update(t)
        if name is not None:
            q = q.set(t.name, name)
            self.name = name
        if cmd is not None:
            q = q.set(t.cmd, cmd)
            self.cmd = cmd
        if cwd is not None:
            q = q.set(t.cmd, cwd)
            self.cwd = cwd
        q = q.where(t.id == self.id)
        with world.db:
            world.db.execute(str(q))

    def delete_kernel(self):
        assert self.process is None
        with world.db:
            world.db.execute('delete from kernels where id = ?',
                             (self.id,))
        del world.kernels.kernels[self.id]

    def send_code(self, code, callback, registers=None, catch_errors=True):
        assert self.status == 'started', f'status is {self.status}'
        self.callback = callback
        message = {'code': code['code'], 'registers': json.dumps(registers, cls=JSONEncoder),
                   'catch_errors': catch_errors}
        self.socket.send_json(message)

    async def send_code_async(self, code, registers=None, catch_errors=True):
        future = world.aio.loop.create_future()
        def callback(result):
            future.set_result(result)
        self.send_code(code, callback, registers, catch_errors)
        return await future

    def poll(self):
        socks = dict(self.poller.poll(0))
        if self.socket in socks and socks[self.socket] == zmq.POLLIN:
            response = self.socket.recv_json()
            response['registers'] = json.loads(response['registers'], object_hook=parse_json_obj)
            if self.callback:
                self.callback(response)
                self.callback = None
            return response
        return None

    def on_update(self, delta):
        if self.callback:
            self.poll()

    def start_kernel(self, timeout=1):
        self.status = 'starting'

        if os.path.isfile(self.connection_file):
            os.remove(self.connection_file)

        self.process = subprocess.Popen(
            shlex.split(self.cmd),
            #stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            #stderr=subprocess.PIPE,
            text=True,
            env={'KERNEL_CONNECTION_FILE': self.connection_file},
            cwd=self.cwd,
        )
        t0 = time.time()
        while True:
            if os.path.isfile(self.connection_file):
                self.kernel_endpoint = json.load(open(self.connection_file))['endpoint']
                break
            if time.time() - t0 > timeout:
                raise Exception('connection failed')
            time.sleep(0.01)

        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.REQ)
        self.socket.connect(self.kernel_endpoint)

        self.poller = zmq.Poller()
        self.poller.register(self.socket, zmq.POLLIN)

        world.updated.connect(self.on_update)
        self.status = 'started'

        self.changed.emit()

    def stop_kernel(self):
        if self.status != 'started':
            return
        world.updated.disconnect(self.on_update)
        self.socket.send_string('STOP')
        self.status = 'stopping'
        self.changed.emit()

    def is_kernel_alive(self):
        return self.process and self.process.poll() is None

    def wait_for_kernel_stopped(self):
        if self.status != 'stopping':
            return
        self.process.terminate()
        self.process.wait()
        self.process = None
        self.status = 'stopped'
        self.changed.emit()

    def drop(self):
        if self.process is not None:
            self.stop_kernel()
            self.wait_for_kernel_stopped()


class Kernels:
    def __init__(self):
        self.folder = os.path.join(world.datadir, 'kernels')
        os.makedirs(self.folder, exist_ok=True)

        self.internal_kernel = InternalKernel()
        self.kernels = {0: self.internal_kernel}

        for data in self.get_kernels():
            self.load_kernel(data)

        self.changed = util.Signal()

    def __getitem__(self, key):
            return self.kernels[key]

    def on_kernel_changed(self):
        self.changed.emit()

    def load_kernel(self, data):
        connection_file = os.path.join(self.folder, str(data['id']))
        kernel = SubprocessKernel(data['id'], data['name'], data['cmd'], data['cwd'], connection_file)
        kernel.changed.connect(self.on_kernel_changed)
        self.kernels[kernel.id] = kernel
        return kernel

    def create_subprocess_kernel(self, cmd, cwd, name=None):
        with world.db:
            cur = world.db.execute('insert into kernels (cmd, cwd, name) values (?, ?, ?)',
                                   (cmd, cwd, name))
            id = cur.lastrowid
        data = self.get_kernel(id)
        return self.load_kernel(data)

    def get_kernels(self):
        return list(map(dict, world.db.execute('select * from kernels').fetchall()))

    def run_in_kernel(self, exprs, callback=None, kernel_id=None, kernel_name=None,
                      registers=None):
        if kernel_id is None:
            kernel = one([x for x in self.kernels.values()
                             if x.name == kernel_name])
        else:
            kernel = self.kernels[kernel_id]
        kernel.send_code({'code': exprs}, callback, registers=registers)

    def get_kernel(self, kernel_id):
        return one(world.db.execute(
            'select * from kernels where id = ?', (kernel_id,)).fetchall())

    def ensure_kernel(self, kernel_id):
        return self.kernels[kernel_id]

    def drop(self):
        for id, kernel in self.kernels.items():
            kernel.drop()
