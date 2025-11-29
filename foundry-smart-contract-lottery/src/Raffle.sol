// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

//SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title A sample Raffle contract
 * @author Chakradhar
 * @notice contract for simple raffleImplements
 * @dev Implements Chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /**
     * Errors
     */
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__WaitForMoreTime();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpKeepNotNeeded(uint256 balance, uint256 players, uint256 raffleState); //more info for clarity

    /**
     * Type Declaration
     */
    enum RaffleState {
        OPEN, //0
        CALCULATING //1 ...

    }

    /**
     * State variables
     */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /**
     * Events
     */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint32 callbackGasLimit,
        uint256 subscriptionId
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        //@dev duration of lottery in seconds
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        // require(msg.value >= I_ENTRANCE_FEE , "Not Enough ETH set");
        // require(msg.value >= I_ENTRANCE_FEE , SendMoreToEnterRaffle());

        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle(); //gas efficient than require
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        //makes migration easier
        // makes front end "indexing" easier
        //gas efficient
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev this fn calls ChainLink nodes if the lottery is ready
     * to have a winner picked
     * following should be true to do so:
     * 1.time interval has passed between raffle runs
     * 2.the lottery is open
     * 3.the contract has ETH
     * 4.implicitly , your subscription has LINK
     * @dev this fn works on offchain
     * @param -ignores
     * @return upkeepNeeded - true if its time to restart the lottery
     * @return -ignored
     */
    function checkUpKeep(
        bytes memory /* checkData */ // calldata -> from transaction
    ) public view returns (bool upkeepNeeded, bytes memory /*performData */ ) {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    /**
     * get a random number ->req RNG ->get RNG
     * use random number to pick a player
     * be automatically called
     */
    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upKeepNeeded,) = checkUpKeep("");
        if (!upKeepNeeded) {
            revert Raffle__UpKeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
        s_raffleState = RaffleState.CALCULATING;

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            //passing a struct as param
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash, //max gas price
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit, //gas limit
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes( //returns abi
                        VRFV2PlusClient.ExtraArgsV1({
                            nativePayment: false //set true if you want to pay with native token:ETH ..
                        })
                    )
            })
        );
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal virtual override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);

        (bool success,) = recentWinner.call{value: address(this).balance}(""); //transaction to winner
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * Getter functions -> testing
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getTimePassed() external view returns (bool) {
        return ((block.timestamp - s_lastTimeStamp) >= i_interval);
    }
}
