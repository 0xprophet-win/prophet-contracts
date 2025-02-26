// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IProphetPriceFeed {

    function getHistoricalPrice(
        string calldata token,
        uint256 queryTimestamp
    )
        external
        view
        returns (uint256);

    function getPrice(
        string calldata token
    )
        external
        view
        returns (uint256);
}
