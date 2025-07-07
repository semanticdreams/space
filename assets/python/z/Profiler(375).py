import os
import sys
import appdirs
import subprocess
import cProfile


class Profiler:
    def __init__(self, name):
        self.name = name

        self.dir = os.path.join(appdirs.user_data_dir('space'), 'prof')
        os.makedirs(self.dir, exist_ok=True)
        self.prof_filename = os.path.join(self.dir, f'{self.name}.prof')
        self.svg_filename = os.path.join(self.dir, f'{self.name}.svg')

        self.gprof2dot = os.path.abspath(os.path.join(world.assets_path, 'python/lib/gprof2dot.py'))

        self.profiler = cProfile.Profile()

    def enable(self):
        self.profiler.enable()

    def disable(self):
        self.profiler.disable()

    def dump(self):
        self.profiler.dump_stats(self.prof_filename)

    def svg(self):
        gprof2dot_args = [self.gprof2dot, "-f", "pstats", os.path.abspath(self.prof_filename)]
        dot_args = ["dot", "-Tsvg", "-o", self.svg_filename]
        with subprocess.Popen(gprof2dot_args, stdout=subprocess.PIPE) as pgprof:
            with subprocess.Popen(
                dot_args, stdin=pgprof.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE
            ) as pdot:
                pgprof.stdout.close()  # Allow pgprof to receive a SIGPIPE if pdot exits
                pgprof.wait()
                pdot.wait()
                stdout, stderr = pdot.communicate()
                if pgprof.returncode != 0:
                    raise Exception(f"gprof2dot failed with return code {pgprof.returncode}")
                if pdot.returncode != 0:
                    raise Exception(f"dot failed with return code {pdot.returncode}: {stderr.decode()}")

    def __enter__(self):
        self.profiler.enable()
        return self.profiler

    def __exit__(self, exc_type, exc_value, traceback):
        self.profiler.disable()
        self.dump()
