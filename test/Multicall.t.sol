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
import { Multicall } from "../src/Multicall.sol";

contract TestProphet is Test {

    Multicall public multicall;

    MockERC20 public token;
    MockERC20 public token2;

    address prophetPriceFeed = address(0x5);
    address admin = address(0x1);

    function setUp() public{
        vm.startPrank(admin);

        token = new MockERC20();
        token2 = new MockERC20();

        multicall = new Multicall();

        token.transfer(admin, 100e18);
        token2.transfer(admin, 100e18);
        vm.stopPrank();
    }

    function testMulticall() public{
        vm.startPrank(admin);
        uint balance = token.balanceOf(admin);
        uint balance2 = token2.balanceOf(admin);
        token.transfer(address(multicall), 1e18);
        token2.transfer(address(multicall), 1e18);
        Multicall.Call[] memory calls = new Multicall.Call[](0);
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = token;
        tokens[1] = token2;
        multicall.aggregate(calls, tokens);
        assertEq(token.balanceOf(admin), balance);
        assertEq(token2.balanceOf(admin), balance2);
        vm.stopPrank();
    }

}
