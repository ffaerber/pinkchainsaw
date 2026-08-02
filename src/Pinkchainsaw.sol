// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

interface IPostageStamp {
    function topUp(bytes32 _batchId, uint256 _topupAmountPerChunk) external;
    function batches(bytes32)
        external
        view
        returns (address owner, uint8 depth, uint8 bucketDepth, bool immutableFlag, uint256 remainingBalance);
}

contract Pinkchainsaw is Initializable, UUPSUpgradeable {
    address public owner;
    uint256 public bzzFee;

    ERC20 public bzzToken;
    IPostageStamp public postageStamp;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }
    bytes32[] private threadIds;

    mapping(bytes32 => Post) private posts;
    mapping(address => bytes32[]) private addressToThreadIds;
    mapping(address => bytes32[]) private addressToCommentIds;
    mapping(address => int256) private addressToSocialScore;

    // Appended after the original layout. New state must be added at the end so that
    // storage of the already deployed proxy stays valid across upgrades.
    mapping(bytes32 => mapping(address => int256)) private postToVoterToVote;
    mapping(address => bytes32) private addressToBatchId;

    // The project's own postage batch, which hosts the frontend. A share of every fee tops it up,
    // and it is the fallback whenever the batch a fee was meant for cannot take it.
    bytes32 private pinkchainsawBatchId;
    uint256 private projectBps;

    enum PostType {
        THREAD,
        COMMENT
    }

    // Domain separators keep thread ids and comment ids in disjoint namespaces, so a
    // comment can never land on the storage slot of a thread.
    bytes32 private constant THREAD_DOMAIN = keccak256("pinkchainsaw.thread");
    bytes32 private constant COMMENT_DOMAIN = keccak256("pinkchainsaw.comment");

    int256 private constant UP_VOTE = 1;
    int256 private constant DOWN_VOTE = -1;

    uint256 private constant BPS_DENOMINATOR = 10000;
    /// @notice Ceiling on the project's share, so it can never be raised to swallow a whole fee.
    uint256 public constant MAX_PROJECT_BPS = 2000;

    event BatchRegistered(address indexed author, bytes32 batchId);
    event PinkchainsawBatchUpdated(bytes32 batchId);
    event ProjectShareUpdated(uint256 bps);
    event FeePaid(address indexed payer, bytes32 targetBatchId, uint256 targetAmount, uint256 projectAmount);
    event ThreadCreated(bytes32 id);
    event ThreadUpdated(bytes32 id);
    event CommentUpdated(bytes32 id);
    event CommentCreated(bytes32 id);

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _bzzTokenAddress, address _postageStampAddress) public initializer {
        require(_bzzTokenAddress != address(0), "bzz token is zero address");
        require(_postageStampAddress != address(0), "postage stamp is zero address");

        owner = msg.sender;
        bzzToken = ERC20(_bzzTokenAddress);
        postageStamp = IPostageStamp(_postageStampAddress);
        bzzFee = 10 ** 13;
        projectBps = 1000;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice The project batch that hosts the frontend and receives the project share of fees.
    function getPinkchainsawBatchId() public view returns (bytes32) {
        return pinkchainsawBatchId;
    }

    /// @notice Owner settable because postage batches expire and have to be replaced.
    function setPinkchainsawBatchId(bytes32 _batchId) public onlyOwner {
        pinkchainsawBatchId = _batchId;
        emit PinkchainsawBatchUpdated(_batchId);
    }

    /// @notice The project's share of every fee, in basis points.
    function getProjectBps() public view returns (uint256) {
        return projectBps;
    }

    function setProjectBps(uint256 _bps) public onlyOwner {
        require(_bps <= MAX_PROJECT_BPS, "project share above cap");
        projectBps = _bps;
        emit ProjectShareUpdated(_bps);
    }

    /// @notice What an upvote or a downvote costs. Flat for everyone, so that a well reputed
    /// account cannot vote more cheaply than a new one.
    function getVoteFee() public view returns (uint256) {
        return bzzFee;
    }

    /// @notice The postage batch that funds this author's posts, or zero before their first post.
    function getBatchId(address author) public view returns (bytes32) {
        return addressToBatchId[author];
    }

    /// @notice Register the postage batch that funds your posts, replacing any earlier one. A
    /// batch has a finite lifetime, so an author must be able to move to a new one.
    /// @dev Rotating is deliberately its own transaction. Posting can only ever use the batch
    /// registered here, so a client cannot quietly point an author's fees at a different batch
    /// by changing an argument the author never sees.
    function setBatchId(bytes32 _batchId) public {
        require(_batchId != bytes32(0), "batch id is zero");
        addressToBatchId[msg.sender] = _batchId;
        emit BatchRegistered(msg.sender, _batchId);
    }

    /// @dev The first post registers the batch, every later post must reuse it. The PostageStamp
    /// contract lets anyone top up any batch, and a batch is owned by the author's Bee node rather
    /// than by their wallet, so ownership cannot be checked on chain. Binding the batch to the
    /// author is what keeps fees pointed where the author put them.
    function _bindBatch(bytes32 _batchId) internal {
        require(_batchId != bytes32(0), "batch id is zero");

        bytes32 registered = addressToBatchId[msg.sender];
        if (registered == bytes32(0)) {
            addressToBatchId[msg.sender] = _batchId;
            emit BatchRegistered(msg.sender, _batchId);
        } else {
            require(registered == _batchId, "batch not registered to sender");
        }
    }

    /// @dev Routes a fee into postage batches: a share to the project batch, the rest to the batch
    /// of whoever is being replied to or voted on. Engagement funds the storage of the content
    /// engaged with, so a post outlives its author for as long as people keep interacting with it.
    ///
    /// A fee must never block the interaction it belongs to. If the target batch has expired, does
    /// not exist, or is too deep for the amount to survive rounding, its share goes to the project
    /// batch instead, and anything that still cannot be placed is returned to the payer.
    function _payFee(bytes32 _targetBatchId, uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }

        bytes32 projectBatch = pinkchainsawBatchId;
        uint256 projectAmount;
        uint256 targetAmount;

        if (_targetBatchId == bytes32(0) || _targetBatchId == projectBatch) {
            projectAmount = _amount;
        } else {
            projectAmount = (_amount * projectBps) / BPS_DENOMINATOR;
            targetAmount = _amount - projectAmount;
        }

        (uint256 targetPerChunk, uint256 targetTotal) = _quoteTopUp(_targetBatchId, targetAmount);
        if (targetTotal == 0) {
            // the target cannot take it, so the project batch gets the whole fee
            projectAmount += targetAmount;
        }

        (uint256 projectPerChunk, uint256 projectTotal) = _quoteTopUp(projectBatch, projectAmount);

        uint256 total = targetTotal + projectTotal;
        if (total == 0) {
            return;
        }

        require(bzzToken.transferFrom(msg.sender, address(this), total), "transfer failed");

        uint256 spent;
        if (targetTotal > 0) {
            spent += _executeTopUp(_targetBatchId, targetPerChunk, targetTotal);
        }
        if (projectTotal > 0) {
            spent += _executeTopUp(projectBatch, projectPerChunk, projectTotal);
        }

        // a top up can still be refused for a reason the quote cannot see, such as an expired batch
        if (spent < total) {
            require(bzzToken.transfer(msg.sender, total - spent), "refund failed");
        }

        emit FeePaid(msg.sender, _targetBatchId, targetTotal, projectTotal);
    }

    /// @dev What a batch can actually take, or zero when it cannot take anything. A batch that has
    /// never existed reports a zero owner, and a batch deep enough that the amount rounds away
    /// cannot be topped up at all.
    function _quoteTopUp(bytes32 _batchId, uint256 _amount) internal view returns (uint256 perChunk, uint256 total) {
        if (_batchId == bytes32(0) || _amount == 0) {
            return (0, 0);
        }

        (address batchOwner, uint8 depth,,,) = postageStamp.batches(_batchId);
        if (batchOwner == address(0)) {
            return (0, 0);
        }

        perChunk = _amount >> depth;
        if (perChunk == 0) {
            return (0, 0);
        }

        total = perChunk << depth;
    }

    function _executeTopUp(bytes32 _batchId, uint256 _perChunk, uint256 _total) internal returns (uint256) {
        bzzToken.approve(address(postageStamp), _total);

        try postageStamp.topUp(_batchId, _perChunk) {
            return _total;
        } catch {
            bzzToken.approve(address(postageStamp), 0);
            return 0;
        }
    }

    /// @dev The batch a fee should flow to when replying to or voting on a post. Replying to
    /// yourself would otherwise let a penalised author pay their own inflated fee to themselves,
    /// so that case goes to the project batch.
    function _batchOf(address postOwner) internal view returns (bytes32) {
        if (postOwner == msg.sender) {
            return pinkchainsawBatchId;
        }
        return addressToBatchId[postOwner];
    }

    /// @notice Pages are 1-indexed. Out of range pages return an empty array, and the last
    /// page is zero padded up to _resultsPerPage.
    function getPaginatedThreadIds(uint256 _page, uint256 _resultsPerPage)
        external
        view
        returns (bytes32[] memory data)
    {
        if (_page == 0 || _resultsPerPage == 0) {
            return new bytes32[](0);
        }

        uint256 _index = _resultsPerPage * (_page - 1);

        if (_index >= threadIds.length) {
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
        bytes32 threadId = threadIdOf(msg.sender, _threadBzzhash);
        require(!posts[threadId].exists, "thread already exists");

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

        _bindBatch(_batchId);
        // a thread has nobody to reply to, so its fee keeps the frontend alive
        _payFee(pinkchainsawBatchId, getFee(msg.sender));
        return true;
    }

    /// @notice A thread is unique per (owner, bzzhash), so the same image cannot be posted twice.
    function threadIdOf(address _owner, bytes32 _bzzhash) public pure returns (bytes32) {
        return keccak256(abi.encode(THREAD_DOMAIN, _owner, _bzzhash));
    }

    /// @notice A comment is unique per (owner, bzzhash, parent, position under that parent), so the
    /// same text may be posted again without overwriting the earlier comment.
    function commentIdOf(address _owner, bytes32 _bzzhash, bytes32 _parentId, uint256 _index)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(COMMENT_DOMAIN, _owner, _bzzhash, _parentId, _index));
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

        uint256 commentIndex = post.commentIds.length;
        address parentOwner = post.owner;
        bytes32 commentId = commentIdOf(msg.sender, _commentBzzhash, _id, commentIndex);
        require(!posts[commentId].exists, "comment already exists");

        posts[commentId] = Post({
            id: commentId,
            index: commentIndex,
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

        _bindBatch(_batchId);
        // the fee keeps alive the post being replied to, whether that is a thread or a comment
        _payFee(_batchOf(parentOwner), getFee(msg.sender));
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
        _vote(_id, UP_VOTE);
        return true;
    }

    function downVote(bytes32 _id) public returns (bool succeed) {
        _vote(_id, DOWN_VOTE);
        return true;
    }

    /// @notice Returns the vote an address has cast on a post: 1, -1, or 0 when it has not voted.
    function getVote(bytes32 _id, address voter) public view returns (int256) {
        return postToVoterToVote[_id][voter];
    }

    /// @dev One vote per address per post. A voter may flip an existing vote, which costs another
    /// fee and moves the rating by two, but may not repeat a vote it has already cast.
    function _vote(bytes32 _id, int256 _direction) internal {
        Post storage post = posts[_id];
        require(post.exists, "thread or comment doesn't exist");
        require(msg.sender != post.owner, "cannot vote on own post");

        int256 previousVote = postToVoterToVote[_id][msg.sender];
        require(previousVote != _direction, "already voted");
        postToVoterToVote[_id][msg.sender] = _direction;

        int256 delta = _direction - previousVote;
        post.rating += delta;
        addressToSocialScore[post.owner] += delta;

        if (post.postType == PostType.COMMENT) {
            emit CommentUpdated(post.id);
        }
        if (post.postType == PostType.THREAD) {
            emit ThreadUpdated(post.id);
        }

        // flat fee, and it tops up the batch of the post being voted on rather than paying its
        // owner in tokens: a downvote then costs the voter without ever being income for the target
        _payFee(_batchOf(post.owner), bzzFee);
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
