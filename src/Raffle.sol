// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/** 
* @title Simple Raffle Contract
* @author semihalpk
* @dev Implements Chainlink VRFv2
 */

contract Raffle is VRFConsumerBaseV2 {
    error NotEnoughETH();
    error NotEnoughTimePassed();
    error TransferFailed();
    error RaffleNotOpen();
    error RaffleUpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval; // duration of the lottery in seconds
    uint256 private s_lastTimeStamp;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    address private s_recentWinner;
    bytes32 private immutable i_keyHash;
    RaffleState private s_raffleState;

    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 keyHash,
        uint64 subscriptionId,
        uint32 callbackGasLimit
        ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_keyHash = keyHash;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }
    function enterRaffle() external payable {
        if (msg.value < i_entranceFee){
            revert NotEnoughETH();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    function checkUpkeep(bytes memory) public view returns (bool upkeepNeeded, bytes memory)
    {
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    function  performUpkeep(bytes calldata) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert RaffleUpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_keyHash,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        emit RequestedRaffleWinner(requestId);
        }
    function fulfillRandomWords(uint256, uint256[] memory randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        (bool success,) = winner.call{value: address(this).balance}("");
        if(!success){
            revert TransferFailed();
        }
        emit PickedWinner(winner);
    }

    function getEntranceFee() external view returns(uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns(RaffleState){
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns(address) {
        return s_recentWinner;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getInterval() external view returns (uint256) {
        return i_interval;
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return s_players.length;
    }
}