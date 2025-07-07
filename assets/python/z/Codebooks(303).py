class Codebooks:
    def get_codebooks(self):
        return list(map(z.Codebook, map(dict, world.db.execute('select * from codebooks').fetchall())))

    def get_codebook(self, codebook_id):
        return Codebook(dict(one(world.db.execute('select * from codebooks where id = ?',
                                                  (codebook_id,)).fetchall())))

    def create_codebook(self):
        with world.db:
            cur = world.db.execute('insert into codebooks default values')
            codebook_id = cur.lastrowid
        codebook = self.get_codebook(codebook_id)
        return codebook

    def drop(self):
        pass
