// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { ERC2771Context } from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { AccessControlAdminProtection } from "./util/AccessControlAdminProtection.sol";
import { ProphetTicketManager } from "./ProphetTicketManager.sol";

import {
    IProphet,
    Lottery,
    LotteryData,
    LotteryParams
} from "./interfaces/IProphet.sol";
import { IProphetPriceFeed } from "./interfaces/IProphetPriceFeed.sol";

/**
 * @title Prophet
 * @notice Contract for creating and managing prediction lotteries.
 *
 *  Assumptions:
 *
 *   The outcome of a prediction lottery is determined using an oracle service conforming to
 *   the IProphetPriceFeed interface. Prices can be scaled as deemed appropriate by the price feed,
 *   but all prices should fit in 128 bits. We disallow purchasing tickets for prices that do not
 *   fit in 128 bits.
 *
 *   The collateral token must be an ERC-20 where the change in balance resulting from a token
 *   transfer is exactly equal to the specified transfer amount. This means fee-on-transfer tokens
 *   are not supported, and an attempted payment into the contract with such a mechanism will
 *   revert. Tokens with rebasing mechanisms are also not supported as collateral.
 */
contract Prophet is
    ERC2771Context,
    IProphet,
    ProphetTicketManager,
    ReentrancyGuard,
    Pausable,
    AccessControlAdminProtection
{
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // ===================== Constants ===================== //

    // AccessControl roles.
    bytes32 public constant PRICE_SETTER_ROLE = keccak256("PRICE_SETTER_ROLE");
    bytes32 public constant FEE_RECIPIENT_ROLE = keccak256("FEE_RECIPIENT_ROLE");
    bytes32 public constant LOTTERY_MANAGER_ROLE = keccak256("LOTTERY_MANAGER_ROLE");

    uint256 public constant FEE_PRECISION = 100e6; // 100%
    uint256 public constant MAX_FEE_RATE = 20e6; // 20%

    // External contracts.
    IProphetPriceFeed public immutable PRICE_FEED;

    // ===================== Storage ===================== //

    /// @dev The current rate for protocol fees, as a fraction of FEE_PRECISION.
    uint256 public _FEE_RATE_;

    /// @dev The last lottery ID, or zero if no lotteries were created.
    ///
    ///  This is also equal to the number of lotteries that have been created.
    uint256 public _LAST_LOTTERY_ID_;

    /// @dev Mapping (lotteryId => Lottery) for lottery parameters and state.
    mapping(uint256 => Lottery) private _LOTTERIES_;

    /// @dev Mapping (collateralToken -> feeCollected) for accumulated protocol fees.
    mapping(IERC20 => uint256) public _FEE_COLLECTED_;

    // ===================== Constructor ===================== //

    constructor(
        IProphetPriceFeed prophetPriceFeed,
        uint256 feeRate,
        address admin,
        string memory tokenURI,
        address trustedForwarder
    )
        ProphetTicketManager(tokenURI)
        ERC2771Context(trustedForwarder)
    {
        // Set immutable variables.
        PRICE_FEED = prophetPriceFeed;

        // Set storage.
        _setFeeRate(feeRate);

        // Grant admin role.
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ===================== Admin-Only External Functions (Cold) ===================== //

    function pauseContract()
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _pause();
    }

    function unpauseContract()
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _unpause();
    }

    function setFeeRate(
        uint256 feeRate
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setFeeRate(feeRate);
    }

    function setTicketURI(
        string calldata tokenURI
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setURI(tokenURI);
    }

    // ===================== Admin-Only External Functions (Hot) ===================== //

    /**
     * @notice Create a new lottery.
     */
    function createLottery(
        LotteryParams calldata lotteryParams
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(LOTTERY_MANAGER_ROLE)
    {
        require(
            lotteryParams.openTimestamp > block.timestamp,
            "openTimestamp must be in the future"
        );
        require(
            lotteryParams.closeTimestamp > lotteryParams.openTimestamp,
            "invalid closeTimestamp"
        );
        require(
            lotteryParams.maturityTimestamp > lotteryParams.closeTimestamp,
            "invalid maturityTimestamp"
        );
        require(
            lotteryParams.bucketSize > 0,
            "bucketSize must be greater than 0"
        );

        uint256 lotteryId = ++_LAST_LOTTERY_ID_;
        _LOTTERIES_[lotteryId].params = lotteryParams;

        emit LotteryCreated(
            lotteryId,
            lotteryParams
        );
    }

    /**
     * @notice Set the ticket prices for a lottery.
     */
    function setLotteryTicketsPrice(
        uint256 lotteryId,
        uint256 firstBucketLowerBound,
        uint256[] calldata bucketTicketPrices
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(PRICE_SETTER_ROLE)
    {
        Lottery storage lottery = _getLottery(lotteryId);

        require(
            bucketTicketPrices.length > 0,
            "empty price list"
        );
        require(
            block.timestamp < lottery.params.closeTimestamp,
            "lottery closed"
        );

        // Set the ticket prices for each bucket.
        lottery.firstBucketLowerBound = firstBucketLowerBound;
        lottery.bucketTicketPrices = bucketTicketPrices;

        // Set the ticket prices for all buckets outside the range of the bucketTicketPrices array.
        uint256 firstPrice = bucketTicketPrices[0];
        uint256 lastPrice = bucketTicketPrices[bucketTicketPrices.length - 1];
        lottery.minimumTicketPrice = firstPrice < lastPrice ? firstPrice : lastPrice;

        emit SetLotteryPrices(
            lotteryId,
            firstBucketLowerBound,
            lottery.minimumTicketPrice,
            bucketTicketPrices
        );
    }

    /**
     * @notice Transfer proceeds from a previous lottery to a current lottery.
     *
     *  This can only be called if the previous lottery has matured without a winner.
     */
    function transferProceeds(
        uint256 prevLotteryId,
        uint256 forwardLotteryId
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(LOTTERY_MANAGER_ROLE)
    {
        Lottery storage prevLottery = _getLottery(prevLotteryId);
        Lottery storage forwardLottery = _getLottery(forwardLotteryId);

        require(
            prevLottery.params.collateralToken == forwardLottery.params.collateralToken,
            "collateral token mismatch"
        );
        require(
            block.timestamp >= prevLottery.params.maturityTimestamp,
            "lottery not matured"
        );

        if (!prevLottery.isResolved) {
            _resolveLottery(prevLotteryId);
        }

        // Do not allow transfer if any tickets were sold for the winning bucket.
        if (prevLottery.ticketsSoldCounts[prevLottery.winningBucketLowerBound] != 0) {
            return;
        }

        require(
            block.timestamp >= forwardLottery.params.openTimestamp,
            "lottery not open"
        );
        require(
            block.timestamp < forwardLottery.params.closeTimestamp,
            "lottery closed"
        );

        forwardLottery.proceeds += prevLottery.proceeds;
        prevLottery.proceeds = 0;

        emit TransferProceeds(
            prevLotteryId,
            forwardLotteryId
        );
    }

    /**
     * @notice Add bonus proceeds to a lottery by making an ERC-20 transfer.
     */
    function addProceeds(
        uint256 lotteryId,
        uint256 amount
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(LOTTERY_MANAGER_ROLE)
    {
        Lottery storage lottery = _getLottery(lotteryId);

        require(
            block.timestamp < lottery.params.closeTimestamp,
            "lottery closed"
        );

        _addProceedsViaTransfer(lottery, _msgSender(), amount);

        emit AddProceeds(
            lotteryId,
            amount
        );
    }

    /**
     * @notice Withdraw protocol fees.
     */
    function withdrawFees(
        address recipient,
        IERC20 token,
        uint256 amount
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(LOTTERY_MANAGER_ROLE)
    {
        require(
            hasRole(FEE_RECIPIENT_ROLE, recipient),
            "Invalid recipient"
        );
        require(
            amount <= _FEE_COLLECTED_[token],
            "amount too large"
        );

        _FEE_COLLECTED_[token] -= amount;

        token.safeTransfer(
            recipient,
            amount
        );

        emit FeeWithdrawn(
            recipient,
            amount
        );
    }

    // ===================== Other External Functions ===================== //

    /**
     * @notice Buy lottery tickets.
     */
    function buyTickets(
        uint256 lotteryId,
        uint128 bucketLowerBound,
        uint256 buyTicketCount
    )
        external
        nonReentrant
        whenNotPaused
    {
        Lottery storage lottery = _getLottery(lotteryId);

        require(
            block.timestamp >= lottery.params.openTimestamp,
            "lottery not open"
        );
        require(
            lottery.bucketTicketPrices.length > 0,
            "lottery prices not set"
        );
        require(
            block.timestamp < lottery.params.closeTimestamp,
            "lottery closed"
        );
        require(
            buyTicketCount > 0,
            "count should be greater than 0"
        );
        require(
            bucketLowerBound % lottery.params.bucketSize == 0,
            "invalid bucket lower bound"
        );

        // Determine whether the requested bucket is within the range of priced buckets.
        uint256 pricedRange = lottery.bucketTicketPrices.length * lottery.params.bucketSize;
        bool isPricedBucket = (
            bucketLowerBound >= lottery.firstBucketLowerBound &&
            bucketLowerBound < lottery.firstBucketLowerBound + pricedRange
        );

        // Get the index of the requested bucket within the priced buckets.
        // If the requested bucket is not within the range of priced buckets, the index will be 0
        // and will be unused.
        uint256 bucketId = isPricedBucket
            ? (
                (bucketLowerBound - lottery.firstBucketLowerBound) /
                lottery.params.bucketSize
            )
            : 0;

        // Get the price of tickets from the requested bucket.
        uint256 ticketPrice = isPricedBucket
            ? lottery.bucketTicketPrices[bucketId]
            : lottery.minimumTicketPrice;

        // Calculate the total cost of the tickets.
        uint256 ticketsCost = buyTicketCount * ticketPrice;

        address buyer = _msgSender();

        // Charge the buyer for the tickets.
        //
        // Note: Intentionally violating CEI pattern under assumption we are protected by the
        //       reentrancy guard. Charger the buyer before minting tickets.
        _addProceedsViaTransfer(lottery, buyer, ticketsCost);
        
        lottery.ticketsSoldCounts[bucketLowerBound] += buyTicketCount;

        _mintTickets(
            buyer,
            lotteryId,
            bucketLowerBound,
            buyTicketCount,
            ""
        );

        emit BoughtTickets(
            lotteryId,
            buyer,
            bucketLowerBound,
            buyTicketCount,
            ticketsCost
        );
    }

    /**
     * @notice Claim winnings for one or more lotteries.
     */
    function claim(
        uint256[] calldata lotteryIds
    )
        external
        nonReentrant
        whenNotPaused
    {
        address claimer = _msgSender();

        for (uint256 i = 0; i < lotteryIds.length;) {
            uint256 lotteryId = lotteryIds[i];
            Lottery storage lottery = _getLottery(lotteryId);

            if (!lottery.isResolved) {
                _resolveLottery(lotteryId);
            }

            // Note: This will revert if the resolved price does not fit in 128 bits. The lottery
            //       params and price oracle should be chosen to ensure that this cannot occur.
            //       If it does somehow occur, there will be no winning tickets for that lottery
            //       since we disallow purchasing tickets for prices that do not fit in 128 bits.
            uint128 winningBucketLowerBound = lottery.winningBucketLowerBound.toUint128();

            uint256 userWinningTicketBalance = ticketBalanceOf(
                claimer,
                lotteryId,
                winningBucketLowerBound
            );

            require(
                userWinningTicketBalance > 0,
                "no winning tickets"
            );

            uint256 claimAmount = (
                userWinningTicketBalance *
                lottery.proceeds /
                lottery.ticketsSoldCounts[lottery.winningBucketLowerBound]
            );

            lottery.params.collateralToken.safeTransfer(
                claimer,
                claimAmount
            );

            _burnTickets(
                claimer,
                lotteryId,
                winningBucketLowerBound,
                userWinningTicketBalance
            );

            emit Claimed(
                lotteryId,
                claimer
            );

            unchecked { i++; }
        }
    }

    /**
     * @notice Resolve a lottery that has matured.
     */
    function resolveLottery(
        uint256 lotteryId
    )
        external
        nonReentrant
        whenNotPaused
    {
        _resolveLottery(lotteryId);
    }

    function getLottery(
        uint256 lotteryId
    ) external view returns (LotteryData memory) {
        Lottery storage lottery = _getLottery(lotteryId);
        return LotteryData({
            params: lottery.params,
            firstBucketLowerBound: lottery.firstBucketLowerBound,
            bucketTicketPrices: lottery.bucketTicketPrices,
            minimumTicketPrice: lottery.minimumTicketPrice,
            isResolved: lottery.isResolved,
            winningBucketLowerBound: lottery.winningBucketLowerBound,
            proceeds: lottery.proceeds
        });
    }

    function getTicketsSoldCount(
        uint256 lotteryId,
        uint256 bucketLowerBound
    ) external view returns (uint256) {
        Lottery storage lottery = _getLottery(lotteryId);
        return lottery.ticketsSoldCounts[bucketLowerBound];
    }

    // ===================== Public Functions ===================== //

    function exists(
        uint256 lotteryId
    )
        public
        view
        returns (bool)
    {
        return lotteryId != 0 && lotteryId <= _LAST_LOTTERY_ID_;
    }

    /**
     * @dev See {IERC1155-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(AccessControlEnumerable, ERC1155)
        returns (bool)
    {
        return (
            interfaceId == type(IProphet).interfaceId ||
            AccessControlEnumerable.supportsInterface(interfaceId) ||
            ERC1155.supportsInterface(interfaceId)
        );
    }

    // ===================== Internal Functions ===================== //

    function _setFeeRate(
        uint256 feeRate
    ) internal {
        require(
            feeRate <= MAX_FEE_RATE,
            "feeRate too large"
        );

        _FEE_RATE_ = feeRate;

        emit FeeRateChanged(
            feeRate
        );
    }

    function _resolveLottery(
        uint256 lotteryId
    )
        internal
    {
        Lottery storage lottery = _getLottery(lotteryId);

        require(
            block.timestamp >= lottery.params.maturityTimestamp,
            "lottery not matured"
        );
        require(
            !lottery.isResolved,
            "lottery already resolved"
        );

        uint256 price = PRICE_FEED.getHistoricalPrice(
            lottery.params.token,
            lottery.params.maturityTimestamp
        );

        // Calculate the lower bound of the bucket containing the price at maturity.
        // Each bucket includes its lower bound and excludes its upper bound.
        lottery.winningBucketLowerBound = (
            price /
            lottery.params.bucketSize *
            lottery.params.bucketSize
        );

        // Collect protocol fee off of the proceeds.
        uint256 fee = lottery.proceeds * _FEE_RATE_ / FEE_PRECISION;
        _FEE_COLLECTED_[lottery.params.collateralToken] += fee;
        lottery.proceeds -= fee;

        // Mark the lottery as resolved.
        lottery.isResolved = true;

        emit LotteryResolved(
            lotteryId,
            price,
            lottery.winningBucketLowerBound
        );
    }

    /**
     * @dev Perform ERC-20 transfer of collateral and increase proceeds of a lottery accordingly.
     *
     *  Require that the ERC-20 change in balance is exactly equal to the transfer amount.
     *  This means that ERC-20 tokens with fee-on-transfer mechanisms are not supported.
     */
    function _addProceedsViaTransfer(
        Lottery storage lottery,
        address spender,
        uint256 amount
    ) internal {
        IERC20 token = lottery.params.collateralToken;

        // Note: Intentionally violating CEI pattern to execute transfer before adding proceeds.
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(spender, address(this), amount);
        uint256 balanceAfter = token.balanceOf(address(this));

        require(balanceBefore + amount == balanceAfter, "invalid ERC-20 transfer");

        lottery.proceeds += amount;
    }

    function _getLottery(
        uint256 lotteryId
    )
        internal
        view
        returns (Lottery storage)
    {
        require(
            exists(lotteryId),
            "invalid lottery id"
        );

        return _LOTTERIES_[lotteryId];
    }

    function _msgSender()
        internal
        view
        override(Context, ERC2771Context)
        returns (address)
    {
        return ERC2771Context._msgSender();
    }

    function _msgData()
        internal
        view
        override(Context, ERC2771Context)
        returns (bytes calldata)
    {
        return ERC2771Context._msgData();
    }
}
