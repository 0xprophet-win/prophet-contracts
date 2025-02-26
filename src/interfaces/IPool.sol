// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.19;

interface IPool {
    function token() external view returns (address);
    function convertRate() external view returns (uint256);
}