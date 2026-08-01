// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/Pinkchainsaw.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PinkchainsawTest is Test {
    Pinkchainsaw public board;

    address constant BZZ = 0xdBF3Ea6F5beE45c02255B2c26a16F300502F68da;
    address constant POSTAGE_STAMP = 0x45a1502382541Cd610CC9068e88727426b696293;
    address constant BZZ_WHALE = 0x781c6D1f0eaE6F1Da1F604c6cDCcdB8B76428ba7;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    bytes32 batchId;
    bytes32[] bytes32Strings;

    function setUp() public {
        Pinkchainsaw impl = new Pinkchainsaw();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(Pinkchainsaw.initialize, (BZZ, POSTAGE_STAMP)));
        board = Pinkchainsaw(address(proxy));

        // Fund wallets with real BZZ via whale
        vm.startPrank(BZZ_WHALE);
        IERC20(BZZ).transfer(alice, 1e16);
        IERC20(BZZ).transfer(bob, 1e16);
        IERC20(BZZ).transfer(carol, 1e16);
        vm.stopPrank();

        // Find a usable batch from the PostageStamp contract
        // Use a known active batch (from the Makefile/env)
        batchId = 0xd6a860cbd104d026c48e947dc896a367347de6677d11ac003dea0a61ed5b69bf;

        for (uint256 i = 0; i < 210; i++) {
            bytes32Strings.push(bytes32(i));
        }
    }

    function test_usersHaveBZZ() public view {
        assertEq(IERC20(BZZ).balanceOf(alice), 1e16);
        assertEq(IERC20(BZZ).balanceOf(bob), 1e16);
        assertEq(IERC20(BZZ).balanceOf(carol), 1e16);
    }

    function test_createThread() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        assertEq(board.getTotalThreads(), 1);
    }

    function test_createMultipleThreads() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        board.createThread(bytes32Strings[1], batchId);
        vm.stopPrank();

        assertEq(board.getTotalThreads(), 2);

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 2);

        Pinkchainsaw.Post memory thread0 = board.getThread(threadIds[0]);
        assertEq(thread0.index, 0);

        Pinkchainsaw.Post memory thread1 = board.getThread(threadIds[1]);
        assertEq(thread1.index, 1);
    }

    function test_getThreadViaId() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);

        uint256 blocktime = block.timestamp + 1 hours;
        vm.warp(blocktime);

        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 2);
        Pinkchainsaw.Post memory thread = board.getThread(threadIds[0]);

        assertEq(thread.index, 0);
        assertEq(thread.bzzhash, bytes32Strings[0]);
        assertEq(thread.owner, alice);
        assertEq(thread.timestamp, blocktime);
        assertEq(thread.commentIds.length, 0);
    }

    function test_createCommentOnThread() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 1);

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createComment(threadIds[0], bytes32Strings[1], batchId);
        vm.stopPrank();

        Pinkchainsaw.Post memory thread = board.getThread(threadIds[0]);
        bytes32 commentId = thread.commentIds[0];

        Pinkchainsaw.Post memory comment = board.getComment(commentId);
        assertEq(comment.bzzhash, bytes32Strings[1]);
        assertEq(comment.owner, bob);
        assertEq(comment.commentIds.length, 0);
        assertEq(comment.threadBzzhash, bytes32Strings[0]);
    }

    function test_createCommentOnComment() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 1);

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createComment(threadIds[0], bytes32Strings[1], batchId);
        vm.stopPrank();

        Pinkchainsaw.Post memory thread = board.getThread(threadIds[0]);
        bytes32 commentId = thread.commentIds[0];

        vm.startPrank(bob);
        board.createComment(commentId, bytes32Strings[2], batchId);
        vm.stopPrank();

        Pinkchainsaw.Post memory comment = board.getComment(commentId);
        bytes32 subCommentId = comment.commentIds[0];

        Pinkchainsaw.Post memory subComment = board.getComment(subCommentId);
        assertEq(subComment.bzzhash, bytes32Strings[2]);
    }

    function test_getMultiplier() public view {
        assertEq(board.getMultiplier(2), 1);
        assertEq(board.getMultiplier(1), 2);
        assertEq(board.getMultiplier(0), 3);
        assertEq(board.getMultiplier(-1), 4);
        assertEq(board.getMultiplier(-2), 5);
    }

    function test_getMultiplierBelowMinusTwo() public view {
        assertEq(board.getMultiplier(-3), 5);
        assertEq(board.getMultiplier(-10), 5);
        assertEq(board.getMultiplier(-100), 5);
    }

    function test_feeGoesToStampTopUp() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);

        uint256 stampBalanceBefore = IERC20(BZZ).balanceOf(POSTAGE_STAMP);
        uint256 aliceBalanceBefore = IERC20(BZZ).balanceOf(alice);

        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        uint256 stampBalanceAfter = IERC20(BZZ).balanceOf(POSTAGE_STAMP);
        uint256 aliceBalanceAfter = IERC20(BZZ).balanceOf(alice);

        assertTrue(aliceBalanceAfter < aliceBalanceBefore, "alice should have spent BZZ");
        assertTrue(stampBalanceAfter > stampBalanceBefore, "stamp contract should have received BZZ");
    }

    function test_stampRemainingBalanceIncreases() public {
        (,,,, uint256 remainingBefore) = IPostageStamp(POSTAGE_STAMP).batches(batchId);

        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        (,,,, uint256 remainingAfter) = IPostageStamp(POSTAGE_STAMP).batches(batchId);

        assertTrue(remainingAfter > remainingBefore, "stamp remainingBalance should increase");
    }

    function test_stampTopUpAmountMatchesFee() public {
        (, uint8 depth,,, uint256 remainingBefore) = IPostageStamp(POSTAGE_STAMP).batches(batchId);
        uint256 fee = board.getFee(alice);
        uint256 expectedPerChunk = fee / (1 << depth);

        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        (,,,, uint256 remainingAfter) = IPostageStamp(POSTAGE_STAMP).batches(batchId);

        assertEq(
            remainingAfter - remainingBefore, expectedPerChunk, "remaining balance should increase by amountPerChunk"
        );
    }

    function test_multiplePostsAccumulateStampTopUp() public {
        (, uint8 depth,,, uint256 remainingBefore) = IPostageStamp(POSTAGE_STAMP).batches(batchId);
        uint256 fee = board.getFee(alice);
        uint256 expectedPerChunk = fee / (1 << depth);

        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        board.createThread(bytes32Strings[1], batchId);
        board.createThread(bytes32Strings[2], batchId);
        vm.stopPrank();

        (,,,, uint256 remainingAfter) = IPostageStamp(POSTAGE_STAMP).batches(batchId);

        assertEq(remainingAfter - remainingBefore, expectedPerChunk * 3, "3 posts should top up 3x");
    }

    function test_commentTopsUpCommenterStamp() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 1);

        (,,,, uint256 remainingBefore) = IPostageStamp(POSTAGE_STAMP).batches(batchId);

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createComment(threadIds[0], bytes32Strings[1], batchId);
        vm.stopPrank();

        (,,,, uint256 remainingAfter) = IPostageStamp(POSTAGE_STAMP).batches(batchId);

        assertTrue(remainingAfter > remainingBefore, "comment should top up the stamp");
    }

    function test_voteDoesNotTopUpStamp() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 1);

        (,,,, uint256 remainingBefore) = IPostageStamp(POSTAGE_STAMP).batches(batchId);

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.upVote(threadIds[0]);
        vm.stopPrank();

        (,,,, uint256 remainingAfter) = IPostageStamp(POSTAGE_STAMP).batches(batchId);

        assertEq(remainingAfter, remainingBefore, "votes should not top up stamp");
    }

    function test_voteSendsFeeToPostOwner() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 1);

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);

        uint256 aliceBefore = IERC20(BZZ).balanceOf(alice);
        board.upVote(threadIds[0]);
        vm.stopPrank();

        uint256 aliceAfter = IERC20(BZZ).balanceOf(alice);
        assertTrue(aliceAfter > aliceBefore, "alice should have received vote fee");
    }

    function test_getSocialScore() public {
        vm.startPrank(carol);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        assertEq(board.getSocialScore(carol), 0);

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 1);

        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.upVote(threadIds[0]);
        assertEq(board.getSocialScore(carol), 1);
        // flipping to a down vote moves the score by two
        board.downVote(threadIds[0]);
        assertEq(board.getSocialScore(carol), -1);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.downVote(threadIds[0]);
        assertEq(board.getSocialScore(carol), -2);
        vm.stopPrank();
    }

    function test_cannotRepeatSameVote() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.upVote(threadId);

        vm.expectRevert("already voted");
        board.upVote(threadId);

        board.downVote(threadId);

        vm.expectRevert("already voted");
        board.downVote(threadId);
        vm.stopPrank();

        // one voter can never move a rating by more than one in either direction
        assertEq(board.getThread(threadId).rating, -1);
        assertEq(board.getSocialScore(alice), -1);
    }

    function test_voteIsRecordedPerVoter() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        assertEq(board.getVote(threadId, bob), 0);

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.upVote(threadId);
        vm.stopPrank();

        assertEq(board.getVote(threadId, bob), 1);
        assertEq(board.getVote(threadId, carol), 0);

        vm.prank(bob);
        board.downVote(threadId);

        assertEq(board.getVote(threadId, bob), -1);
    }

    function test_flippingVoteChargesFeeAgain() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.upVote(threadId);

        uint256 fee = board.getFee(bob);
        uint256 bobBefore = IERC20(BZZ).balanceOf(bob);
        board.downVote(threadId);
        vm.stopPrank();

        assertEq(bobBefore - IERC20(BZZ).balanceOf(bob), fee, "flipping a vote costs a fee");
    }

    function test_cannotSelfVote() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 1);

        vm.expectRevert("cannot vote on own post");
        board.upVote(threadIds[0]);

        vm.expectRevert("cannot vote on own post");
        board.downVote(threadIds[0]);
        vm.stopPrank();
    }

    function test_cannotCreateDuplicateThread() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);

        vm.expectRevert("thread already exists");
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();
    }

    function test_paginationEdgeCase() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32[] memory page2 = board.getPaginatedThreadIds(2, 1);
        assertEq(page2.length, 0);
    }

    function test_firstPostRegistersTheBatch() public {
        assertEq(board.getBatchId(alice), bytes32(0));

        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        assertEq(board.getBatchId(alice), batchId);
    }

    /// A client cannot point an author's fees at a batch the author never chose.
    function test_cannotPostWithAnUnregisteredBatch() public {
        bytes32 otherBatch = keccak256("some other batch");

        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);

        vm.expectRevert("batch not registered to sender");
        board.createThread(bytes32Strings[1], otherBatch);
        vm.stopPrank();

        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createComment(threadId, bytes32Strings[2], batchId);

        vm.expectRevert("batch not registered to sender");
        board.createComment(threadId, bytes32Strings[3], otherBatch);
        vm.stopPrank();
    }

    function test_setBatchIdRotatesTheBinding() public {
        bytes32 otherBatch = keccak256("some other batch");

        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);

        board.setBatchId(otherBatch);
        assertEq(board.getBatchId(alice), otherBatch);

        // the previously registered batch is now the one that is rejected
        vm.expectRevert("batch not registered to sender");
        board.createThread(bytes32Strings[1], batchId);

        // rotating back restores posting with it
        board.setBatchId(batchId);
        board.createThread(bytes32Strings[1], batchId);
        vm.stopPrank();

        assertEq(board.getTotalThreads(), 2);
    }

    function test_batchBindingIsPerAuthor() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        // alice's binding does not constrain bob, who has not posted yet
        assertEq(board.getBatchId(bob), bytes32(0));

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[1], batchId);
        vm.stopPrank();

        assertEq(board.getBatchId(bob), batchId);
    }

    function test_cannotRegisterZeroBatch() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);

        vm.expectRevert("batch id is zero");
        board.setBatchId(bytes32(0));

        vm.expectRevert("batch id is zero");
        board.createThread(bytes32Strings[0], bytes32(0));
        vm.stopPrank();
    }

    function test_paginationPageZeroReturnsEmpty() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        // page 0 used to revert with an arithmetic underflow
        assertEq(board.getPaginatedThreadIds(0, 20).length, 0);
        assertEq(board.getPaginatedThreadIds(1, 0).length, 0);
    }

    /// Posting the same text twice produces the same Swarm reference. Both comments must
    /// survive as separate posts instead of the second overwriting the first.
    function test_sameCommentBzzhashInTwoThreads() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        board.createThread(bytes32Strings[1], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 2);

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createComment(threadIds[0], bytes32Strings[9], batchId);
        board.createComment(threadIds[1], bytes32Strings[9], batchId);
        vm.stopPrank();

        Pinkchainsaw.Post memory threadOne = board.getThread(threadIds[0]);
        Pinkchainsaw.Post memory threadTwo = board.getThread(threadIds[1]);

        assertEq(threadOne.commentIds.length, 1);
        assertEq(threadTwo.commentIds.length, 1);
        assertTrue(threadOne.commentIds[0] != threadTwo.commentIds[0], "comments must have distinct ids");

        // each comment still points at the thread it was posted under
        assertEq(board.getComment(threadOne.commentIds[0]).threadBzzhash, bytes32Strings[0]);
        assertEq(board.getComment(threadTwo.commentIds[0]).threadBzzhash, bytes32Strings[1]);
        assertEq(board.getCommentIdsByAddress(bob).length, 2);
    }

    function test_sameCommentBzzhashTwiceInOneThread() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createComment(threadId, bytes32Strings[9], batchId);
        board.createComment(threadId, bytes32Strings[9], batchId);
        vm.stopPrank();

        Pinkchainsaw.Post memory thread = board.getThread(threadId);
        assertEq(thread.commentIds.length, 2);
        assertTrue(thread.commentIds[0] != thread.commentIds[1], "comments must have distinct ids");
        assertEq(board.getComment(thread.commentIds[0]).index, 0);
        assertEq(board.getComment(thread.commentIds[1]).index, 1);
    }

    /// A comment whose bzzhash equals its author's own thread bzzhash used to overwrite that
    /// thread, leaving a dead id in the thread list.
    function test_commentCannotOverwriteOwnThread() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);

        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];
        board.createComment(threadId, bytes32Strings[0], batchId);
        vm.stopPrank();

        Pinkchainsaw.Post memory thread = board.getThread(threadId);
        assertEq(thread.owner, alice);
        assertEq(thread.bzzhash, bytes32Strings[0]);
        assertEq(thread.index, 0);
        assertEq(thread.commentIds.length, 1);
        assertTrue(thread.commentIds[0] != threadId, "comment id must not equal the thread id");
        assertEq(board.getTotalThreads(), 1);
    }

    function test_votesAndCommentsSurviveARepostedBzzhash() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        board.createThread(bytes32Strings[1], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 2);

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createComment(threadIds[0], bytes32Strings[9], batchId);
        vm.stopPrank();

        bytes32 firstCommentId = board.getThread(threadIds[0]).commentIds[0];

        vm.startPrank(carol);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.upVote(firstCommentId);
        vm.stopPrank();

        assertEq(board.getComment(firstCommentId).rating, 1);

        // bob reposts the same text under the other thread
        vm.prank(bob);
        board.createComment(threadIds[1], bytes32Strings[9], batchId);

        // the earlier comment keeps its rating
        assertEq(board.getComment(firstCommentId).rating, 1);
        assertEq(board.getSocialScore(bob), 1);
    }

    function test_getCommentsByAddress() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 1);
        bytes32 threadId = threadIds[0];

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createComment(threadId, bytes32Strings[1], batchId);
        vm.stopPrank();

        vm.startPrank(carol);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createComment(threadId, bytes32Strings[2], batchId);
        vm.stopPrank();

        vm.startPrank(alice);
        board.createComment(threadId, bytes32Strings[3], batchId);
        vm.stopPrank();

        Pinkchainsaw.Post memory thread = board.getThread(threadId);

        bytes32[] memory bobCommentIds = board.getCommentIdsByAddress(bob);
        assertEq(bobCommentIds.length, 1);
        _assertContains(thread.commentIds, bobCommentIds[0]);

        bytes32[] memory carolCommentIds = board.getCommentIdsByAddress(carol);
        assertEq(carolCommentIds.length, 1);
        _assertContains(thread.commentIds, carolCommentIds[0]);

        bytes32[] memory aliceCommentIds = board.getCommentIdsByAddress(alice);
        assertEq(aliceCommentIds.length, 1);
        _assertContains(thread.commentIds, aliceCommentIds[0]);
    }

    function test_upVoteTransfersExactFee() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 1);

        uint256 fee = board.getFee(bob);
        uint256 aliceBefore = IERC20(BZZ).balanceOf(alice);
        uint256 bobBefore = IERC20(BZZ).balanceOf(bob);

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.upVote(threadIds[0]);
        vm.stopPrank();

        assertEq(IERC20(BZZ).balanceOf(alice) - aliceBefore, fee, "alice should receive exactly fee");
        assertEq(bobBefore - IERC20(BZZ).balanceOf(bob), fee, "bob should spend exactly fee");
    }

    function test_downVoteTransfersExactFeeToOwner() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 1);

        uint256 fee = board.getFee(bob);
        uint256 aliceBefore = IERC20(BZZ).balanceOf(alice);
        uint256 bobBefore = IERC20(BZZ).balanceOf(bob);

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.downVote(threadIds[0]);
        vm.stopPrank();

        assertEq(IERC20(BZZ).balanceOf(alice) - aliceBefore, fee, "alice should receive exactly fee on downvote");
        assertEq(bobBefore - IERC20(BZZ).balanceOf(bob), fee, "bob should spend exactly fee on downvote");
    }

    function test_feeScalesWithNegativeSocialScore() public {
        // alice starts at score 0 → multiplier 3
        assertEq(board.getFee(alice), board.bzzFee() * 3);

        // bob creates a thread so alice can downvote it (driving alice's own votes, not her score)
        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        // carol downvotes alice's thread to push alice's social score negative
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[1], batchId);
        vm.stopPrank();

        bytes32[] memory allThreads = board.getPaginatedThreadIds(1, 2);
        bytes32 aliceThread = allThreads[1];

        vm.startPrank(carol);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.downVote(aliceThread);
        vm.stopPrank();

        // alice score: -1 → multiplier 4
        assertEq(board.getSocialScore(alice), -1);
        assertEq(board.getFee(alice), board.bzzFee() * 4);

        // a second, distinct voter is needed to push the score further down
        vm.prank(bob);
        board.downVote(aliceThread);

        // alice score: -2 → multiplier 5
        assertEq(board.getSocialScore(alice), -2);
        assertEq(board.getFee(alice), board.bzzFee() * 5);
    }

    function test_feeScalesWithPositiveSocialScore() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 1);

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.upVote(threadIds[0]);
        vm.stopPrank();

        // alice score: 1 → multiplier 2
        assertEq(board.getFee(alice), board.bzzFee() * 2);

        // a second, distinct voter is needed to push the score further up
        vm.startPrank(carol);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.upVote(threadIds[0]);
        vm.stopPrank();

        // alice score: 2 → multiplier 1
        assertEq(board.getFee(alice), board.bzzFee() * 1);
    }

    function test_voteFailsWithoutApproval() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 1);

        // bob has BZZ but has not approved the board
        vm.prank(bob);
        vm.expectRevert();
        board.upVote(threadIds[0]);
    }

    function _assertContains(bytes32[] memory haystack, bytes32 needle) internal pure {
        bool found = false;
        for (uint256 i = 0; i < haystack.length; i++) {
            if (haystack[i] == needle) {
                found = true;
                break;
            }
        }
        assertTrue(found, "expected element not found in array");
    }
}
