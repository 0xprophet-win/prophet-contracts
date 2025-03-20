// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IProphetTicketManager } from "./interfaces/IProphetTicketManager.sol";

/**
 * @title ProphetTicketManager
 * @notice Contract for managing tickets as ERC-1155 tokens.
 */
abstract contract ProphetTicketManager is
    ERC1155,
    IProphetTicketManager
{
    // ===================== Constructor ===================== //

    constructor(
        string memory metadataUri
    )
        ERC1155(metadataUri)
    {}

    // ===================== Public Functions ===================== //

    function ticketBalanceOf(
        address account,
        uint256 lotteryId,
        uint128 bucketLowerBound
    )
        public
        view
        returns (uint256)
    {
        uint256 tokenId = _generateTicketId(lotteryId, bucketLowerBound);
        return balanceOf(account, tokenId);
    }

    // ===================== Internal Functions ===================== //

    function _mintTickets(
        address to,
        uint256 lotteryId,
        uint128 bucketLowerBound,
        uint256 count,
        bytes memory data
    )
        internal
    {
        uint256 tokenId = _generateTicketId(lotteryId, bucketLowerBound);
        _mint(to, tokenId, count, data);
    }

    function _burnTickets(
        address from,
        uint256 lotteryId,
        uint128 bucketLowerBound,
        uint256 count
    )
        internal
    {
        uint256 tokenId = _generateTicketId(lotteryId, bucketLowerBound);
        _burn(from, tokenId, count);
    }

    // ===================== Private Functions ===================== //

    /**
     * @dev Generates the ERC-1155 token ID from a lottery ID and a bucket lower bound.
     *
     * @param lotteryId The lottery ID.
     * @param bucketLowerBound The bucket lower bound, uniquely identifying the bucket.
     *
     * @return The ERC-1155 token ID.
     */
    function _generateTicketId(
        uint256 lotteryId,
        uint128 bucketLowerBound
    )
        private
        pure
        returns (uint256)
    {
        // Note: Lottery ID is an incrementing ID starting from 1. It will not overflow here.
        return (lotteryId << 128) + bucketLowerBound;
    }
}
