pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Multicall {
    using SafeERC20 for IERC20;


    struct Call {
        address target;
        bytes callData;
    }
    function aggregate(Call[] memory calls, IERC20[] memory tokens) public returns (uint256 blockNumber, bytes[] memory returnData) {
        blockNumber = block.number;
        returnData = new bytes[](calls.length);
        for(uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory ret) = calls[i].target.call(calls[i].callData);
            require(success, "call failed");
            returnData[i] = ret;
        }
        for(uint256 i = 0; i < tokens.length; i++) {
            tokens[i].safeTransfer(msg.sender, tokens[i].balanceOf(address(this)));
        }
    }
}