import time
class LayoutStatsView:
    def __init__(self, lt):
        self.lt = lt

        self.focus = world.focus.add_child(self)
        self.name = z.ReactiveValue(f'layout-stats: {self.lt}')

        self.label = z.Label('')

        self.column = z.Flex([self.label], axis='y', xalign='largest')
        self.layout = self.column.layout

        self.reload()

        self.interval = world.apps['Time'].set_interval(self.reload, 1000)

    def reload(self):
        counts = [
            self.agg_counts(self.lt.measure_times),
            self.agg_counts(self.lt.layout_times),
            self.agg_counts(self.lt.transform_times),
        ]
        self.label.text.set('\n'.join((' '.join((str(x) for x in y[0])) + ' | ' + ' '.join((str(round(max(x), 3)) for x in y[1])) for y in counts)))

    def agg_counts(self, times):
        counts = [0] * 10
        deltas = [[0]] * 10
        start_time = int(time.time()) - 9
        for t0, t1 in times:
            sec = int(t0)
            if sec >= start_time:
                counts[sec - start_time] += 1
                deltas[sec - start_time].append(t1 - t0)
        return counts, deltas

    def drop(self):
        world.apps['Time'].remove_interval(self.interval)
        self.column.drop()
        self.label.drop()
        self.focus.drop()
