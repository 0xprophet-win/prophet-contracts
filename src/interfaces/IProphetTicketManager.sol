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
    
    function mintTickets(
        address to,
        uint256 lotteryId,
        uint128 bucketLowerBound,
        uint256 count,
        bytes memory data
    )
        external;

    function burnTickets(
        address from,
        uint256 lotteryId,
        uint128 bucketLowerBound,
        uint256 count
    )
        external;

    function generateTicketId(
        uint256 lotteryId,
        uint128 bucketLowerBound
    )
        external
        pure
        returns (uint256);
}
