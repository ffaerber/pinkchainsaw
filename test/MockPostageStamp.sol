// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockPostageStamp {
    IERC20 public bzzToken;

    struct Batch {
        address owner;
        uint8 depth;
        uint8 bucketDepth;
        bool immutableFlag;
        uint256 remainingBalance;
    }

    mapping(bytes32 => Batch) public batches;

    constructor(address _bzzToken) {
        bzzToken = IERC20(_bzzToken);
    }

    function createBatch(bytes32 _batchId, address _owner, uint8 _depth) external {
        batches[_batchId] =
            Batch({owner: _owner, depth: _depth, bucketDepth: 16, immutableFlag: false, remainingBalance: 1});
    }

    function topUp(bytes32 _batchId, uint256 _topupAmountPerChunk) external {
        Batch storage batch = batches[_batchId];
        require(batch.owner != address(0), "batch does not exist");
        uint256 totalAmount = _topupAmountPerChunk * (1 << batch.depth);
        bzzToken.transferFrom(msg.sender, address(this), totalAmount);
        batch.remainingBalance += _topupAmountPerChunk;
    }
}
