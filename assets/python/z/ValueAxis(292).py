class ValueAxis:
    def __init__(self):
        self.range = [None, None]

    def set_range(self, min_val, max_val):
        self.range = [min_val, max_val]