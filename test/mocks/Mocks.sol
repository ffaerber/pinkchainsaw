// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockBzz is ERC20 {
    constructor() ERC20("Mock BZZ", "mBZZ") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Enough of Swarm's PostageStamp to exercise fee routing. Topping up is permissionless on
/// the real contract too, so no ownership check here either.
contract MockPostageStamp {
    struct Batch {
        address owner;
        uint8 depth;
        uint256 remainingBalance;
        bool expired;
    }

    mapping(bytes32 => Batch) private _batches;
    ERC20 public immutable token;

    constructor(address _token) {
        token = ERC20(_token);
    }

    function createBatch(bytes32 _batchId, address _owner, uint8 _depth) external {
        _batches[_batchId] = Batch({owner: _owner, depth: _depth, remainingBalance: 0, expired: false});
    }

    function expireBatch(bytes32 _batchId) external {
        _batches[_batchId].expired = true;
    }

    function batches(bytes32 _batchId)
        external
        view
        returns (address owner, uint8 depth, uint8 bucketDepth, bool immutableFlag, uint256 remainingBalance)
    {
        Batch storage batch = _batches[_batchId];
        return (batch.owner, batch.depth, 16, false, batch.remainingBalance);
    }

    function topUp(bytes32 _batchId, uint256 _topupAmountPerChunk) external {
        Batch storage batch = _batches[_batchId];
        require(batch.owner != address(0), "batch does not exist");
        require(!batch.expired, "batch already expired");

        uint256 total = _topupAmountPerChunk << batch.depth;
        require(token.transferFrom(msg.sender, address(this), total), "transfer failed");
        batch.remainingBalance += _topupAmountPerChunk;
    }

    /// @dev Total BZZ a batch has received, which is what the routing tests assert on.
    function toppedUp(bytes32 _batchId) external view returns (uint256) {
        Batch storage batch = _batches[_batchId];
        return batch.remainingBalance << batch.depth;
    }
}
