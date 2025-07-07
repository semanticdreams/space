import json
import base58

from solders.keypair import Keypair
from solders.pubkey import Pubkey
from solana.rpc.types import TokenAccountOpts
from solana.rpc.api import Client
from solana.rpc.websocket_api import connect


class Solana:
    def __init__(self, privkey):
        self.privkey = privkey
        self.sol_client = Client("https://api.mainnet-beta.solana.com")
        self.raydium_program_id = '675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8'

    def _keys_from_array(self, array):
        secret_key = key_array[0:32]
        public_key = key_array[32:64]
        sk = base58.b58encode(bytes(secret_key))
        pk = base58.b58encode(bytes(public_key))
        return sk, pb

    def _keys_str_to_array(self, keys_str):
        return [x for x in base58.b58decode(keys_str)]

    #def get_trading_wallet_privkey(self):
    #    return world.secrets.get('solana-privkey')

    def get_trading_wallet_keypair(self):
        #privkey = self.get_trading_wallet_privkey()
        keypair = Keypair.from_base58_string(self.privkey)
        return keypair

    def get_trading_wallet_balance(self):
        keypair = self.get_trading_wallet_keypair()
        pubkey = keypair.pubkey()
        balance = self.sol_client.get_balance(pubkey).value
        return balance / 1_000_000_000

    def get_tokens(self):
        token_program_id = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'
        response = self.sol_client.get_token_accounts_by_owner_json_parsed(
                self.get_trading_wallet_keypair().pubkey(), TokenAccountOpts(
                program_id=Pubkey.from_string(self.raydium_program_id))).to_json()
        json_response = json.loads(response)
        return json_response['result']['value']

    async def get_transactions(self):
        async with connect("wss://api.devnet.solana.com") as websocket:
            await websocket.logs_subscribe()
            first_resp = await websocket.recv()
            subscription_id = first_resp[0].result
            while True:
                next_resp = await websocket.recv()
                print(next_resp)
            await websocket.logs_unsubscribe(subscription_id)
