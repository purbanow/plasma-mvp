import pytest
import rlp

from eth_utils import encode_hex, decode_hex

import rlp
from rlp.sedes import big_endian_int, binary
from ethereum import utils

class JustEight(rlp.Serializable):
    fields = [
        ('f1', big_endian_int),
        ('f2', big_endian_int),
        ('f3', big_endian_int),
        ('f4', big_endian_int),
        ('f5', big_endian_int),
        ('f6', big_endian_int),
        ('f7', utils.address),
        ('f8', utils.address)
    ]

    def __init__(self, f1, f2, f3, f4, f5, f6, f7, f8):
        self.f1 = f1
        self.f2 = f2
        self.f3 = f3
        self.f4 = f4
        self.f5 = f5
        self.f6 = f6
        self.f7 = f7
        self.f8 = f8

class AlmostTen(rlp.Serializable):
    fields = [
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

    def __init__(self, f1, f2, f3, f4, f5, f6, f7, f8, f9):
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
    contract = get_contract('Test')
    t.chain.mine()
    return contract

def test_rlp_tx_decode_success(t, u, rlp_test):
    tx = JustEight(1, 2, 3, 4, 5, 6, t.a0, t.a1)
    tx_bytes = rlp.encode(tx, JustEight)
    print("tx: {0}".format(encode_hex(tx_bytes)))
    assert [6, encode_hex(t.a0), encode_hex(t.a1)] == rlp_test.justEight(tx_bytes)
    assert False

def test_rlp_tx_decode_fail(t, u, rlp_test):
    tx = AlmostTen(1, 2, 3, 4, 5, 6, t.a0, t.a1, t.a2)
    tx_bytes = rlp.encode(tx, AlmostTen)
    print("tx: {0}".format(encode_hex(tx_bytes)))
    assert [6, encode_hex(t.a0), encode_hex(t.a1), encode_hex(t.a2)] == rlp_test.almostTen(tx_bytes)
    assert False
