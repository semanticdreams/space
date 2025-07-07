class Normalizer:
    def __init__(self, values=None, fixed_min_val=None, fixed_max_val=None):
        self.values = np.asarray(values) if values is not None else np.array()
        self.fixed_min_val = fixed_min_val
        self.fixed_max_val = fixed_max_val
        self.min_val = fixed_min_val or np.min(values)
        self.max_val = fixed_max_val or np.max(values)
        if self.min_val == self.max_val:
            self.result = np.array([0.5] * len(values))
        else:
            self.result = (self.values - self.min_val) / (self.max_val - self.min_val)