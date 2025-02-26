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

    uint16 dstChainId = 1;

    function setUp() public{
        vm.startPrank(admin);

        token = new MockERC20();

        prophetTicketManager = new ProphetTicketManager("");

        prophet = new Prophet(IProphetPriceFeed(prophetPriceFeed), stargateStruct, layerZeroEndpoint, admin, IProphetTicketManager(prophetTicketManager));
        prophet.grantRole(PRICE_SETTER_ROLE, priceSetter);
        prophet.grantRole(LOTTERY_MANAGER_ROLE, admin);
        prophet.setTrustedRemoteAddress(dstChainId, abi.encodePacked(address(prophet)));
        prophet.setFundBridgeFee(dstChainId, 10);
        prophet.setDstGasReserve(dstChainId, 1e5);

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
        vm.deal(user1, 10 ether);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(prophet), 100e18);
        vm.stopPrank();
    }

    function testSetDstGasReserve() public {
        vm.startPrank(admin);

        assertEq(prophet.dstGasReserve(dstChainId), 100000);
        prophet.setDstGasReserve(dstChainId, 1e8);
        assertEq(prophet.dstGasReserve(dstChainId), 1e8);

        vm.stopPrank();

        vm.startPrank(user1);

        vm.expectRevert();
        prophet.setDstGasReserve(dstChainId, 1e7);

        vm.stopPrank();
    }

    function testCrossChainBuy() public {
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
        uint16 dstChainId = 1;
        uint256 srcPoolId = 1;
        uint256 dstPoolId = 1;
        uint256 amountLD = 5 * 12.744696 * 1e8;
        uint256 minAmountLD = 0;
        uint256 lotteryId = 1;
        uint128 bucketLowerBound = 17000 * 1e8;
        uint256 buyTicketCount = 5;
        bytes memory payload = abi.encode(address(user1), lotteryId, bucketLowerBound, buyTicketCount);
        IStargateRouter.lzTxObj memory lzTxParams;
        lzTxParams.dstGasForCall = prophet.dstGasReserve(dstChainId);
        lzTxParams.dstNativeAddr = abi.encodePacked(user1);

        vm.warp(timeStamp);
        uint256 prevBalance = token.balanceOf(user1);
        vm.mockCall(
            address(stargateStruct.STARGATE_FACTORY),
            abi.encodeWithSelector(IStargateFactory.getPool.selector),
            abi.encode(address(iPool))
        );
        vm.mockCall(
            address(iPool),
            abi.encodeWithSelector(IPool.token.selector),
            abi.encode(address(token))
        );
        vm.mockCall(
            address(iPool),
            abi.encodeWithSelector(IERC20.allowance.selector),
            abi.encode(0)
        );
        vm.mockCall(
            address(iPool),
            abi.encodeWithSelector(IERC20.approve.selector),
            abi.encode()
        );
        vm.mockCall(
            address(iPool),
            abi.encodeWithSelector(IPool.convertRate.selector),
            abi.encode(1)
        );

        bytes memory selector = abi.encodeWithSelector(
            stargateStruct.STARGATE_COMPOSER.swap.selector,
            dstChainId,
            srcPoolId,
            dstPoolId,
            payable(user1),
            amountLD,
            minAmountLD,
            lzTxParams,
            abi.encodePacked(user1),
            payload
        );
        vm.mockCall(
            address(stargateStruct.STARGATE_COMPOSER),
            selector,
            abi.encode()
        );

        prophet.buyTicketsCrossChain(1, 17000 * 1e8, 5, 1, 1, 1, 5 * 12.744696 * 1e8, 0, user1);
        assertEq(token.balanceOf(user1), prevBalance - amountLD);
        assertEq(token.balanceOf(address(prophet)), 100e18 + amountLD);
        vm.stopPrank();


        // stargate recieve buy tickets
        vm.startPrank(address(stargateStruct.STARGATE_COMPOSER));
        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 17000 * 1e8), 0);
        prophet.sgReceive(0, "", 0, address(token), amountLD, payload);
        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 17000 * 1e8), 5);
        vm.stopPrank();

        // resolve lottery
        vm.startPrank(user1);
        vm.warp(timeStamp + 240);
        prophet.resolveLottery(1);
        vm.stopPrank();


        // claim from other chain
        vm.startPrank(user1);
        prevBalance = token.balanceOf(user1);
        uint256 lotId = 1;
        payload = abi.encode(user1, lotId, 1, 1);

        // claim call by user
        vm.mockCall(
            address(stargateStruct.STARGATE_COMPOSER),
            abi.encode(IStargateRouter.quoteLayerZeroFee.selector),
            abi.encode(uint256(0),uint256(0))
        );

        selector = abi.encodeWithSelector(
            ILayerZeroEndpoint.send.selector,
            dstChainId,
            abi.encodePacked(address(prophet), address(prophet)),
            payload,
            user1,
            address(0x0),
            abi.encodePacked(uint16(1), uint256(1e5))
        );
        vm.mockCall(
            address(layerZeroEndpoint),
            selector,
            abi.encode()
        );

        prophet.claimOnChain{value: 1e6 wei}(lotId, 1, 1, 1, 1e5);
        vm.stopPrank();

        // layerzero recieve
        vm.startPrank(address(layerZeroEndpoint));
        vm.mockCall(
            address(stargateStruct.STARGATE_COMPOSER),
            abi.encode(IStargateRouter.quoteLayerZeroFee.selector),
            abi.encode(uint256(0),uint256(0))
        );
        lzTxParams.dstGasForCall = prophet.dstGasReserve(dstChainId);
        lzTxParams.dstNativeAddr = abi.encodePacked(user1);
        selector = abi.encodeWithSelector(
            stargateStruct.STARGATE_RELAYER.swap.selector,
            dstChainId,
            srcPoolId,
            dstPoolId,
            payable(address(prophet)),
            5 * 12.744696 * 1e8 * 0.9,
            minAmountLD,
            lzTxParams,
            abi.encodePacked(user1),
            ""
        );
        vm.mockCall(
            address(stargateStruct.STARGATE_RELAYER),
            selector,
            abi.encode()
        );

        prophet.lzReceive(
            1,
            abi.encodePacked(address(prophet), address(prophet)),
            0,
            payload
        );
        vm.stopPrank();
        vm.startPrank(address(stargateStruct.STARGATE_RELAYER));
        token.transferFrom(address(prophet), user1, 5 * 12.744696 * 1e8 * 0.9);


        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 17000 * 1e8), 0);
        assertEq(token.balanceOf(user1), prevBalance + 5 * 12.744696 * 1e8 * 0.9);

        // Check that user can not claim again
        vm.startPrank(user1);
        prevBalance = token.balanceOf(user1);
        payload = abi.encode(user1, lotId, 1, 1);

        // claim call by user
        vm.mockCall(
            address(stargateStruct.STARGATE_COMPOSER),
            abi.encode(IStargateRouter.quoteLayerZeroFee.selector),
            abi.encode(uint256(0),uint256(0))
        );
        selector = abi.encodeWithSelector(
            ILayerZeroEndpoint.send.selector,
            dstChainId,
            abi.encodePacked(address(prophet), address(prophet)),
            payload,
            user1,
            address(0x0),
            abi.encodePacked(uint16(1), uint256(1e5))
        );
        vm.mockCall(
            address(layerZeroEndpoint),
            selector,
            abi.encode()
        );

        prophet.claimOnChain{value: 1e6 wei}(lotId, 1, 1, 1, 1e5);
        vm.stopPrank();

        // layerzero recieve
        vm.startPrank(address(layerZeroEndpoint));
        vm.mockCall(
            address(stargateStruct.STARGATE_COMPOSER),
            abi.encode(IStargateRouter.quoteLayerZeroFee.selector),
            abi.encode(uint256(0),uint256(0))
        );
        lzTxParams.dstGasForCall = prophet.dstGasReserve(dstChainId);
        lzTxParams.dstNativeAddr = abi.encodePacked(user1);
        selector = abi.encodeWithSelector(
            stargateStruct.STARGATE_RELAYER.swap.selector,
            dstChainId,
            srcPoolId,
            dstPoolId,
            payable(address(prophet)),
            0,
            minAmountLD,
            lzTxParams,
            abi.encodePacked(user1),
            ""
        );
        vm.mockCall(
            address(stargateStruct.STARGATE_RELAYER),
            selector,
            abi.encode()
        );

        prophet.lzReceive(
            1,
            abi.encodePacked(address(prophet), address(prophet)),
            0,
            payload
        );
        vm.stopPrank();
        vm.startPrank(address(stargateStruct.STARGATE_RELAYER));

        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 17000 * 1e8), 0);
        assertEq(token.balanceOf(user1), prevBalance);
        vm.stopPrank();
    }

    function testCrossChainClaimRefund() public {
        vm.startPrank(user1);
        uint16 dstChainId = 1;
        uint256 srcPoolId = 1;
        uint256 dstPoolId = 1;
        uint256 amountLD = 5 * 12.744696 * 1e8;
        uint256 minAmountLD = 0;
        uint256 lotteryId = 1;
        uint128 bucketLowerBound = 17000 * 1e8;
        uint256 buyTicketCount = 5;
        bytes memory payload = abi.encode(address(user1), lotteryId, bucketLowerBound, buyTicketCount);
        IStargateRouter.lzTxObj memory lzTxParams;
        lzTxParams.dstGasForCall = prophet.dstGasReserve(dstChainId);
        lzTxParams.dstNativeAddr = abi.encodePacked(user1);

        vm.warp(timeStamp);
        uint256 prevBalance = token.balanceOf(user1);
        vm.mockCall(
            address(stargateStruct.STARGATE_FACTORY),
            abi.encodeWithSelector(IStargateFactory.getPool.selector),
            abi.encode(address(iPool))
        );
        vm.mockCall(
            address(iPool),
            abi.encodeWithSelector(IPool.token.selector),
            abi.encode(address(token))
        );
        vm.mockCall(
            address(iPool),
            abi.encodeWithSelector(IERC20.allowance.selector),
            abi.encode(0)
        );
        vm.mockCall(
            address(iPool),
            abi.encodeWithSelector(IERC20.approve.selector),
            abi.encode()
        );
        vm.mockCall(
            address(iPool),
            abi.encodeWithSelector(IPool.convertRate.selector),
            abi.encode(1)
        );

        bytes memory selector = abi.encodeWithSelector(
            stargateStruct.STARGATE_COMPOSER.swap.selector,
            dstChainId,
            srcPoolId,
            dstPoolId,
            payable(user1),
            amountLD,
            minAmountLD,
            lzTxParams,
            abi.encodePacked(user1),
            payload
        );
        vm.mockCall(
            address(stargateStruct.STARGATE_COMPOSER),
            selector,
            abi.encode()
        );

        prophet.buyTicketsCrossChain(1, 17000 * 1e8, 5, 1, 1, 1, 5 * 12.744696 * 1e8, 0, user1);
        assertEq(token.balanceOf(user1), prevBalance - amountLD);
        assertEq(token.balanceOf(address(prophet)), 100e18 + amountLD);
        vm.stopPrank();

        // stargate recieve buy tickets
        vm.startPrank(address(stargateStruct.STARGATE_COMPOSER));
        assertEq(prophetTicketManager.ticketBalanceOf(user1, 1, 17000 * 1e8), 0);

        prophet.sgReceive(0, "", 0, address(token), amountLD, payload);

        assertEq(prophet._USER_REFUND_AMOUNT_(address(token), user1), amountLD);
        vm.stopPrank();


        // claim from other chain
        vm.startPrank(user1);
        prevBalance = token.balanceOf(user1);
        uint256 lotId = 0;
        payload = abi.encode(user1, lotId, 1, 1);

        // claim call by user
        IStargateRouter.lzTxObj memory _sgTxParams;
        _sgTxParams.dstGasForCall = prophet.dstGasReserve(dstChainId);
        _sgTxParams.dstNativeAddr = abi.encodePacked(user1);
        selector = abi.encodeWithSelector(
            IStargateRouter.quoteLayerZeroFee.selector,
            dstChainId,
            1,
            _sgTxParams.dstNativeAddr,
            "",
            _sgTxParams
        );
        vm.mockCall(
            address(stargateStruct.STARGATE_COMPOSER),
            selector,
            abi.encode(0,0)
        );

        selector = abi.encodeWithSelector(
            ILayerZeroEndpoint.send.selector,
            dstChainId,
            abi.encodePacked(address(prophet), address(prophet)),
            payload,
            user1,
            address(0x0),
            abi.encodePacked(uint16(1), uint256(1e5))
        );
        vm.mockCall(
            address(layerZeroEndpoint),
            selector,
            abi.encode()
        );

        prophet.claimOnChain{value: 1e6 wei}(lotId, 1, 1, 1, 1e5);
        vm.stopPrank();

        // layerzero recieve
        vm.startPrank(address(layerZeroEndpoint));
        vm.mockCall(
            address(stargateStruct.STARGATE_COMPOSER),
            abi.encode(IStargateRouter.quoteLayerZeroFee.selector),
            abi.encode(uint256(0),uint256(0))
        );
        lzTxParams.dstGasForCall = prophet.dstGasReserve(dstChainId);
        lzTxParams.dstNativeAddr = abi.encodePacked(user1);
        selector = abi.encodeWithSelector(
            stargateStruct.STARGATE_RELAYER.swap.selector,
            dstChainId,
            srcPoolId,
            dstPoolId,
            payable(address(prophet)),
            5 * 12.744696 * 1e8,
            minAmountLD,
            lzTxParams,
            abi.encodePacked(user1),
            ""
        );
        vm.mockCall(
            address(stargateStruct.STARGATE_RELAYER),
            selector,
            abi.encode()
        );

        prophet.lzReceive(
            1,
            abi.encodePacked(address(prophet), address(prophet)),
            0,
            payload
        );
        vm.stopPrank();
        vm.startPrank(address(stargateStruct.STARGATE_RELAYER));
        token.transferFrom(address(prophet), user1, 5 * 12.744696 * 1e8);

        assertEq(token.balanceOf(user1), prevBalance + 5 * 12.744696 * 1e8);
        assertEq(prophet._USER_REFUND_AMOUNT_(address(token), user1), 0);
    }
}