// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IProphetTicketManager {

    function ticketBalanceOf(
        address account,
        uint256 lotteryId,
        uint128 bucketLowerBound
    )
        external
        view
        returns (uint256);
}
