class States:
    def __init__(self):
        self.state_count = 0
        self.states_list = []
        self.state_names = {}
        self.reverse_state_names = {}
        self.state_parents = {}
        self.entry_handlers = {}
        self.leave_handlers = {}
        self.active_states = []
        self.history = []

        self.changed = z.Signal()

        world.states = self

    def get_status(self):
        return '/'.join((self.state_names.get(x, '-') for x in self.active_states))

    def create_state(self, parent=None, name=None, on_enter=None, on_leave=None):
        #assert name
        id = self.state_count
        self.state_count += 1
        self.states_list.append(id)
        if parent:
            self.state_parents[id] = parent
        if name:
            assert name not in self.reverse_state_names
            self.state_names[id] = name
            self.reverse_state_names[name] = id
        self.entry_handlers[id] = on_enter
        self.leave_handlers[id] = on_leave
        return id

    def drop_state(self, state_id):
        self.states_list.remove(state_id)
        name = self.state_names.pop(state_id)
        self.reverse_state_names.pop(name)
        del self.entry_handlers[state_id]
        del self.leave_handlers[state_id]
        # TODO parents - traverse?

    def transit(self, state_id=None, state_name=None):
        id = state_id if state_id is not None else self.reverse_state_names[state_name]
        if self.active_states:
            self.history.append(self.active_states[0])
            for s in self.active_states:
                self.leave_handlers[s]()
        self.active_states = [id]
        self.entry_handlers[id]()
        self.changed.emit()

    def is_state_active(self, state_id):
        return state_id in self.active_states

    def transit_back(self):
        self.transit(state_id=self.history[-1])
        self.history = self.history[:-2]

    def transit_next(self):
        raise NotImplementedError

#    def to_next(self):
#        keys_list = list(self.root.keys())
#        index = keys_list.index(self.current)
#        if index < len(keys_list) - 1:
#            self.to(keys_list[index + 1])

    def drop(self):
        pass
