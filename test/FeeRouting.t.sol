// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/Pinkchainsaw.sol";
import "./mocks/Mocks.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// Where a fee ends up. The fork suite runs against the real PostageStamp but has only one usable
/// batch, so it cannot tell one destination from another. These run against mocks and can.
contract FeeRoutingTest is Test {
    Pinkchainsaw board;
    MockBzz bzz;
    MockPostageStamp stamp;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    bytes32 constant PROJECT_BATCH = keccak256("pinkchainsaw batch");
    bytes32 constant ALICE_BATCH = keccak256("alice batch");
    bytes32 constant BOB_BATCH = keccak256("bob batch");
    bytes32 constant CAROL_BATCH = keccak256("carol batch");

    // 3e13 and 3e12 both divide exactly by 2^10, so the split lands on round numbers
    uint8 constant DEPTH = 10;

    function setUp() public {
        bzz = new MockBzz();
        stamp = new MockPostageStamp(address(bzz));

        Pinkchainsaw impl = new Pinkchainsaw();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(Pinkchainsaw.initialize, (address(bzz), address(stamp))));
        board = Pinkchainsaw(address(proxy));
        board.setPinkchainsawBatchId(PROJECT_BATCH);

        stamp.createBatch(PROJECT_BATCH, address(this), DEPTH);
        stamp.createBatch(ALICE_BATCH, alice, DEPTH);
        stamp.createBatch(BOB_BATCH, bob, DEPTH);
        stamp.createBatch(CAROL_BATCH, carol, DEPTH);

        address[3] memory users = [alice, bob, carol];
        for (uint256 i = 0; i < users.length; i++) {
            bzz.mint(users[i], 1e18);
            vm.prank(users[i]);
            bzz.approve(address(board), type(uint256).max);
        }
    }

    function _postFee(address author) internal view returns (uint256) {
        return board.getFee(author);
    }

    function _projectShare(uint256 fee) internal view returns (uint256) {
        return (fee * board.getProjectBps()) / 10000;
    }

    function test_defaultProjectShareIsTenPercent() public view {
        assertEq(board.getProjectBps(), 1000);
    }

    function test_threadFeeGoesEntirelyToProjectBatch() public {
        uint256 fee = _postFee(alice);

        vm.prank(alice);
        board.createThread(bytes32("image"), ALICE_BATCH);

        assertEq(stamp.toppedUp(PROJECT_BATCH), fee, "project batch gets the whole thread fee");
        assertEq(stamp.toppedUp(ALICE_BATCH), 0, "poster's own batch is untouched");
    }

    function test_commentFeeSplitsBetweenThreadOwnerAndProject() public {
        vm.prank(alice);
        board.createThread(bytes32("image"), ALICE_BATCH);

        uint256 projectBefore = stamp.toppedUp(PROJECT_BATCH);
        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        uint256 fee = _postFee(bob);
        uint256 projectCut = _projectShare(fee);

        vm.prank(bob);
        board.createComment(threadId, bytes32("gm"), BOB_BATCH);

        assertEq(stamp.toppedUp(ALICE_BATCH), fee - projectCut, "thread owner gets the rest");
        assertEq(stamp.toppedUp(PROJECT_BATCH) - projectBefore, projectCut, "project gets its share");
        assertEq(stamp.toppedUp(BOB_BATCH), 0, "commenter's own batch is untouched");
    }

    /// Alice replying to Bob's comment funds Bob, not Alice, even though Alice owns the thread.
    function test_replyFundsTheDirectParentNotTheThreadOwner() public {
        vm.prank(alice);
        board.createThread(bytes32("image"), ALICE_BATCH);
        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        vm.prank(bob);
        board.createComment(threadId, bytes32("gm"), BOB_BATCH);
        bytes32 commentId = board.getThread(threadId).commentIds[0];

        uint256 aliceBefore = stamp.toppedUp(ALICE_BATCH);
        uint256 fee = _postFee(alice);
        uint256 projectCut = _projectShare(fee);

        vm.prank(alice);
        board.createComment(commentId, bytes32("hi bob"), ALICE_BATCH);

        assertEq(stamp.toppedUp(BOB_BATCH), fee - projectCut, "parent comment owner is funded");
        assertEq(stamp.toppedUp(ALICE_BATCH), aliceBefore, "thread owner gets nothing for replying");
    }

    function test_selfReplyGoesToProjectBatch() public {
        vm.prank(alice);
        board.createThread(bytes32("image"), ALICE_BATCH);
        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        uint256 projectBefore = stamp.toppedUp(PROJECT_BATCH);
        uint256 fee = _postFee(alice);

        vm.prank(alice);
        board.createComment(threadId, bytes32("bump"), ALICE_BATCH);

        assertEq(stamp.toppedUp(ALICE_BATCH), 0, "an author cannot fund their own batch by replying");
        assertEq(stamp.toppedUp(PROJECT_BATCH) - projectBefore, fee, "the whole fee goes to the project");
    }

    function test_voteTopsUpPostOwnerBatchAndPaysNoTokens() public {
        vm.prank(alice);
        board.createThread(bytes32("image"), ALICE_BATCH);
        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        uint256 aliceTokensBefore = bzz.balanceOf(alice);
        uint256 projectBefore = stamp.toppedUp(PROJECT_BATCH);
        uint256 fee = board.getVoteFee();
        uint256 projectCut = _projectShare(fee);

        vm.prank(bob);
        board.upVote(threadId);

        assertEq(bzz.balanceOf(alice), aliceTokensBefore, "a vote is never income for the post owner");
        assertEq(stamp.toppedUp(ALICE_BATCH), fee - projectCut, "it buys the post storage time instead");
        assertEq(stamp.toppedUp(PROJECT_BATCH) - projectBefore, projectCut);
    }

    function test_downVoteCannotBeFarmedByThePostOwner() public {
        vm.prank(alice);
        board.createThread(bytes32("bait"), ALICE_BATCH);
        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        uint256 aliceTokensBefore = bzz.balanceOf(alice);

        vm.prank(bob);
        board.downVote(threadId);
        vm.prank(carol);
        board.downVote(threadId);

        assertEq(bzz.balanceOf(alice), aliceTokensBefore, "downvotes must never pay the target");
        assertEq(board.getSocialScore(alice), -2);
    }

    function test_voteFeeIsFlatRegardlessOfVoterScore() public {
        vm.prank(alice);
        board.createThread(bytes32("image"), ALICE_BATCH);
        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        // drive bob's social score down so his posting fee rises
        vm.prank(carol);
        board.createThread(bytes32("carol image"), CAROL_BATCH);
        bytes32 bobThread;
        vm.prank(bob);
        board.createThread(bytes32("bob image"), BOB_BATCH);
        bobThread = board.threadIdOf(bob, bytes32("bob image"));

        vm.prank(alice);
        board.downVote(bobThread);
        vm.prank(carol);
        board.downVote(bobThread);

        assertEq(board.getSocialScore(bob), -2);
        assertEq(board.getFee(bob), board.bzzFee() * 5, "posting is dearer for bob");
        assertEq(board.getVoteFee(), board.bzzFee(), "but voting is not");

        uint256 bobBefore = bzz.balanceOf(bob);
        vm.prank(bob);
        board.upVote(threadId);

        assertEq(bobBefore - bzz.balanceOf(bob), board.bzzFee(), "bob pays the flat vote fee");
    }

    /// An author who has gone away must not make their thread uncommentable.
    function test_expiredTargetBatchFallsBackToProject() public {
        vm.prank(alice);
        board.createThread(bytes32("image"), ALICE_BATCH);
        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        stamp.expireBatch(ALICE_BATCH);

        uint256 projectBefore = stamp.toppedUp(PROJECT_BATCH);
        uint256 fee = _postFee(bob);
        uint256 bobBefore = bzz.balanceOf(bob);

        vm.prank(bob);
        board.createComment(threadId, bytes32("still works"), BOB_BATCH);

        assertEq(board.getThread(threadId).commentIds.length, 1, "the comment still lands");
        // the target share could not be placed, so only the project share was charged
        assertEq(stamp.toppedUp(PROJECT_BATCH) - projectBefore, _projectShare(fee));
        assertEq(bobBefore - bzz.balanceOf(bob), _projectShare(fee), "the rest is refunded");
    }

    function test_batchTooDeepForTheFeeFallsBackToProject() public {
        vm.prank(alice);
        board.createThread(bytes32("image"), ALICE_BATCH);
        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        // a batch so deep that the per chunk amount rounds away entirely
        bytes32 deepBatch = keccak256("deep");
        stamp.createBatch(deepBatch, alice, 60);
        vm.prank(alice);
        board.setBatchId(deepBatch);

        uint256 projectBefore = stamp.toppedUp(PROJECT_BATCH);
        uint256 fee = _postFee(bob);

        vm.prank(bob);
        board.createComment(threadId, bytes32("gm"), BOB_BATCH);

        assertEq(board.getThread(threadId).commentIds.length, 1);
        assertEq(stamp.toppedUp(PROJECT_BATCH) - projectBefore, fee, "the whole fee falls back");
    }

    function test_unsetProjectBatchDoesNotBlockPosting() public {
        board.setPinkchainsawBatchId(bytes32(0));

        uint256 aliceBefore = bzz.balanceOf(alice);

        vm.prank(alice);
        board.createThread(bytes32("image"), ALICE_BATCH);

        assertEq(board.getTotalThreads(), 1, "posting still works before the project batch is set");
        assertEq(bzz.balanceOf(alice), aliceBefore, "and nothing is charged with nowhere to send it");
    }

    function test_projectShareIsCapped() public {
        // read the cap first: an external call here would consume the expectRevert
        uint256 cap = board.MAX_PROJECT_BPS();

        vm.expectRevert("project share above cap");
        board.setProjectBps(cap + 1);

        board.setProjectBps(cap);
        assertEq(board.getProjectBps(), cap);
    }

    function test_onlyOwnerCanConfigureTheProject() public {
        vm.startPrank(alice);

        vm.expectRevert("not owner");
        board.setPinkchainsawBatchId(ALICE_BATCH);

        vm.expectRevert("not owner");
        board.setProjectBps(0);

        vm.stopPrank();
    }

    function test_contractKeepsNoTokens() public {
        vm.prank(alice);
        board.createThread(bytes32("image"), ALICE_BATCH);
        bytes32 threadId = board.getPaginatedThreadIds(1, 1)[0];

        vm.prank(bob);
        board.createComment(threadId, bytes32("gm"), BOB_BATCH);

        vm.prank(carol);
        board.upVote(threadId);

        assertEq(bzz.balanceOf(address(board)), 0, "fees are forwarded or refunded, never retained");
    }
}
