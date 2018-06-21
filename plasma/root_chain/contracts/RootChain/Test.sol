pragma solidity 0.4.18;

import 'PlasmaRLP.sol';

/* import '../Libraries/PlasmaRLP.sol'; */

contract Test {

    using PlasmaRLP for bytes;

    function RootChain()
        public
    {
    }

    function justEight(bytes tx_bytes)
        public
        constant
        returns (uint256, address, address)
    {
        return tx_bytes.justEight();
    }

    function almostTen(bytes tx_bytes)
        public
        constant
        returns (uint256, address, address, address)
    {
        return tx_bytes.almostTen();
    }
}
