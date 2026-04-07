// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IPostageStamp {
    function topUp(bytes32 _batchId, uint256 _topupAmountPerChunk) external;
    function batches(bytes32)
        external
        view
        returns (address owner, uint8 depth, uint8 bucketDepth, bool immutableFlag, uint256 remainingBalance);
}

contract Pinkchainsaw {
    uint256 public bzzFee = 10 ** 13;

    ERC20 public bzzToken;
    IPostageStamp public postageStamp;
    bytes32[] private threadIds;

    mapping(bytes32 => Post) private posts;
    mapping(address => bytes32[]) private addressToThreadIds;
    mapping(address => bytes32[]) private addressToCommentIds;
    mapping(address => int256) private addressToSocialScore;

    enum PostType {
        THREAD,
        COMMENT
    }

    event ThreadCreated(bytes32 bzzhash);
    event ThreadUpdated(bytes32 bzzhash);
    event CommentUpdated(bytes32 bzzhash);
    event CommentCreated(bytes32 bzzhash);

    struct Post {
        bytes32 id;
        uint256 index;
        uint256 timestamp;
        address owner;
        bytes32 bzzhash;
        bytes32 threadBzzhash;
        bool exists;
        bytes32[] commentIds;
        int256 rating;
        PostType postType;
    }

    constructor(address _bzzTokenAddress, address _postageStampAddress) {
        bzzToken = ERC20(_bzzTokenAddress);
        postageStamp = IPostageStamp(_postageStampAddress);
    }

    function _topUpStamp(bytes32 _batchId, uint256 _totalAmount) internal {
        (, uint8 depth,,,) = postageStamp.batches(_batchId);
        uint256 amountPerChunk = _totalAmount / (1 << depth);
        require(amountPerChunk > 0, "fee too small for batch depth");
        uint256 actualTotal = amountPerChunk * (1 << depth);
        require(bzzToken.transferFrom(msg.sender, address(this), actualTotal), "transfer failed");
        bzzToken.approve(address(postageStamp), actualTotal);
        postageStamp.topUp(_batchId, amountPerChunk);
    }

    function getPaginatedThreadIds(uint256 _page, uint256 _resultsPerPage)
        external
        view
        returns (bytes32[] memory data)
    {
        uint256 _index = _resultsPerPage * _page - _resultsPerPage;

        if (threadIds.length == 0 || _index >= threadIds.length) {
            return new bytes32[](0);
        }

        bytes32[] memory _bzzHashes = new bytes32[](_resultsPerPage);
        uint256 _returnCounter = 0;

        for (_index; _index < _resultsPerPage * _page; _index++) {
            if (_index < threadIds.length) {
                _bzzHashes[_returnCounter] = threadIds[_index];
            } else {
                _bzzHashes[_returnCounter] = 0;
            }
            _returnCounter++;
        }
        return _bzzHashes;
    }

    function createThread(bytes32 _threadBzzhash, bytes32 _batchId) public returns (bool succeed) {
        bytes32 threadId = keccak256(abi.encode(msg.sender, _threadBzzhash));
        require(!posts[threadId].exists, "thread already exists");

        uint256 fee = getFee(msg.sender);
        _topUpStamp(_batchId, fee);

        posts[threadId] = Post({
            id: threadId,
            index: threadIds.length,
            timestamp: block.timestamp,
            owner: msg.sender,
            bzzhash: _threadBzzhash,
            threadBzzhash: _threadBzzhash,
            exists: true,
            commentIds: new bytes32[](0),
            rating: 0,
            postType: PostType.THREAD
        });
        threadIds.push(threadId);
        addressToThreadIds[msg.sender].push(threadId);
        emit ThreadCreated(threadId);
        return true;
    }

    function getThread(bytes32 _id) external view returns (Post memory) {
        Post storage thread = posts[_id];
        require(thread.exists, "thread doesn't exist");
        require(thread.postType == PostType.THREAD, "this is not a thread");
        return thread;
    }

    function getThreadIdsByAddress(address addr) public view returns (bytes32[] memory) {
        return addressToThreadIds[addr];
    }

    function getTotalThreads() public view returns (uint256) {
        return threadIds.length;
    }

    function createComment(bytes32 _id, bytes32 _commentBzzhash, bytes32 _batchId) public returns (bool succeed) {
        Post storage post = posts[_id];
        require(post.exists, "thread or comment doesn't exist");
        bytes32 commentId = keccak256(abi.encode(msg.sender, _commentBzzhash));

        uint256 fee = getFee(msg.sender);
        _topUpStamp(_batchId, fee);

        posts[commentId] = Post({
            id: commentId,
            index: 0,
            timestamp: block.timestamp,
            owner: msg.sender,
            bzzhash: _commentBzzhash,
            threadBzzhash: post.postType == PostType.COMMENT ? post.threadBzzhash : post.bzzhash,
            exists: true,
            commentIds: new bytes32[](0),
            rating: 0,
            postType: PostType.COMMENT
        });

        post.commentIds.push(commentId);
        addressToCommentIds[msg.sender].push(commentId);
        if (post.postType == PostType.COMMENT) {
            emit CommentUpdated(post.id);
        }
        if (post.postType == PostType.THREAD) {
            emit ThreadUpdated(post.id);
        }
        emit CommentCreated(commentId);

        return true;
    }

    function getComment(bytes32 _id) external view returns (Post memory) {
        Post storage comment = posts[_id];
        require(comment.exists, "comment doesn't exist");
        require(comment.postType == PostType.COMMENT, "this is not a comment");
        return comment;
    }

    function getCommentIdsByAddress(address addr) public view returns (bytes32[] memory) {
        return addressToCommentIds[addr];
    }

    function upVote(bytes32 _id) public returns (bool succeed) {
        Post storage post = posts[_id];
        require(post.exists, "thread or comment doesn't exist");
        require(msg.sender != post.owner, "cannot vote on own post");

        uint256 fee = getFee(msg.sender);
        require(bzzToken.transferFrom(msg.sender, post.owner, fee), "transfer failed");

        post.rating++;
        addressToSocialScore[post.owner]++;
        if (post.postType == PostType.COMMENT) {
            emit CommentUpdated(post.id);
        }
        if (post.postType == PostType.THREAD) {
            emit ThreadUpdated(post.id);
        }
        return true;
    }

    function downVote(bytes32 _id) public returns (bool succeed) {
        Post storage post = posts[_id];
        require(post.exists, "thread or comment doesn't exist");
        require(msg.sender != post.owner, "cannot vote on own post");

        uint256 fee = getFee(msg.sender);
        require(bzzToken.transferFrom(msg.sender, post.owner, fee), "transfer failed");

        post.rating--;
        addressToSocialScore[post.owner]--;
        if (post.postType == PostType.COMMENT) {
            emit CommentUpdated(post.id);
        }
        if (post.postType == PostType.THREAD) {
            emit ThreadUpdated(post.id);
        }
        return true;
    }

    function getSocialScore(address addr) public view returns (int256) {
        return addressToSocialScore[addr];
    }

    function getFee(address addr) public view returns (uint256 fee) {
        int256 socialScore = addressToSocialScore[addr];
        uint256 multiplier = getMultiplier(socialScore);
        return bzzFee * multiplier;
    }

    function getMultiplier(int256 socialScore) public pure returns (uint256) {
        if (socialScore >= 2) {
            return 1;
        }
        if (socialScore >= 1) {
            return 2;
        }
        if (socialScore >= 0) {
            return 3;
        }
        if (socialScore >= -1) {
            return 4;
        }
        return 5;
    }
}
