pragma solidity 0.4.18;

import 'SafeMath.sol';
import 'Math.sol';
import 'PlasmaRLP.sol';
import 'Merkle.sol';
import 'Validate.sol';
import 'PriorityQueue.sol';


/**
 * @title RootChain
 * @dev This contract secures a utxo payments plasma child chain to ethereum
 */

contract RootChain {
    using SafeMath for uint256;
    using Merkle for bytes32;
    using PlasmaRLP for bytes;

    /*
     * Events
     */
    event Deposit(
        address indexed depositor,
        uint256 indexed depositBlock,
        address token,
        uint256 amount
    );

    event ExitStarted(
        address indexed exitor,
        uint256 indexed utxoPos,
        address token,
        uint256 amount
    );

    event TokenAdded(
        address token
    );

    /*
     *  Storage
     */
    mapping(uint256 => childBlock) public childChain;
    mapping(uint256 => exit) public exits;
    mapping (address => address) public exitsQueues;
    address public authority;
    /* Block numbering scheme below is needed to prevent Ethereum reorg from invalidating blocks submitted
       by operator. Two mechanisms must be in place to prevent chain from crashing:
       1) don't mine tx that spent fresh deposits; if they are reorged from existence, block is invalid
       2) disappearance of submit block does not affect operator's block numbering; hence tx submitted by
       users that address that block stay valid.
    */
    uint256 public currentChildBlock; /* ends with 000 */
    uint256 public currentDepositBlock; /* takes values in range 1..999 */
    uint256 public childBlockInterval;
    uint256 public currentFeeExit;

    struct exit {
        address owner;
        address token;
        uint256 amount;
    }

    struct childBlock {
        bytes32 root;
        uint256 created_at;
    }

    /*
     *  Modifiers
     */
    modifier isAuthority() {
        require(msg.sender == authority);
        _;
    }

    /*
     * Public Functions
     */

    function RootChain()
        public
    {
        authority = msg.sender;
        childBlockInterval = 1000;
        currentChildBlock = childBlockInterval;
        currentDepositBlock = 1;
        currentFeeExit = 1;
        // Support only ETH on deployment; other tokens need
        // to be added explicitly.
        exitsQueues[address(0)] = address(new PriorityQueue());
    }

    // @dev Allows anyone to add new token to Plasma chain
    // @param token The address of the ERC-20 token
    function addToken(address token)
        public
    {
        require(exitsQueues[token] == address(0));
        exitsQueues[token] = address(new PriorityQueue());
        TokenAdded(token);
    }

    function hasToken(address token)
        view
        public
        returns (bool)
    {
        return exitsQueues[token] != address(0);
    }

    // @dev Allows Plasma chain operator to submit block root
    // @param root The root of a child chain block
    function submitBlock(bytes32 root)
        public
        isAuthority
    {   
        childChain[currentChildBlock] = childBlock({
            root: root,
            created_at: block.timestamp
        });
        currentChildBlock = currentChildBlock.add(childBlockInterval);
        currentDepositBlock = 1;
    }

    // @dev Allows anyone to deposit funds into the Plasma chain
    // @param txBytes The format of the transaction that'll become the deposit
    function deposit()
        public
        payable
    {
        require(currentDepositBlock < childBlockInterval);
        bytes32 root = keccak256(msg.sender, address(0), msg.value);
        uint256 depositBlock = getDepositBlock();
        childChain[depositBlock] = childBlock({
            root: root,
            created_at: block.timestamp
        });
        currentDepositBlock = currentDepositBlock.add(1);
        Deposit(msg.sender, depositBlock, address(0), msg.value);
    }

    function startDepositExit(uint256 depositPos, address token, uint256 amount)
        public
    {
        uint256 blknum = depositPos / 1000000000;
        // Makes sure that deposit position is actually a deposit
        require(blknum % childBlockInterval != 0);
        bytes32 root = childChain[blknum].root;
        bytes32 depositHash = keccak256(msg.sender, token, amount);
        require(root == depositHash);
        addExitToQueue(depositPos, msg.sender, token, amount, childChain[blknum].created_at);
    }

    function startFeeExit(address token, uint256 amount)
        public
        isAuthority
        returns (uint256)
    {
        addExitToQueue(currentFeeExit, msg.sender, token, amount, block.timestamp + 1);
        currentFeeExit = currentFeeExit.add(1);
    }

    // @dev Starts to exit a specified utxo
    // @param utxoPos The position of the exiting utxo in the format of blknum * 1000000000 + index * 10000 + oindex
    // @param txBytes The transaction being exited in RLP bytes format
    // @param proof Proof of the exiting transactions inclusion for the block specified by utxoPos
    // @param sigs Both transaction signatures and confirmations signatures used to verify that the exiting transaction has been confirmed
    function startExit(uint256 utxoPos, bytes txBytes, bytes proof, bytes sigs)
        public
    {
        uint256 blknum = utxoPos / 1000000000;
        uint256 txindex = (utxoPos % 1000000000) / 10000;
        uint256 oindex = utxoPos - blknum * 1000000000 - txindex * 10000; 
        var exitingTx = txBytes.createExitingTx(oindex);
        require(msg.sender == exitingTx.exitor);
        bytes32 root = childChain[blknum].root; 
        bytes32 merkleHash = keccak256(keccak256(txBytes), ByteUtils.slice(sigs, 0, 130));
        require(Validate.checkSigs(keccak256(txBytes), root, exitingTx.inputCount, sigs));
        require(merkleHash.checkMembership(txindex, root, proof));
        addExitToQueue(utxoPos, exitingTx.exitor, exitingTx.token, exitingTx.amount, childChain[blknum].created_at);
    }

    // Priority is a given utxos position in the exit priority queue
    function addExitToQueue(uint256 utxoPos, address exitor, address token, uint256 amount, uint256 created_at)
        private
    {
        // known token:
        require(exitsQueues[token] != address(0));
        uint256 exitable_at = Math.max(created_at + 2 weeks, block.timestamp + 1 weeks);
        uint256 priority = exitable_at << 128 | utxoPos;
        require(amount > 0);
        require(exits[utxoPos].amount == 0);
        PriorityQueue queue = PriorityQueue(exitsQueues[token]);
        queue.insert(priority);
        exits[utxoPos] = exit({
            owner: exitor,
            token: token,
            amount: amount
        });
        ExitStarted(msg.sender, utxoPos, token, amount);
    }

    // @dev Allows anyone to challenge an exiting transaction by submitting proof of a double spend on the child chain
    // @param cUtxoPos The position of the challenging utxo
    // @param eUtxoIndex The output position of the exiting utxo
    // @param txBytes The challenging transaction in bytes RLP form
    // @param proof Proof of inclusion for the transaction used to challenge
    // @param sigs Signatures for the transaction used to challenge
    // @param confirmationSig The confirmation signature for the transaction used to challenge
    function challengeExit(uint256 cUtxoPos, uint256 eUtxoIndex, bytes txBytes, bytes proof, bytes sigs, bytes confirmationSig)
        public
    {
        uint256 eUtxoPos = txBytes.getUtxoPos(eUtxoIndex);
        uint256 txindex = (cUtxoPos % 1000000000) / 10000;
        bytes32 root = childChain[cUtxoPos / 1000000000].root;
        var txHash = keccak256(txBytes);
        var confirmationHash = keccak256(txHash, root);
        var merkleHash = keccak256(txHash, sigs);
        address owner = exits[eUtxoPos].owner;

        require(owner == ECRecovery.recover(confirmationHash, confirmationSig));
        require(merkleHash.checkMembership(txindex, root, proof));
        // Clear as much as possible from succesful challenge
        delete exits[eUtxoPos].owner;
    }

    // @dev Loops through the priority queue of exits, settling the ones whose challenge
    // @dev challenge period has ended
    function finalizeExits(address token)
        public
    {
        uint256 utxoPos;
        uint256 exitable_at;
        (utxoPos, exitable_at) = getNextExit(token);
        exit memory currentExit = exits[utxoPos];
        PriorityQueue queue = PriorityQueue(exitsQueues[token]);
        while (exitable_at < block.timestamp && queue.currentSize() > 0) {
            currentExit = exits[utxoPos];
            // FIXME: handle ERC-20 transfer
            require(address(0) == token);
            currentExit.owner.transfer(currentExit.amount);
            queue.delMin();
            // FIXME: something like this:
            /* if (address(0) == token) { */
            /*     currentExit.owner.transfer(currentExit.amount); */
            /* } */
            /* else { */
            /*     require(ERC20Basic(token).transfer(currentExit.owner, currentExit.amount)); */
            /* } */
            /* queue.delMin(); */
            delete exits[utxoPos].owner;

            if (queue.currentSize() > 0) {
                (utxoPos, exitable_at) = getNextExit(token);
            } else {
                return;
            }
        }
    }

    /* 
     *  Constant functions
     */
    function getChildChain(uint256 blockNumber)
        public
        view
        returns (bytes32, uint256)
    {
        return (childChain[blockNumber].root, childChain[blockNumber].created_at);
    }

    function getDepositBlock()
        public
        view
        returns (uint256)
    {
        return currentChildBlock.sub(childBlockInterval).add(currentDepositBlock);
    }

    function getExit(uint256 utxoPos)
        public
        view
        returns (address, address, uint256)
    {
        return (exits[utxoPos].owner, exits[utxoPos].token, exits[utxoPos].amount);
    }

    function getNextExit(address token)
        public
        view
        returns (uint256, uint256)
    {
        uint256 priority = PriorityQueue(exitsQueues[token]).getMin();
        uint256 utxoPos = uint256(uint128(priority));
        uint256 exitable_at = priority >> 128;
        return (utxoPos, exitable_at);
    }
}
