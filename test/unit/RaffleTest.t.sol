// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "lib/forge-std/src/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";


contract RaffleTest is Test {

    event EnteredRaffle(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 keyHash;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (entranceFee,
        interval,
        vrfCoordinator,
        keyHash,
        subscriptionId,
        callbackGasLimit,
        link,
        ) = helperConfig.activeNetworkConfig();

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }
        modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.NotEnoughETH.selector);
        raffle.enterRaffle();
    }
    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventsOnEtrance() public {  //gives error??? log != expected log
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

    }

     function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public raffleEntered {

        raffle.performUpkeep("");
        vm.expectRevert(Raffle.RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upKeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upKeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfRaffleIsNotOpen() public raffleEntered {
        raffle.performUpkeep("");
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        (bool upKeepNeeded, ) = raffle.checkUpkeep("");

        assert(raffleState == Raffle.RaffleState.CALCULATING);
        assert(!upKeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsTrueWhenParametersGood() public raffleEntered {
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(upkeepNeeded);
    }

////performUpKeep tests
    function testPerformUpkeepCanOnlyRunIfCheckUpKeepIsTrue() public raffleEntered {
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpKeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.expectRevert(abi.encodeWithSelector(Raffle.RaffleUpkeepNotNeeded.selector, currentBalance, numPlayers, rState));
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered skipFork {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1); // 0 = open, 1 = calculating
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEntered skipFork {
        vm.expectRevert("nonexistent request");

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

        function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered {
        address expectedWinner = address(1);
        uint256 additionalEntrances = 4;
        uint256 startingIndex = 1;

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrances; i++) {
            address player = address(uint160(i));
            hoax(player, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 startingBalance = expectedWinner.balance;

        vm.recordLogs();
        raffle.performUpkeep(""); // emits requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        console.logBytes32(entries[1].topics[1]);
        bytes32 requestId = entries[1].topics[1]; // get the requestId from the logs

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrances + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == startingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}