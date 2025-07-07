import sys

class Redirected:
    def __init__(self, out=sys.stdout, err=sys.stderr):
        self.out = out
        self.err = err
        self._saved_stdout = None
        self._saved_stderr = None

    def __enter__(self):
        self._saved_stdout = sys.stdout
        self._saved_stderr = sys.stderr
        sys.stdout = self.out
        sys.stderr = self.err

    def __exit__(self, exc_type, exc_val, exc_tb):
        sys.stdout = self._saved_stdout
        sys.stderr = self._saved_stderr