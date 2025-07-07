class SolanaView:
    def __init__(self, focus_parent=world.focus):
        self.focus = focus_parent.add_child(self)
        self.balance_label = z.Label()
        self.layout = self.balance_label.layout

        world.aio.create_task(self.update())
        
    async def update(self):
        await self.update_balance()
        #await self.update_tokens()
        
    async def update_balance(self):
        kernel = world.kernels[1]
        cls = world.classes.get_class_code(name='Solana')
        await kernel.send_code_async(cls)
        privkey = world.apps['Secrets'].get('solana-privkey')
        code = dict(code='solana = Solana(_registers["privkey"]); _registers["balance"] = solana.get_trading_wallet_balance()',
                    )
        result = await kernel.send_code_async(code, registers=dict(privkey=privkey))
        self.balance_label.set_text(str(result['registers']['balance']))

    async def update_tokens(self):
        kernel = world.kernels[1]
        cls = world.classes.get_class_code(name='Solana')
        await kernel.send_code_async(cls)
        privkey = world.apps['Secrets'].get('solana-privkey')
        code = dict(code='solana = Solana(_registers["privkey"]); _registers["balance"] = solana.get_tokens()',
                    )
        result = await kernel.send_code_async(code, registers=dict(privkey=privkey))
        print(result)
        
    def drop(self):
        self.balance_label.drop()
