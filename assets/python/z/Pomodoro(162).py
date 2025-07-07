class Pomodoro:
    def create_session(self):
        with world.db:
            cur = world.db.execute('insert into pomodoro_sessions (created_at) values (?)',
                                   (time.time(),))
            return cur.lastrowid

    def get_session(self, id):
        return dict(one(world.db.execute('select * from pomodoro_sessions where id = ?',
                                         (id,)).fetchall()))

    def get_most_recently_created_session(self):
        return dict(one(world.db.execute('select * from pomodoro_sessions order by created_at desc'
                                         ' limit 1',
                                        ).fetchall()))

    def recover_sessions(self):
        # just unset started_at in case they weren't stopped
        with world.db:
            world.db.execute('update pomodoro_sessions set started_at = null')

    def stop_session(self, id):
        session = self.get_session(id)
        assert session['started_at']
        with world.db:
            world.db.execute('update pomodoro_sessions set started_at = null, elapsed = ?'
                             ' where id = ?',
                             (session['elapsed'] + (time.time() - session['started_at']),
                              id))

    def start_session(self, id):
        session = self.get_session(id)
        assert not session['started_at']
        with world.db:
            world.db.execute('update pomodoro_sessions set started_at = ?'
                             ' where id = ?',
                             (time.time(), id))