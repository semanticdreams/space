import traceback
import code
import os, json
import sys
import io
import textwrap
import numpy as np
import sdl2


class Console:
    history_path = os.path.join(world.datadir, 'console_history')

    def __init__(self):
        self.prompt = '>>>'
        self.cmdlines = [self.prompt + ' ']
        self.cmds = json.load(open(self.history_path))
        self.cmd_index = len(self.cmds) - 1
        self.runner = code.InteractiveConsole(locals=dict(world=world))

        self.changed = z.Signal()

    def write(self, text):
        self.cmdlines[-1] += str(text)
        self.changed.emit()

    def writeline(self, text):
        text = '\n'.join(reversed(text.split('\n')))
        self.cmdlines.append(str(text))
        self.changed.emit()

    def inject(self, text):
        out = io.StringIO()
        err = io.StringIO()

        with z.Redirected(out=out, err=err):
            out.flush()
            err.flush()

            more = self.runner.runcode(text)

            output = out.getvalue()
            error = err.getvalue()

        self.writeline(output)
        self.writeline(error)

        self.prompt = '...' if more else '>>>'

    def ret(self):
        text = self.cmdlines[-1].strip()[4:]
        if text:
            self.cmds.append(text)
            self.cmd_index = len(self.cmds)
            self.save_history()
            self.eval(text)
        self.writeline(self.prompt + ' ')

    def backspace(self):
        self.cmdlines[-1] = self.cmdlines[-1][:max(4, len(self.cmdlines[-1])-1)]
        self.changed.emit()

    def eval(self, cmd):
        out = io.StringIO()
        err = io.StringIO()

        with z.Redirected(out=out, err=err):
            out.flush()
            err.flush()

            more = self.runner.push(cmd)

            output = out.getvalue()
            error = err.getvalue()

        self.writeline(output)
        self.writeline(error)

        self.prompt = '...' if more else '>>>'

    def browse_history(self, direction):
        if direction == 'up':
            if self.cmd_index > 0:
                self.cmd_index -= 1
        elif direction == 'down':
            if self.cmd_index < len(self.cmds) - 1:
                self.cmd_index += 1
            else:
                self.cmd_index = len(self.cmds)
                self.cmdlines[-1] = self.prompt + ' '
                self.changed.emit()
                return
        if 0 <= self.cmd_index < len(self.cmds):
            self.cmdlines[-1] = self.prompt + ' ' + self.cmds[self.cmd_index]
        else:
            self.cmdlines[-1] = self.prompt + ' '
        self.changed.emit()

    def save_history(self):
        with open(self.history_path ,'w') as f:
            json.dump(self.cmds, f)