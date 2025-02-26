// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import "../mocks/MockERC20.sol";
import { IProphetPriceFeed } from "../src/interfaces/IProphetPriceFeed.sol";
import { LotteryParams } from "../src/Prophet.sol";
import { ProphetTicketManager } from "../src/ProphetTicketManager.sol";
import { Prophet } from "../src/Prophet.sol";
import { Lottery } from "../src/Prophet.sol";
import {StargateStruct} from "../src/interfaces/StargateStruct.sol";
import { ILayerZeroEndpoint } from "@LayerZero/contracts/interfaces/ILayerZeroEndpoint.sol";
import {IStargateRouter} from "../src/interfaces/IStargateRouter.sol";
import {IStargateFactory} from "../src/interfaces/IStargateFactory.sol";
import {IProphetTicketManager} from "../src/interfaces/IProphetTicketManager.sol";
import {ProphetTicketManager} from "../src/ProphetTicketManager.sol";
import {IPool} from "../src/interfaces/IPool.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TestProphet is Test {

    Prophet public prophet;
    ProphetTicketManager public prophetTicketManager;

    MockERC20 public token;

    address admin = address(0x1);
    address priceSetter = address(0x2);
    address user1 = address(0x3);
    address user2 = address(0x4);
    address prophetPriceFeed = address(0x5);
    StargateStruct public stargateStruct = StargateStruct(
        IStargateRouter(address(0x6)),
        IStargateRouter(address(0x7)),
        IStargateFactory(address(0x8))
    );
    ILayerZeroEndpoint layerZeroEndpoint = ILayerZeroEndpoint(address(0x9));
    IPool iPool = IPool(address(0xa));

    uint256 timeStamp = 1e7;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x0000000000000000000000000000000000000000000000000000000000000000;
    bytes32 public constant LOTTERY_MANAGER_ROLE = keccak256("LOTTERY_MANAGER_ROLE");
    bytes32 public constant PRICE_SETTER_ROLE = keccak256("PRICE_SETTER_ROLE");
    bytes32 public constant FEE_RECIPIENT_ROLE = keccak256("FEE_RECIPIENT_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant TOKEN_MINTER_ROLE = keccak256("TOKEN_MINTER_ROLE");

    function setUp() public{
        vm.startPrank(admin);

        token = new MockERC20();

        prophetTicketManager = new ProphetTicketManager("");

        prophet = new Prophet(IProphetPriceFeed(prophetPriceFeed), stargateStruct, layerZeroEndpoint, admin, IProphetTicketManager(prophetTicketManager));
        prophet.grantRole(PRICE_SETTER_ROLE, priceSetter);
        prophet.grantRole(LOTTERY_MANAGER_ROLE, admin);

        prophetTicketManager.grantRole(TOKEN_MINTER_ROLE, address(prophet));

        vm.mockCall(
            prophetPriceFeed,
            abi.encodeWithSelector(IProphetPriceFeed.getHistoricalPrice.selector),
            abi.encode(17350 * 1e8)
        );

        vm.warp(timeStamp - 120);

        token.transfer(user1, 100e18);
        token.transfer(user2, 100e18);
        token.transfer(address(prophet), 100e18);

        vm.stopPrank();

        vm.startPrank(user1);
        token.approve(address(prophet), 100e18);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(prophet), 100e18);
        vm.stopPrank();
    }

    function testAdminRoleProtection() public {
        bytes32 adminRole = prophet.DEFAULT_ADMIN_ROLE();

        vm.startPrank(admin);

        vm.expectRevert("last admin cannot renounce");
        prophet.renounceRole(adminRole, admin);

        vm.expectRevert("cannot revoke last admin");
        prophet.revokeRole(adminRole, admin);

        address newAdmin = address(0x11);
        prophet.grantRole(adminRole, newAdmin);

        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert("AccessControl: account 0x0000000000000000000000000000000000000003 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        prophet.revokeRole(adminRole, admin);

        vm.startPrank(newAdmin);

        prophet.revokeRole(adminRole, admin);

        vm.expectRevert("last admin cannot renounce");
        prophet.renounceRole(adminRole, newAdmin);

        vm.expectRevert("cannot revoke last admin");
        prophet.revokeRole(adminRole, newAdmin);

        vm.stopPrank();
    }

    function testProphet() public{
        vm.startPrank(admin);
        prophet.createLottery(
            LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp,
                timeStamp + 120,
                timeStamp + 240,
                token
            )
        );
        vm.stopPrank();
        assertEq(prophet._LAST_LOTTERY_ID_(), 1, "Lottery Id should be 1");

        vm.startPrank(priceSetter);
        uint256[] memory bucketTicketPrices = new uint256[](22);
        bucketTicketPrices[0] = 0.305079 * 1e8;
        bucketTicketPrices[1] = 0.925714 * 1e8;
        bucketTicketPrices[2] = 2.496422 * 1e8;
        bucketTicketPrices[3] = 5.983227 * 1e8;
        bucketTicketPrices[4] = 12.744696 * 1e8;
        bucketTicketPrices[5] = 24.126816 * 1e8;
        bucketTicketPrices[6] = 40.592614 * 1e8;
        bucketTicketPrices[7] = 60.697461 * 1e8;
        bucketTicketPrices[8] = 80.662286 * 1e8;
        bucketTicketPrices[9] = 95.267993 * 1e8;
        bucketTicketPrices[10] = 100.000000 * 1e8;
        bucketTicketPrices[11] = 93.288794 * 1e8;
        bucketTicketPrices[12] = 77.345570 * 1e8;
        bucketTicketPrices[13] = 56.992526 * 1e8;
        bucketTicketPrices[14] = 37.323027 * 1e8;
        bucketTicketPrices[15] = 21.722625 * 1e8;
        bucketTicketPrices[16] = 11.236324 * 1e8;
        bucketTicketPrices[17] = 5.165504 * 1e8;
        bucketTicketPrices[18] = 2.110462 * 1e8;
        bucketTicketPrices[19] = 0.766336 * 1e8;
        bucketTicketPrices[20] = 0.247307 * 1e8;
        bucketTicketPrices[21] = 0.070930 * 1e8;

        prophet.setLotteryTicketsPrice(1, 15000 * 1e8, bucketTicketPrices);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp);
        uint256 prevBalance = token.balanceOf(user1);
        prophet.buyTickets(1, 17000 * 1e8, 5, user1);
        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 17000 * 1e8), 5);
        assertEq(token.balanceOf(user1), prevBalance - 5 * 12.744696 * 1e8);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert("lottery not matured");
        prophet.resolveLottery(1);
        vm.warp(timeStamp + 240);
        prophet.resolveLottery(1);
        vm.stopPrank();

        vm.startPrank(user1);
        prevBalance = token.balanceOf(user1);
        uint256[] memory lotIdArray = new uint256[](1);
        lotIdArray[0] = 1;
        prophet.claim(lotIdArray);
        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 17000 * 1e8), 0);
        assertEq(token.balanceOf(user1), prevBalance + 5 * 12.744696 * 1e8 * 0.9);
        vm.stopPrank();

        // Check that the user cannot claim a second time.
        vm.startPrank(user1);
        prevBalance = token.balanceOf(user1);
        prophet.claim(lotIdArray);
        assertEq(token.balanceOf(user1), prevBalance);
        vm.stopPrank();
    }

    function testProphetMultiBuy() public{
        vm.startPrank(admin);
        prophet.createLottery(
            LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp,
                timeStamp + 120,
                timeStamp + 240,
                token
            )
        );
        vm.stopPrank();
        assertEq(prophet._LAST_LOTTERY_ID_(), 1, "Lottery Id should be 1");

        vm.startPrank(priceSetter);
        uint256[] memory bucketTicketPrices = new uint256[](22);
        bucketTicketPrices[0] = 0.305079 * 1e8;
        bucketTicketPrices[1] = 0.925714 * 1e8;
        bucketTicketPrices[2] = 2.496422 * 1e8;
        bucketTicketPrices[3] = 5.983227 * 1e8;
        bucketTicketPrices[4] = 12.744696 * 1e8;
        bucketTicketPrices[5] = 24.126816 * 1e8;
        bucketTicketPrices[6] = 40.592614 * 1e8;
        bucketTicketPrices[7] = 60.697461 * 1e8;
        bucketTicketPrices[8] = 80.662286 * 1e8;
        bucketTicketPrices[9] = 95.267993 * 1e8;
        bucketTicketPrices[10] = 100.000000 * 1e8;
        bucketTicketPrices[11] = 93.288794 * 1e8;
        bucketTicketPrices[12] = 77.345570 * 1e8;
        bucketTicketPrices[13] = 56.992526 * 1e8;
        bucketTicketPrices[14] = 37.323027 * 1e8;
        bucketTicketPrices[15] = 21.722625 * 1e8;
        bucketTicketPrices[16] = 11.236324 * 1e8;
        bucketTicketPrices[17] = 5.165504 * 1e8;
        bucketTicketPrices[18] = 2.110462 * 1e8;
        bucketTicketPrices[19] = 0.766336 * 1e8;
        bucketTicketPrices[20] = 0.247307 * 1e8;
        bucketTicketPrices[21] = 0.070930 * 1e8;

        prophet.setLotteryTicketsPrice(1, 15000 * 1e8, bucketTicketPrices);
        vm.stopPrank();

        uint128[] memory multiBucketLowerBound = new uint128[](3);
        multiBucketLowerBound[0] = 17000 * 1e8;
        multiBucketLowerBound[1] = 17500 * 1e8;
        multiBucketLowerBound[2] = 18000 * 1e8;

        uint256[] memory multiBuyTicketCount = new uint256[](3);
        multiBuyTicketCount[0] = 5;
        multiBuyTicketCount[1] = 6;
        multiBuyTicketCount[2] = 7;

        vm.startPrank(user1);
        vm.warp(timeStamp);
        uint256 prevBalance = token.balanceOf(user1);
        prophet.buyMultipleTickets(1, multiBucketLowerBound, multiBuyTicketCount, user1);
        uint256 cost = 0;
        for(uint i = 0; i < 3; i++){
            assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, multiBucketLowerBound[i]), multiBuyTicketCount[i]);
            cost += multiBuyTicketCount[i] * bucketTicketPrices[i + 4];
        }
        assertEq(token.balanceOf(user1), prevBalance - cost);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert("lottery not matured");
        prophet.resolveLottery(1);
        vm.warp(timeStamp + 240);
        prophet.resolveLottery(1);
        vm.stopPrank();

        vm.startPrank(user1);
        prevBalance = token.balanceOf(user1);
        uint256[] memory lotIdArray = new uint256[](1);
        lotIdArray[0] = 1;
        prophet.claim(lotIdArray);
        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 17000 * 1e8), 0);
        assertEq(token.balanceOf(user1), prevBalance + ((cost * 90*1e6) / 100e6));
        vm.stopPrank();

        // Check that the user cannot claim a second time.
        vm.startPrank(user1);
        prevBalance = token.balanceOf(user1);
        prophet.claim(lotIdArray);
        assertEq(token.balanceOf(user1), prevBalance);
        vm.stopPrank();
    }

    function testFractions() public{
        vm.startPrank(admin);
        prophet.createLottery(
            LotteryParams(
                "BTC",
                0.37 * 1e8,
                timeStamp,
                timeStamp + 120,
                timeStamp + 240,
                token
            )
        );
        vm.stopPrank();
        assertEq(prophet._LAST_LOTTERY_ID_(), 1, "Lottery Id should be 1");

        vm.startPrank(priceSetter);
        uint256[] memory bucketTicketPrices = new uint256[](22);
        bucketTicketPrices[0] = 0.305079 * 1e8;
        bucketTicketPrices[1] = 0.925714 * 1e8;
        bucketTicketPrices[2] = 2.496422 * 1e8;
        bucketTicketPrices[3] = 5.983227 * 1e8;
        bucketTicketPrices[4] = 12.744696 * 1e8;
        bucketTicketPrices[5] = 24.126816 * 1e8;
        bucketTicketPrices[6] = 40.592614 * 1e8;
        bucketTicketPrices[7] = 60.697461 * 1e8;
        bucketTicketPrices[8] = 80.662286 * 1e8;
        bucketTicketPrices[9] = 95.267993 * 1e8;
        bucketTicketPrices[10] = 100.000000 * 1e8;
        bucketTicketPrices[11] = 93.288794 * 1e8;
        bucketTicketPrices[12] = 77.345570 * 1e8;
        bucketTicketPrices[13] = 56.992526 * 1e8;
        bucketTicketPrices[14] = 37.323027 * 1e8;
        bucketTicketPrices[15] = 21.722625 * 1e8;
        bucketTicketPrices[16] = 11.236324 * 1e8;
        bucketTicketPrices[17] = 5.165504 * 1e8;
        bucketTicketPrices[18] = 2.110462 * 1e8;
        bucketTicketPrices[19] = 0.766336 * 1e8;
        bucketTicketPrices[20] = 0.247307 * 1e8;
        bucketTicketPrices[21] = 0.070930 * 1e8;

        prophet.setLotteryTicketsPrice(1, 0.74 * 1e8, bucketTicketPrices);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp);
        uint256 prevBalance = token.balanceOf(user1);
        prophet.buyTickets(1, 2.59 * 1e8, 5, user1);
        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 2.59 * 1e8), 5);
        assertEq(token.balanceOf(user1), prevBalance - 5 * 24.126816 * 1e8);
        vm.stopPrank();

        vm.mockCall(
            prophetPriceFeed,
            abi.encodeWithSelector(IProphetPriceFeed.getHistoricalPrice.selector),
            abi.encode(2.84 * 1e8)
        );

        vm.startPrank(user1);
        vm.expectRevert("lottery not matured");
        prophet.resolveLottery(1);
        vm.warp(timeStamp + 240);
        prophet.resolveLottery(1);
        vm.stopPrank();

        vm.startPrank(user1);
        prevBalance = token.balanceOf(user1);
        uint256[] memory lotIdArray = new uint256[](1);
        lotIdArray[0] = 1;
        prophet.claim(lotIdArray);
        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 2.59 * 1e8), 0);
        assertEq(token.balanceOf(user1), prevBalance + 5 * 24.126816 * 1e8 * 0.9);
        vm.stopPrank();
    }

    function testPause() public {
        vm.startPrank(admin);
        vm.expectRevert("Pausable: not paused");
        prophet.unpauseContract();
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert("AccessControl: account 0x0000000000000000000000000000000000000003 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        prophet.pauseContract();
        vm.stopPrank();

        vm.startPrank(admin);
        prophet.pauseContract();
        assertEq(prophet.paused(), true);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert("Pausable: paused");
        prophet.createLottery(
            LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp,
                timeStamp + 120,
                timeStamp + 240,
                token
            )
        );
        vm.stopPrank();

        vm.startPrank(admin);
        prophet.unpauseContract();
        assertEq(prophet.paused(), false);
        vm.stopPrank();
    }

    function testSetFeeRate() public {
        vm.startPrank(user1);
        vm.expectRevert("AccessControl: account 0x0000000000000000000000000000000000000003 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        prophet.setFeeRate(10 * 1e6);
        vm.stopPrank();

        vm.startPrank(admin);
        vm.expectRevert("feeRate too large");
        prophet.setFeeRate(25 * 1e6);

        prophet.setFeeRate(10 * 1e6);
        assertEq(prophet._FEE_RATE_(), 10 * 1e6);
        vm.stopPrank();
    }

    function testBuyTickets() public {
        vm.startPrank(admin);
        prophet.createLottery(
            LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp,
                timeStamp + 120,
                timeStamp + 240,
                token
            )
        );
        vm.stopPrank();
        assertEq(prophet._LAST_LOTTERY_ID_(), 1, "Lottery Id should be 1");

        vm.startPrank(user1);
        vm.warp(timeStamp);
        vm.expectRevert();
        prophet.buyTickets(1, 20 * 1e8, 5, user1);
        vm.stopPrank();

        vm.startPrank(priceSetter);
        uint256[] memory bucketTicketPrices = new uint256[](5);
        bucketTicketPrices[0] = 1 * 1e8;
        bucketTicketPrices[1] = 2 * 1e8;
        bucketTicketPrices[2] = 3 * 1e8;
        bucketTicketPrices[3] = 4 * 1e8;
        bucketTicketPrices[4] = 0.5 * 1e8;

        prophet.setLotteryTicketsPrice(1, 15000 * 1e8, bucketTicketPrices);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp);
        uint256 prevBalance = token.balanceOf(user1);
        prophet.buyTickets(1, 16000 * 1e8, 5, user1) ;
        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 16000 * 1e8), 5);
        assertEq(token.balanceOf(user1), prevBalance - 3 * 5 * 1e8);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp);
        prevBalance = token.balanceOf(user1);
        prophet.buyTickets(1, 15000 * 1e8, 5, user1) ;
        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 15000 * 1e8), 5);
        assertEq(token.balanceOf(user1), prevBalance - 1 * 5 * 1e8);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.warp(timeStamp);
        prevBalance = token.balanceOf(user2);
        prophet.buyTickets(1, 20000 * 1e8, 5, user2) ;
        assertEq(prophetTicketManager.ticketBalanceOf(user2, 1, 20000 * 1e8), 5);
        assertEq(token.balanceOf(user2), prevBalance - 0.5 * 5 * 1e8);
        vm.stopPrank();
    }

    function testBuyTicketsWithDifferentReceiver() public {
        vm.startPrank(admin);
        prophet.createLottery(
            LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp,
                timeStamp + 120,
                timeStamp + 240,
                token
            )
        );
        vm.stopPrank();
        assertEq(prophet._LAST_LOTTERY_ID_(), 1, "Lottery Id should be 1");

        vm.startPrank(user1);
        vm.warp(timeStamp);
        vm.expectRevert();
        prophet.buyTickets(1, 20 * 1e8, 5, user1);
        vm.stopPrank();

        vm.startPrank(priceSetter);
        uint256[] memory bucketTicketPrices = new uint256[](5);
        bucketTicketPrices[0] = 1 * 1e8;
        bucketTicketPrices[1] = 2 * 1e8;
        bucketTicketPrices[2] = 3 * 1e8;
        bucketTicketPrices[3] = 4 * 1e8;
        bucketTicketPrices[4] = 0.5 * 1e8;

        prophet.setLotteryTicketsPrice(1, 15000 * 1e8, bucketTicketPrices);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp);
        uint256 prevBalance = token.balanceOf(user1);
        prophet.buyTickets(1, 16000 * 1e8, 5, user2) ;
        assertEq(prophetTicketManager.ticketBalanceOf(user2, 1, 16000 * 1e8), 5);
        assertEq(token.balanceOf(user1), prevBalance - 3 * 5 * 1e8);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp);
        prevBalance = token.balanceOf(user1);
        prophet.buyTickets(1, 15000 * 1e8, 5, user2) ;
        assertEq(prophetTicketManager.ticketBalanceOf(user2, 1, 15000 * 1e8), 5);
        assertEq(token.balanceOf(user1), prevBalance - 1 * 5 * 1e8);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.warp(timeStamp);
        prevBalance = token.balanceOf(user2);
        prophet.buyTickets(1, 20000 * 1e8, 5, user1) ;
        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 20000 * 1e8), 5);
        assertEq(token.balanceOf(user2), prevBalance - 0.5 * 5 * 1e8);
        vm.stopPrank();
    }

    function testBuyTicketsBelowPricedRange() public {
        vm.startPrank(admin);
        prophet.createLottery(
            LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp,
                timeStamp + 120,
                timeStamp + 240,
                token
            )
        );
        vm.stopPrank();

        vm.startPrank(priceSetter);
        uint256[] memory bucketTicketPrices = new uint256[](3);
        bucketTicketPrices[0] = 1 * 1e8;
        bucketTicketPrices[1] = 2 * 1e8;
        bucketTicketPrices[2] = 0.5 * 1e8;
        prophet.setLotteryTicketsPrice(1, 15000 * 1e8, bucketTicketPrices);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp);
        uint256 prevBalance = token.balanceOf(user1);
        uint256 lotteryId = 1;
        uint128 targetPrice = 14000 * 1e8;
        prophet.buyTickets(lotteryId, targetPrice, 5, user1) ;
        assertEq(prophetTicketManager.ticketBalanceOf(user1, lotteryId, targetPrice), 5);
        assertEq(token.balanceOf(user1), prevBalance - 0.5 * 5 * 1e8);
        vm.stopPrank();
    }

    function testBuyTicketsAbovePricedRange() public {
        vm.startPrank(admin);
        prophet.createLottery(
            LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp,
                timeStamp + 120,
                timeStamp + 240,
                token
            )
        );
        vm.stopPrank();

        vm.startPrank(priceSetter);
        uint256[] memory bucketTicketPrices = new uint256[](3);
        bucketTicketPrices[0] = 1 * 1e8;
        bucketTicketPrices[1] = 2 * 1e8;
        bucketTicketPrices[2] = 0.5 * 1e8;
        prophet.setLotteryTicketsPrice(1, 15000 * 1e8, bucketTicketPrices);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp);
        uint256 prevBalance = token.balanceOf(user1);
        uint256 lotteryId = 1;
        uint128 targetPrice = 24000 * 1e8;
        prophet.buyTickets(lotteryId, targetPrice, 5, user1) ;
        assertEq(prophetTicketManager.ticketBalanceOf(user1, lotteryId, targetPrice), 5);
        assertEq(token.balanceOf(user1), prevBalance - 0.5 * 5 * 1e8);
        vm.stopPrank();
    }

    function testBuyTicketsMisalignedPrice() public {
        vm.startPrank(admin);
        prophet.createLottery(
            LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp,
                timeStamp + 120,
                timeStamp + 240,
                token
            )
        );
        vm.stopPrank();

        vm.startPrank(priceSetter);
        uint256[] memory bucketTicketPrices = new uint256[](3);
        bucketTicketPrices[0] = 1 * 1e8;
        bucketTicketPrices[1] = 2 * 1e8;
        bucketTicketPrices[2] = 0.5 * 1e8;
        prophet.setLotteryTicketsPrice(1, 15000 * 1e8, bucketTicketPrices);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp);
        uint256 lotteryId = 1;
        uint128 targetPrice = 15001 * 1e8;
        vm.expectRevert();
        prophet.buyTickets(lotteryId, targetPrice, 5, user1) ;
        vm.stopPrank();
    }

    function testTranferProceeds() public {
        vm.startPrank(admin);
        prophet.createLottery(
            LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp,
                timeStamp + 120,
                timeStamp + 240,
                token
            )
        );

        vm.stopPrank();
        assertEq(prophet._LAST_LOTTERY_ID_(), 1, "Lottery Id should be 1");

        vm.startPrank(priceSetter);
        uint256[] memory bucketTicketPrices = new uint256[](22);
        bucketTicketPrices[0] = 0.305079 * 1e8;
        bucketTicketPrices[1] = 0.925714 * 1e8;
        bucketTicketPrices[2] = 2.496422 * 1e8;
        bucketTicketPrices[3] = 5.983227 * 1e8;
        bucketTicketPrices[4] = 12.744696 * 1e8;
        bucketTicketPrices[5] = 24.126816 * 1e8;
        bucketTicketPrices[6] = 40.592614 * 1e8;
        bucketTicketPrices[7] = 60.697461 * 1e8;
        bucketTicketPrices[8] = 80.662286 * 1e8;
        bucketTicketPrices[9] = 95.267993 * 1e8;
        bucketTicketPrices[10] = 100.000000 * 1e8;
        bucketTicketPrices[11] = 93.288794 * 1e8;
        bucketTicketPrices[12] = 77.345570 * 1e8;
        bucketTicketPrices[13] = 56.992526 * 1e8;
        bucketTicketPrices[14] = 37.323027 * 1e8;
        bucketTicketPrices[15] = 21.722625 * 1e8;
        bucketTicketPrices[16] = 11.236324 * 1e8;
        bucketTicketPrices[17] = 5.165504 * 1e8;
        bucketTicketPrices[18] = 2.110462 * 1e8;
        bucketTicketPrices[19] = 0.766336 * 1e8;
        bucketTicketPrices[20] = 0.247307 * 1e8;
        bucketTicketPrices[21] = 0.070930 * 1e8;

        prophet.setLotteryTicketsPrice(1, 15000 * 1e8, bucketTicketPrices);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp);
        prophet.buyTickets(1, 22000 * 1e8, 5, user1) ;
        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 22000 * 1e8), 5);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.warp(timeStamp);
        prophet.buyTickets(1, 19500 * 1e8, 3, user2);
        assertEq(prophetTicketManager.ticketBalanceOf(user2, 1, 19500 * 1e8), 3);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp + 240);
        uint256 prevBalance = token.balanceOf(user1);
        prophet.resolveLottery(1);
        uint256[] memory prevLotIdArray = new uint256[](1);
        prevLotIdArray[0] = 1;
        vm.expectRevert();
        prophet.claim(prevLotIdArray);
        assertEq(token.balanceOf(user1), prevBalance);
        vm.stopPrank();

        vm.startPrank(admin);
        prophet.createLottery(
            LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp + 360,
                timeStamp + 480,
                timeStamp + 600,
                token
            )
        );
        assertEq(prophet._LAST_LOTTERY_ID_(), 2, "Lottery Id should be 2");
        vm.warp(timeStamp + 360);
        prophet.transferProceeds(1, 2);
        vm.stopPrank();

        vm.startPrank(priceSetter);
        prophet.setLotteryTicketsPrice(2, 15000 * 1e8, bucketTicketPrices);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp + 360);
        prophet.buyTickets(2, 17000 * 1e8, 5, user1) ;
        assertEq(prophetTicketManager.ticketBalanceOf(user1, 2, 17000 * 1e8), 5);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp + 600);
        prevBalance = token.balanceOf(user1);
        prophet.resolveLottery(2);
        uint256[] memory lotIdArray = new uint256[](1);
        lotIdArray[0] = 2;
        prophet.claim(lotIdArray);
        assertEq(token.balanceOf(user1), prevBalance + (5 * 12.744696 + (5 * 37.323027 + 3 * 95.267993) * 0.9) * 1e8 * 0.9);
        vm.stopPrank();
    }

    function testTranferProceedsWithDifferentReceiver() public {
        vm.startPrank(admin);
        prophet.createLottery(
            LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp,
                timeStamp + 120,
                timeStamp + 240,
                token
            )
        );

        vm.stopPrank();
        assertEq(prophet._LAST_LOTTERY_ID_(), 1, "Lottery Id should be 1");

        vm.startPrank(priceSetter);
        uint256[] memory bucketTicketPrices = new uint256[](22);
        bucketTicketPrices[0] = 0.305079 * 1e8;
        bucketTicketPrices[1] = 0.925714 * 1e8;
        bucketTicketPrices[2] = 2.496422 * 1e8;
        bucketTicketPrices[3] = 5.983227 * 1e8;
        bucketTicketPrices[4] = 12.744696 * 1e8;
        bucketTicketPrices[5] = 24.126816 * 1e8;
        bucketTicketPrices[6] = 40.592614 * 1e8;
        bucketTicketPrices[7] = 60.697461 * 1e8;
        bucketTicketPrices[8] = 80.662286 * 1e8;
        bucketTicketPrices[9] = 95.267993 * 1e8;
        bucketTicketPrices[10] = 100.000000 * 1e8;
        bucketTicketPrices[11] = 93.288794 * 1e8;
        bucketTicketPrices[12] = 77.345570 * 1e8;
        bucketTicketPrices[13] = 56.992526 * 1e8;
        bucketTicketPrices[14] = 37.323027 * 1e8;
        bucketTicketPrices[15] = 21.722625 * 1e8;
        bucketTicketPrices[16] = 11.236324 * 1e8;
        bucketTicketPrices[17] = 5.165504 * 1e8;
        bucketTicketPrices[18] = 2.110462 * 1e8;
        bucketTicketPrices[19] = 0.766336 * 1e8;
        bucketTicketPrices[20] = 0.247307 * 1e8;
        bucketTicketPrices[21] = 0.070930 * 1e8;

        prophet.setLotteryTicketsPrice(1, 15000 * 1e8, bucketTicketPrices);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp);
        prophet.buyTickets(1, 22000 * 1e8, 5, user2) ;
        assertEq(prophetTicketManager.ticketBalanceOf(user2, 1, 22000 * 1e8), 5);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.warp(timeStamp);
        prophet.buyTickets(1, 19500 * 1e8, 3, user1);
        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 19500 * 1e8), 3);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp + 240);
        uint256 prevBalance = token.balanceOf(user1);
        prophet.resolveLottery(1);
        uint256[] memory prevLotIdArray = new uint256[](1);
        prevLotIdArray[0] = 1;
        vm.expectRevert();
        prophet.claim(prevLotIdArray);
        assertEq(token.balanceOf(user1), prevBalance);
        vm.stopPrank();

        vm.startPrank(admin);
        prophet.createLottery(
            LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp + 360,
                timeStamp + 480,
                timeStamp + 600,
                token
            )
        );
        assertEq(prophet._LAST_LOTTERY_ID_(), 2, "Lottery Id should be 2");
        vm.warp(timeStamp + 360);
        prophet.transferProceeds(1, 2);
        vm.stopPrank();

        vm.startPrank(priceSetter);
        prophet.setLotteryTicketsPrice(2, 15000 * 1e8, bucketTicketPrices);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(timeStamp + 360);
        prophet.buyTickets(2, 17000 * 1e8, 5, user2) ;
        assertEq(prophetTicketManager.ticketBalanceOf(user2, 2, 17000 * 1e8), 5);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.warp(timeStamp + 600);
        prevBalance = token.balanceOf(user2);
        prophet.resolveLottery(2);
        uint256[] memory lotIdArray = new uint256[](1);
        lotIdArray[0] = 2;
        prophet.claim(lotIdArray);
        assertEq(token.balanceOf(user2), prevBalance + (5 * 12.744696 + (5 * 37.323027 + 3 * 95.267993) * 0.9) * 1e8 * 0.9);
        vm.stopPrank();
    }

    function testTransferProceeds_revertIfCollateralMismatch() public {
        vm.startPrank(admin);
        prophet.createLottery(
            LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp,
                timeStamp + 120,
                timeStamp + 240,
                token
            )
        );
        uint256 timeStampNext = timeStamp + 240;
        prophet.createLottery(
            LotteryParams(
                "ETH",
                500 * 1e8,
                timeStampNext,
                timeStampNext + 120,
                timeStampNext + 240,
                new MockERC20()
            )
        );
        vm.warp(timeStamp + 360);
        vm.expectRevert("collateral token mismatch");
        prophet.transferProceeds(1, 2);
        vm.stopPrank();
    }

    function testSetPrices_revertIfEmptyPriceList() public {
        vm.startPrank(admin);
        prophet.createLottery(
            LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp,
                timeStamp + 120,
                timeStamp + 240,
                token
            )
        );
        vm.stopPrank();

        vm.startPrank(priceSetter);
        uint256[] memory bucketTicketPrices = new uint256[](0);
        vm.expectRevert("empty price list");
        prophet.setLotteryTicketsPrice(1, 15000 * 1e8, bucketTicketPrices);
        vm.stopPrank();
    }
}
