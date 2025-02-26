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
import { LotteryData } from "../src/interfaces/IProphet.sol";

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
        prophet.grantRole(FEE_RECIPIENT_ROLE, admin);

        prophetTicketManager.grantRole(TOKEN_MINTER_ROLE, address(prophet));

        vm.mockCall(
            prophetPriceFeed,
            abi.encodeWithSelector(IProphetPriceFeed.getHistoricalPrice.selector),
            abi.encode(17350 * 1e8)
        );

        vm.warp(timeStamp - 120);

        token.transfer(admin, 100e18);
        token.transfer(user1, 100e18);
        token.transfer(user2, 100e18);
        token.transfer(address(prophet), 100e18);

        vm.stopPrank();

        vm.startPrank(admin);
        token.approve(address(prophet), 100e18);
        vm.stopPrank();

        vm.startPrank(user1);
        token.approve(address(prophet), 100e18);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(prophet), 100e18);
        vm.stopPrank();
    }

    function testAddProceeds() public{
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
        LotteryParams memory lot = LotteryParams(
                "BTC",
                500 * 1e8,
                timeStamp,
                timeStamp + 120,
                timeStamp + 240,
                token
        );
        assertEq(prophet.getLottery(1).params.token, lot.token);
        assertEq(prophet.exists(1), true);
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
        assertEq(prophet.getTicketsSoldCount(1, 17000 * 1e8), 5);
        vm.stopPrank();

        vm.startPrank(admin);

        prevBalance = token.balanceOf(admin);
        prophet.addProceeds(1, 1e8);
        assertEq(token.balanceOf(admin), prevBalance - 1e8);

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
        assertEq(token.balanceOf(user1), prevBalance + 5 * 12.744696 * 1e8 * 0.9 + 1e8 * 0.9);
        vm.stopPrank();

        // Check that the user cannot claim a second time.
        vm.startPrank(user1);
        prevBalance = token.balanceOf(user1);
        prophet.claim(lotIdArray);
        assertEq(token.balanceOf(user1), prevBalance);
        vm.stopPrank();

        vm.startPrank(admin);

        prevBalance = token.balanceOf(admin);
        prophet.withdrawFees(admin, token, 1e8*0.1 + 5 * 12.744696 * 1e8 * 0.1);
        assertEq(token.balanceOf(admin), prevBalance + 1e8*0.1 + 5 * 12.744696 * 1e8 * 0.1);
        
        vm.stopPrank();
    }

}
