import time
import random
from collections import deque, defaultdict

from force_layout import ForceLayout as CppForceLayout


class ForceLayout:
    def __init__(self, update_interval=0.1,
                 spring_rest_length = 50,
                 repulsive_force_constant = 6250,
                 spring_constant = 1,
                 delta_t = 0.02,
                 center_force=0.0001,
                 stabilized_max_displacement=0.02,
                 stabilized_avg_displacement=0.01,
                 max_displacement_squared = 100):
        self.position = np.array((0, 500, 0), float)
        self.update_interval = update_interval
        self.spring_rest_length = spring_rest_length
        self.repulsive_force_constant = repulsive_force_constant
        self.spring_constant = spring_constant
        self.delta_t = delta_t
        self.max_displacement_squared = max_displacement_squared
        self.center_force = center_force
        self.stabilized_max_displacement = 0.02
        self.stabilized_avg_displacement = 0.01

        self.active = False
        self.results = 0, 0, 0

        self.cpp_force_layout = CppForceLayout(
            spring_rest_length=self.spring_rest_length,
            repulsive_force_constant=self.repulsive_force_constant,
            spring_constant=self.spring_constant,
            delta_t=self.delta_t,
            center_force=self.center_force,
            center_position=self.position,
            max_displacement_squared=self.max_displacement_squared,
        )

        self.clear()

        self.stabilized = z.Signal()
        self.changed = z.Signal()

    def update_params(self):
        self.cpp_force_layout.repulsive_force_constant = self.repulsive_force_constant
        self.cpp_force_layout.spring_rest_length = self.spring_rest_length
        self.cpp_force_layout.spring_constant = self.spring_constant
        self.cpp_force_layout.max_displacement_squared = self.max_displacement_squared
        self.cpp_force_layout.center_force = self.center_force
        self.cpp_force_layout.delta_t = self.delta_t

    def clear(self):
        self.cpp_force_layout.clear()

    def add_node(self, position):
        return self.cpp_force_layout.add_node(np.asarray(position, float))

    def add_edge(self, source, target, mirror=True):
        self.cpp_force_layout.add_edge(source, target, mirror)

    def set_position(self, index, position):
        self.cpp_force_layout.set_position(index, position)

    def start(self, callback=None):
        self.callback = callback
        self.last_update = None
        self.active = True
        self.changed.emit()

    def update(self, num_iterations=2000):
        if not self.active:# or not self.positions.size:
            return

        self.results = self.cpp_force_layout.step(num_iterations)

        self.positions = self.cpp_force_layout.get_positions()

        total_displacement, average_displacement, max_displacement = self.results

        if average_displacement < self.stabilized_avg_displacement and max_displacement < self.stabilized_max_displacement:
            self.stop()
            self.stabilized.emit()

    def cancel(self):
        self.active = False
        self.changed.emit()

    def stop(self):
        self.active = False
        if self.callback is not None:
            self.callback()
        self.changed.emit()

    def until_stable(self, timeout=10):
        t0 = time.time()
        self.start()
        while self.active:
            self.update(1)
            if time.time() - t0 > timeout:
                self.stop()

    def run(self, callback=None):
        if self.active:
            self.active = False
        self.start(callback)

    def drop(self):
        self.clear()
