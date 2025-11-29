//SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {RaffleHarness} from "../helpers/RaffleHarness.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test {
    Raffle public raffle;
    RaffleHarness public harness;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;

    address public PLAYER = makeAddr("player"); //to interact
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    /**
     * Events
     */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;

        if (block.chainid == 31337) {
            VRFCoordinatorV2_5Mock mockCoordinator = VRFCoordinatorV2_5Mock(vrfCoordinator);
            uint256 harnessSubId = mockCoordinator.createSubscription();
            mockCoordinator.fundSubscription(harnessSubId, 100 ether);

            harness = new RaffleHarness(entranceFee, interval, vrfCoordinator, gasLane, callbackGasLimit, harnessSubId);

            mockCoordinator.addConsumer(harnessSubId, address(harness));
        } else {
            harness =
                new RaffleHarness(entranceFee, interval, vrfCoordinator, gasLane, callbackGasLimit, subscriptionId);
        }

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE); //assigning funds to player
    }

    /*//////////////////////////////////////////////////////////////
                        ENTER RAFFLE TESTS                      
    ////////////////////////////////////////////////////////////////*/
    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertWhenYouDontPayEnough() public {
        //Arrange
        vm.prank(PLAYER);
        //Act/Assert
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public {
        //Arrange
        vm.prank(PLAYER);
        //Act
        raffle.enterRaffle{value: entranceFee}();
        //Assert
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteringRaffleEmistsEvent() public {
        //Arrange
        vm.prank(PLAYER);
        //Act
        vm.expectEmit(true, false, false, false, address(raffle)); //only one indexed param
        emit RaffleEntered(PLAYER);
        //Assert
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); //complete an interval
        vm.roll(block.number + 1); // new block for new interval
        raffle.performUpkeep("");

        //Act/Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    /*//////////////////////////////////////////////////////////////
                         CHECK UPKEEP                         
    ////////////////////////////////////////////////////////////////*/

    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        //Arrange
        vm.warp(block.timestamp + interval + 1); //complete an interval //for testing
        vm.roll(block.number + 1);

        //Act
        (bool upkeepNeeded,) = raffle.checkUpKeep("");

        //assert
        assert(!upkeepNeeded);
    }

    function testUpKeepReturnsFalseIfRaffleIsNotOpen() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); //complete an interval
        vm.roll(block.number + 1); // new block for new interval
        raffle.performUpkeep("");

        //Act
        (bool upkeepNeeded,) = raffle.checkUpKeep("");

        //Assert
        assert(!upkeepNeeded);
    }

    //testCheckUpKeepReturnsFalseIfEnoughTimeHasPassed
    //testCheckUpKeepReturnsTrueWhenParametersAreGood
    function testCheckUpKeepReturnsFalseIFNotEnoughTimeHasPassed() public {
        vm.warp(block.timestamp + interval - 1);
        vm.roll(block.number + 1);

        assert(!raffle.getTimePassed()); //false

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        assert(raffle.getTimePassed()); //true
    }

    function testCheckUpKeepReturnsTrueWhenParametersAreGood() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //act
        (bool upkeepNeeded,) = raffle.checkUpKeep("");

        //assert
        assert(upkeepNeeded);
    }

    /*//////////////////////////////////////////////////////////////
                        PERFORM UPKEEP TESTS                     
    ////////////////////////////////////////////////////////////////*/

    function testPerformUpKeepRevertsIfUpKeepNotNeeded() public {
        vm.prank(PLAYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpKeepNotNeeded.selector,
                address(raffle).balance,
                raffle.getNumberOfPlayers(),
                uint256(raffle.getRaffleState())
            )
        );

        raffle.performUpkeep("");
    }

    function testPerformUpKeepRevertsIfStateNotChangedToCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.CALCULATING));
    }

    /*//////////////////////////////////////////////////////////////
                    FULFILL RANDOM WORDS TESTS                  
    ////////////////////////////////////////////////////////////////*/

    function testFullFillRandomWordsResetStateAndPayWinner() public {
        vm.prank(PLAYER);
        harness.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        harness.performUpkeep("");

        uint256 preWinnerBalance = PLAYER.balance;

        uint256[] memory rw = new uint256[](1);
        rw[0] = 3993;

        vm.expectEmit(true, false, false, false, address(harness));
        emit WinnerPicked(PLAYER);

        harness.harnessFulfill(rw);

        assertEq(uint256(harness.getRaffleState()), uint256(Raffle.RaffleState.OPEN));
        assertEq(harness.getNumberOfPlayers(), 0);
        assertEq(PLAYER.balance, preWinnerBalance + entranceFee);
    }
}
