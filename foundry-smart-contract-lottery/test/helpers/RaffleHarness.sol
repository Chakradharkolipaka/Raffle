//SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;

import {Raffle} from "../../src/Raffle.sol";

contract RaffleHarness is Raffle {
    //pass the same params as that of Raffle when deployed
    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint32 callbackGasLimit,
        uint256 subscriptionId
    ) Raffle(entranceFee, interval, vrfCoordinator, gasLane, callbackGasLimit, subscriptionId) {}

    function harnessFulfill(uint256[] calldata randomWords) external {
        fulfillRandomWords(1, randomWords);
    }
}
