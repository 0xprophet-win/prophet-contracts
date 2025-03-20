// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct LotteryParams {
    string token;
    uint256 bucketSize;
    uint256 openTimestamp;
    uint256 closeTimestamp;
    uint256 maturityTimestamp;
    IERC20 collateralToken;
}

struct Lottery {
    LotteryParams params;

    uint256 firstBucketLowerBound;

    /// @dev Ticket price for each bucket starting from firstBucketLowerBound.
    uint256[] bucketTicketPrices;

    /// @dev The minimum ticket price, taken as the min of the first and last bucket ticket prices.
    uint256 minimumTicketPrice;

    /// @dev Tickets sold for each bucket.
    ///
    ///  Mapping (bucket lower bound) => (no. of tickets sold)
    mapping(uint256 => uint256) ticketsSoldCounts;

    bool isResolved;
    uint256 winningBucketLowerBound;
    uint256 proceeds;
}

/// @dev Contains the non-mapping state from a lottery.
struct LotteryData {
    LotteryParams params;
    uint256 firstBucketLowerBound;
    uint256[] bucketTicketPrices;
    uint256 minimumTicketPrice;
    bool isResolved;
    uint256 winningBucketLowerBound;
    uint256 proceeds;
}

interface IProphet {

    event LotteryCreated (
        uint256 indexed lotteryId,
        LotteryParams params
    );

    event SetLotteryPrices(
        uint256 indexed lotteryId,
        uint256 firstBucketLowerBound,
        uint256 minimumTicketPrice,
        uint256[] bucketTicketPrices
    );

    event BoughtTickets(
        uint256 indexed lotteryId,
        address indexed buyer,
        uint256 bucketLowerBound,
        uint256 ticketsBought,
        uint256 ticketsCost
    );

    event LotteryResolved(
        uint256 indexed lotteryId,
        uint256 resolvedPrice,
        uint256 winningBucketLowerBound
    );

    event Claimed(
        uint256 indexed lotteryId,
        address indexed claimer
    );

    event TransferProceeds(
        uint256 indexed lotteryId,
        uint256 indexed newLotteryId
    );

    event AddProceeds(
        uint256 indexed lotteryId,
        uint256 amount
    );

    event FeeRateChanged(
        uint256 newFeeRate
    );

    event FeeWithdrawn(
        address indexed recipient,
        uint256 amount
    );
}
