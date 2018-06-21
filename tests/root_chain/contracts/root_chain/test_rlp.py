import pytest
import rlp

from eth_utils import encode_hex, decode_hex

import rlp
from rlp.sedes import big_endian_int, binary
from ethereum import utils

class Eight(rlp.Serializable):
    fields = [
        ('f0', big_endian_int),
        ('f1', big_endian_int),
        ('f2', big_endian_int),
        ('f3', big_endian_int),
        ('f4', big_endian_int),
        ('f5', big_endian_int),
        ('f6', utils.address),
        ('f7', utils.address)
    ]

    def __init__(self, f0, f1, f2, f3, f4, f5, f6, f7):
        self.f0 = f0
        self.f1 = f1
        self.f2 = f2
        self.f3 = f3
        self.f4 = f4
        self.f5 = f5
        self.f6 = f6
        self.f7 = f7

class Ten(rlp.Serializable):
    fields = [
        ('f0', big_endian_int),
        ('f1', big_endian_int),
        ('f2', big_endian_int),
        ('f3', big_endian_int),
        ('f4', big_endian_int),
        ('f5', big_endian_int),
        ('f6', big_endian_int),
        ('f7', utils.address),
        ('f8', utils.address),
        ('f9', utils.address)
    ]

    def __init__(self, f0, f1, f2, f3, f4, f5, f6, f7, f8, f9):
        self.f0 = f0
        self.f1 = f1
        self.f2 = f2
        self.f3 = f3
        self.f4 = f4
        self.f5 = f5
        self.f6 = f6
        self.f7 = f7
        self.f8 = f8
        self.f9 = f9

@pytest.fixture
def rlp_test(t, get_contract):
    contract = get_contract('RLPTest')
    t.chain.mine()
    return contract

def test_rlp_tx_eight(t, u, rlp_test):
    tx = Eight(0, 1, 2, 3, 4, 5, t.a0, t.a1)
    tx_bytes = rlp.encode(tx, Eight)
    assert [5, encode_hex(t.a0), encode_hex(t.a1)] == rlp_test.eight(tx_bytes)

def test_rlp_tx_ten(t, u, rlp_test):
    tx = Ten(0, 1, 2, 3, 4, 5, 6, t.a0, t.a1, t.a2)
    tx_bytes = rlp.encode(tx, Ten)
    assert [6, encode_hex(t.a0), encode_hex(t.a1), encode_hex(t.a2)] == rlp_test.ten(tx_bytes)
