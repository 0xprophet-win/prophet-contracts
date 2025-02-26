// SPDX_License-Identifier: Unlicense
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ProphetTestERC20 is ERC20 {
    constructor() ERC20("ProphetTest","PTest") {
        _mint(msg.sender, 1000000e18);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}