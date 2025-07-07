class Folders:
    def get_folder_locator(self, folder_id):
        return world.locators.ensure_locator('folder', folder_id)

    def create_folder(self, name=''):
        with world.db:
            cur = world.db.execute('insert into folders (name) values (?)',
                             (name,))
        return dict(id=cur.lastrowid, name=name)

    def create_child_folder(self, parent_id, name=''):
        folder = self.create_folder(name=name)
        with world.db:
            child_locator = self.get_folder_locator(folder['id'])
            self.add_child(parent_id, child_locator['id'])
        return folder

    def add_child(self, folder_id, locator_id):
        with world.db:
            world.db.execute('insert into folder_items (folder_id, locator_id) values (?, ?)',
                             (folder_id, locator_id))

    def get_children(self, folder_id):
        return list(map(dict, world.db.execute(
            'select * from folder_items where folder_id = ?', (folder_id,)).fetchall()))

    def update_name(self, folder_id, name):
        with world.db:
            world.db.execute('update folders set name = ? where id = ?',
                       (name, folder_id))

    def delete_folder(self, folder_id):
        locator = self.get_folder_locator(folder_id)
        with world.db:
            world.db.execute('delete from folder_items where folder_id = ?',
                             (folder_id,))
            world.db.execute('delete from folder_items where locator_id = ?',
                             (locator['id'],))
            world.db.execute('delete from folders where id = ?', (folder_id,))
        world.locators.drop_locator(locator['id'])

    def get_folder(self, folder_id):
        return dict(world.db.execute('select * from folders where id = ?',
                               (folder_id,)).fetchall()[0])

    def find_folder(self, name):
        return dict(world.db.execute('select * from folders where name = ?',
                               (name,)).fetchall()[0])

    def get_folders(self):
        return list(map(dict, world.db.execute('select * from folders').fetchall()))