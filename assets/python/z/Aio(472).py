import asyncio


class Aio:
    def __init__(self):
        self.loop = asyncio.get_event_loop()
        self.pending_tasks = []
        self.callbacks = {}

    def create_task(self, coro, callback=None):
        t = self.loop.create_task(coro)
        self.pending_tasks.append(t)
        if callback:
            self.callbacks[t] = callback
        return t

    def update(self):
        self.loop.run_until_complete(asyncio.sleep(0))
        done = [t for t in self.pending_tasks if t.done()]
        for t in done:
            self.pending_tasks.remove(t)
            result = t.result()
            if t in self.callbacks:
                self.callbacks[t](result)
                del self.callbacks[t]