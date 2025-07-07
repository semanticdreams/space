import traceback
import io


class Codebook:
    def __init__(self, data):
        self.data = data
        self.registers = {}

    def add_code(self, code_id, pos=None):
        codebook_id = self.data['id']
        if pos is None:
            pos = (self.get_max_pos() or 0) + 1
        with world.db:
            world.db.execute(
                'insert into codebook_codes'
                ' (codebook_id, code_id, pos) values (?, ?, ?)',
                (codebook_id, code_id, pos))

    def new_code(self):
        code_id = world.codes.create_code()
        world.codes.update_code_kernel(code_id, self.data['default_kernel'])
        self.add_code(code_id)

    def get_max_pos(self):
        codebook_id = self.data['id']
        return one(world.db.execute(
            'select max(pos) as max_pos from codebook_codes'
            ' where codebook_id = ?',
            (codebook_id,)).fetchall())['max_pos']

    def move_code_up(self, code):
        prev_code = one_or_none(
            world.db.execute(
                'select code_id, pos from codebook_codes where codebook_id = ?'
                ' and pos < ? order by pos desc limit 1',
                (code['codebook_id'], code['pos'])).fetchall())
        if prev_code:
            with world.db:
                world.db.execute(
                    'update codebook_codes set pos = ? where codebook_id = ?'
                    ' and code_id = ? and pos = ?',
                    (prev_code['pos'], code['codebook_id'], code['id'], code['pos']))
                world.db.execute(
                    'update codebook_codes set pos = ? where codebook_id = ?'
                    ' and code_id = ? and pos = ?',
                    (code['pos'], code['codebook_id'], prev_code['code_id'], prev_code['pos']))

    def move_code_down(self, code):
        next_code = one_or_none(
            world.db.execute(
                'select code_id, pos from codebook_codes where codebook_id = ?'
                ' and pos > ? order by pos asc limit 1',
                (code['codebook_id'], code['pos'])).fetchall())
        if next_code:
            with world.db:
                world.db.execute(
                    'update codebook_codes set pos = ? where codebook_id = ?'
                    ' and code_id = ? and pos = ?',
                    (next_code['pos'], code['codebook_id'], code['id'], code['pos']))
                world.db.execute(
                    'update codebook_codes set pos = ? where codebook_id = ?'
                    ' and code_id = ? and pos = ?',
                    (code['pos'], code['codebook_id'], next_code['code_id'], next_code['pos']))


    def get_codebook_codes(self):
        data = world.db.execute('select b.pos, b.codebook_id, c.* from codebook_codes b'
                                ' join codes c on b.code_id = c.id'
                                ' where codebook_id = ?'
                                ' order by b.pos asc',
                               (self.data['id'],)).fetchall()
        return list(map(dict, data))

    def update_name(self, name):
        self.data['name'] = name
        with world.db:
            world.db.execute('update codebooks set name = ? where id = ?',
                             (self.data['name'], self.data['id']))

    def update_default_kernel(self, kernel_id):
        self.data['default_kernel'] = kernel_id
        with world.db:
            world.db.execute('update codebooks set default_kernel = ? where id = ?',
                             (self.data['default_kernel'], self.data['id']))

    def delete_code(self, code):
        self.remove_code_from_codebook(code['id'])
        world.codes.delete_code(code)

    def remove_code_from_codebook(self, code_id):
        with world.db:
            world.db.execute('delete from codebook_codes where codebook_id = ? and code_id = ?',
                             (self.data['id'], code_id))