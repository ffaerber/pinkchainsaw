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

        // Only one usable batch exists on the fork, so it stands in for both the project batch and
        // every author's batch. That means these tests verify amounts against the real PostageStamp
        // but cannot tell fee destinations apart. FeeRouting.t.sol covers routing, against mocks.
        board.setPinkchainsawBatchId(batchId);

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

    function test_multiplierIsNeutralForANewAuthor() public view {
        assertEq(board.multiplierBpsFor(0, 0), 30000, "a new author sits midway between 1x and 5x");
    }

    function test_multiplierClampsAtBothEnds() public view {
        uint256 min = board.MIN_MULTIPLIER_BPS();
        uint256 max = board.MAX_MULTIPLIER_BPS();

        assertEq(board.multiplierBpsFor(10, 0), min, "ten clean upvotes reach the cheapest fee");
        assertEq(board.multiplierBpsFor(1000, 0), min);
        assertEq(board.multiplierBpsFor(0, 10), max, "ten downvotes reach the dearest fee");
        assertEq(board.multiplierBpsFor(0, 100000), max, "and it never goes past it");
    }

    /// The old ladder put a brand new author on the dearest fee after two downvotes, with no way
    /// back except posting at that fee.
    function test_aFewDownvotesDoNotSlamANewAuthor() public view {
        uint256 neutral = board.multiplierBpsFor(0, 0);
        uint256 twoDown = board.multiplierBpsFor(0, 2);

        assertGt(twoDown, neutral, "two downvotes still cost the author something");
        assertLt(twoDown, board.MAX_MULTIPLIER_BPS(), "but nowhere near the ceiling");
        assertLt(twoDown - neutral, board.MAX_MULTIPLIER_BPS() - twoDown, "it stays nearer neutral");
    }

    /// What earned standing is for: the same five downvotes barely touch an established author.
    function test_earnedStandingAbsorbsDownvotes() public view {
        assertEq(board.multiplierBpsFor(1000, 5), board.MIN_MULTIPLIER_BPS(), "veteran unaffected");
        assertGt(board.multiplierBpsFor(0, 5), board.multiplierBpsFor(1000, 5));
    }

    /// Volume alone must not buy a cheap fee. On the old net score an author with 1000 upvotes and
    /// 995 downvotes scored +5 and paid the cheapest rate, despite half their content being
    /// rejected. The ratio prices them near neutral instead.
    function test_volumeDoesNotRescueABadRatio() public view {
        uint256 mixed = board.multiplierBpsFor(1000, 995);

        assertGt(mixed, board.MIN_MULTIPLIER_BPS(), "a 50% record is not the cheapest fee");
        assertApproxEqAbs(mixed, 30000, 200, "it lands close to neutral");
    }

    function test_multiplierIsMonotonic() public view {
        for (uint256 i = 0; i < 20; i++) {
            assertGe(board.multiplierBpsFor(3, i + 1), board.multiplierBpsFor(3, i), "downvotes never cheapen");
            assertLe(board.multiplierBpsFor(i + 1, 3), board.multiplierBpsFor(i, 3), "upvotes never cost more");
        }
    }

    function test_downVotesRaiseThePostingFee() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        uint256 feeBefore = board.getFee(alice);
        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.downVote(threadId);
        vm.stopPrank();

        assertGt(board.getFee(alice), feeBefore, "a downvote makes posting dearer");
        (uint256 up, uint256 down) = board.getVoteCounts(alice);
        assertEq(up, 0);
        assertEq(down, 1);
    }

    function test_voteCountsFollowAFlip() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.upVote(threadId);

        (uint256 up, uint256 down) = board.getVoteCounts(alice);
        assertEq(up, 1);
        assertEq(down, 0);

        // flipping retracts the upvote rather than counting both
        board.downVote(threadId);
        vm.stopPrank();

        (up, down) = board.getVoteCounts(alice);
        assertEq(up, 0, "the upvote is retracted");
        assertEq(down, 1);
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

    function test_commentTopsUpTheParentOwnerStamp() public {
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

    function test_voteTopsUpStamp() public {
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

        assertTrue(remainingAfter > remainingBefore, "a vote buys the post storage time");
    }

    function test_voteIsNotIncomeForThePostOwner() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 1);

        uint256 aliceBefore = IERC20(BZZ).balanceOf(alice);

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.upVote(threadIds[0]);
        board.downVote(threadIds[0]);
        vm.stopPrank();

        assertEq(IERC20(BZZ).balanceOf(alice), aliceBefore, "votes never pay the post owner in tokens");
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

        uint256 charged = _chargeFor(board.getVoteFee());
        uint256 bobBefore = IERC20(BZZ).balanceOf(bob);
        board.downVote(threadId);
        vm.stopPrank();

        assertEq(bobBefore - IERC20(BZZ).balanceOf(bob), charged, "flipping a vote costs a fee");
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

    function test_voterSpendsExactlyTheFlatVoteFee() public {
        vm.startPrank(alice);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.createThread(bytes32Strings[0], batchId);
        vm.stopPrank();

        bytes32[] memory threadIds = board.getPaginatedThreadIds(1, 1);

        uint256 fee = board.getVoteFee();
        assertEq(fee, board.bzzFee(), "the vote fee carries no social score multiplier");

        // a top up can only move whole chunks, so the charge is the fee rounded down to the
        // batch's chunk size, exactly as the contract computes it
        uint256 charged = _chargeFor(fee);

        vm.startPrank(bob);
        IERC20(BZZ).approve(address(board), type(uint256).max);

        uint256 bobBefore = IERC20(BZZ).balanceOf(bob);
        board.upVote(threadIds[0]);
        assertEq(bobBefore - IERC20(BZZ).balanceOf(bob), charged, "bob spends the vote fee");

        bobBefore = IERC20(BZZ).balanceOf(bob);
        board.downVote(threadIds[0]);
        assertEq(bobBefore - IERC20(BZZ).balanceOf(bob), charged, "and the same again to flip it");
        vm.stopPrank();
    }

    /// What a fee actually costs once it has been rounded to whole chunks of the batch.
    function _chargeFor(uint256 fee) internal view returns (uint256) {
        (, uint8 depth,,,) = IPostageStamp(POSTAGE_STAMP).batches(batchId);
        return (fee >> depth) << depth;
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

        assertEq(board.getSocialScore(alice), -1);
        uint256 feeAfterOne = board.getFee(alice);
        assertGt(feeAfterOne, board.bzzFee() * 3, "one downvote makes posting dearer");

        // a second, distinct voter is needed to push the score further down
        vm.prank(bob);
        board.downVote(aliceThread);

        assertEq(board.getSocialScore(alice), -2);
        assertGt(board.getFee(alice), feeAfterOne, "and a second dearer still");
        assertLt(
            board.getFee(alice),
            board.bzzFee() * board.MAX_MULTIPLIER_BPS() / 10000,
            "two downvotes must not reach the ceiling"
        );
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

        uint256 neutralFee = board.bzzFee() * 3;
        uint256 feeAfterOne = board.getFee(alice);
        assertLt(feeAfterOne, neutralFee, "one upvote makes posting cheaper");

        // a second, distinct voter is needed to push the score further up
        vm.startPrank(carol);
        IERC20(BZZ).approve(address(board), type(uint256).max);
        board.upVote(threadIds[0]);
        vm.stopPrank();

        assertLt(board.getFee(alice), feeAfterOne, "and a second cheaper still");
        assertGt(
            board.getFee(alice),
            board.bzzFee() * board.MIN_MULTIPLIER_BPS() / 10000,
            "but the cheapest rate has to be earned over more than two votes"
        );
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
