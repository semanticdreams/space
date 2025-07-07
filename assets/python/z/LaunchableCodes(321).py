class LaunchableCodes:
    def get_launchable_codes(self):
        return list(map(dict, world.db.execute('select * from launchable_codes').fetchall()))

    def get_autolaunch_launchable_codes(self):
        return list(map(dict, world.db.execute('select * from launchable_codes where autolaunch = 1').fetchall()))

    def create_launchable_code(self, code_id):
        with world.db:
            cur = world.db.execute('insert into launchable_codes (code_id) values (?)',
                                   (code_id,))
        return dict(id=cur.lastrowid, name=None, code_id=code_id)

    def update_launchable_code(self, code_id, name):
        with world.db:
            world.db.execute('update launchable_codes set name = ? where code_id = ?',
                             (name, code_id))

    def delete_launchable_code(self, name):
        with world.db:
            world.db.execute('delete from launchable_codes where name = ?', (name,))

    def drop(self):
        pass
