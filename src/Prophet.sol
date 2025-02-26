// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ILayerZeroReceiver } from "@LayerZero/contracts/interfaces/ILayerZeroReceiver.sol";
import { ILayerZeroUserApplicationConfig } from "@LayerZero/contracts/interfaces/ILayerZeroUserApplicationConfig.sol";
import { ILayerZeroEndpoint } from "@LayerZero/contracts/interfaces/ILayerZeroEndpoint.sol";

import { AccessControlAdminProtection } from "./util/AccessControlAdminProtection.sol";
import { IProphetTicketManager } from "./interfaces/IProphetTicketManager.sol";

import { StargateStruct } from "./interfaces/StargateStruct.sol";
import { IStargateReceiver } from "./interfaces/IStargateReceiver.sol";
import { IStargateRouter } from "./interfaces/IStargateRouter.sol";
import { IPool } from "./interfaces/IPool.sol";

import {
    IProphet,
    Lottery,
    LotteryData,
    LotteryParams
} from "./interfaces/IProphet.sol";
import { IProphetPriceFeed } from "./interfaces/IProphetPriceFeed.sol";

/**
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
    IProphet,
    ReentrancyGuard,
    Pausable,
    AccessControlAdminProtection,
    IStargateReceiver,
    ILayerZeroReceiver,
    ILayerZeroUserApplicationConfig
{
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    struct PoolInfo {
        address token;
        address poolAddress;
        uint256 convertRate;
    }

    // ===================== Constants ===================== //

    // AccessControl roles.
    bytes32 public constant PRICE_SETTER_ROLE = keccak256("PRICE_SETTER_ROLE");
    bytes32 public constant FEE_RECIPIENT_ROLE = keccak256("FEE_RECIPIENT_ROLE");
    bytes32 public constant LOTTERY_MANAGER_ROLE = keccak256("LOTTERY_MANAGER_ROLE");

    uint256 public constant FEE_PRECISION = 100e6; // 100%
    uint256 public constant MAX_FEE_RATE = 20e6; // 20%

    // External contracts.
    IProphetPriceFeed public immutable prophetPriceFeed;
    StargateStruct public stargateStruct;
    ILayerZeroEndpoint public immutable layerZeroEndpoint;
    IProphetTicketManager public immutable ProphetTicketManager;

    // ===================== Storage ===================== //

    mapping(uint16 chainId => uint256 gas) public dstGasReserve;
    uint256 public interchainTransactionFees = 0;

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

    mapping(uint256 => PoolInfo) public _POOL_ID_TO_INFO_; // cache pool info
    mapping(uint16 chainId => uint256 fee) public fundBridgeFee; // fee for bridging funds from chainId -> current chain. (not from current chain -> chainId)
    mapping(address collateralToken => mapping(address account => uint256 refundAmount)) public _USER_REFUND_AMOUNT_;
    mapping(uint16 chainId => bytes trustedRemote) public trustedRemoteLookup;

    // ===================== Constructor ===================== //

    constructor(
        IProphetPriceFeed _prophetPriceFeed,
        StargateStruct memory _stargateStruct,
        ILayerZeroEndpoint _layerZeroEndpoint,
        address _admin,
        IProphetTicketManager _prophetTicketManager
    )
    {
        // Set immutable variables.
        prophetPriceFeed = _prophetPriceFeed;
        stargateStruct = _stargateStruct;
        layerZeroEndpoint = _layerZeroEndpoint;
        ProphetTicketManager = _prophetTicketManager;

        // Set storage.
        _setFeeRate(1*1e5); // 0.1%

        // Grant admin role.
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
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
        uint256 _feeRate
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setFeeRate(_feeRate);
    }

    function setDstGasReserve(uint16 _chainId, uint256 _dstGasReserve) whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) external {
        dstGasReserve[_chainId] = _dstGasReserve;
    }

    function setFundBridgeFee(uint16 _chainId, uint256 _fundBridgeFee) public onlyRole(DEFAULT_ADMIN_ROLE) {
        fundBridgeFee[_chainId] = _fundBridgeFee;
    }

    // ===================== Admin-Only External Functions (Hot) ===================== //

    function extractNative(uint256 amount) onlyRole(DEFAULT_ADMIN_ROLE) external {
        if(amount == 0){
            amount = interchainTransactionFees;
        }
        require(amount <= interchainTransactionFees);
        interchainTransactionFees -= amount;
        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent);
    }

    function createLottery(
        LotteryParams calldata _lotteryParams
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(LOTTERY_MANAGER_ROLE)
    {
        require(
            _lotteryParams.openTimestamp > block.timestamp,
            "invalid openTimestamp"
        );
        require(
            _lotteryParams.closeTimestamp > _lotteryParams.openTimestamp,
            "invalid closeTimestamp"
        );
        require(
            _lotteryParams.maturityTimestamp > _lotteryParams.closeTimestamp,
            "invalid maturityTimestamp"
        );
        require(
            _lotteryParams.bucketSize > 0,
            "invalid bucketSize"
        );

        uint256 lotteryId = ++_LAST_LOTTERY_ID_;
        _LOTTERIES_[lotteryId].params = _lotteryParams;

        emit LotteryCreated(
            lotteryId,
            _lotteryParams
        );
    }

    /**
     * @notice Set the ticket prices for a lottery.
     */
    function setLotteryTicketsPrice(
        uint256 _lotteryId,
        uint256 _firstBucketLowerBound,
        uint256[] calldata _bucketTicketPrices
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(PRICE_SETTER_ROLE)
    {
        Lottery storage lottery = _getLottery(_lotteryId);

        require(
            _bucketTicketPrices.length > 0,
            "empty price list"
        );
        require(
            block.timestamp < lottery.params.closeTimestamp,
            "lottery closed"
        );

        // Set the ticket prices for each bucket.
        lottery.firstBucketLowerBound = _firstBucketLowerBound;
        lottery.bucketTicketPrices = _bucketTicketPrices;

        // Set the ticket prices for all buckets outside the range of the _bucketTicketPrices array.
        uint256 firstPrice = _bucketTicketPrices[0];
        uint256 lastPrice = _bucketTicketPrices[_bucketTicketPrices.length - 1];
        lottery.minimumTicketPrice = firstPrice < lastPrice ? firstPrice : lastPrice;

        emit SetLotteryPrices(
            _lotteryId,
            _firstBucketLowerBound,
            lottery.minimumTicketPrice,
            _bucketTicketPrices
        );
    }

    /**
     * @notice Transfer proceeds from a previous lottery to a current lottery.
     *
     *  This can only be called if the previous lottery has matured without a winner.
     */
    function transferProceeds(
        uint256 _prevLotteryId,
        uint256 _forwardLotteryId
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(LOTTERY_MANAGER_ROLE)
    {
        Lottery storage prevLottery = _getLottery(_prevLotteryId);
        Lottery storage forwardLottery = _getLottery(_forwardLotteryId);

        require(
            prevLottery.params.collateralToken == forwardLottery.params.collateralToken,
            "collateral token mismatch"
        );
        require(
            block.timestamp >= prevLottery.params.maturityTimestamp,
            "lottery not matured"
        );

        if (!prevLottery.isResolved) {
            _resolveLottery(_prevLotteryId);
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
            _prevLotteryId,
            _forwardLotteryId
        );
    }

    /**
     * @notice Add bonus proceeds to a lottery by making an ERC-20 transfer.
     */
    function addProceeds(
        uint256 _lotteryId,
        uint256 _amount
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(LOTTERY_MANAGER_ROLE)
    {
        Lottery storage lottery = _getLottery(_lotteryId);

        require(
            block.timestamp < lottery.params.closeTimestamp,
            "lottery closed"
        );

        _addProceedsViaTransfer(lottery, _msgSender(), _amount);

        emit AddProceeds(
            _lotteryId,
            _amount
        );
    }

    /**
     * @notice Withdraw protocol fees.
     */
    function withdrawFees(
        address _recipient,
        IERC20 _token,
        uint256 _amount
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(LOTTERY_MANAGER_ROLE)
    {
        require(
            hasRole(FEE_RECIPIENT_ROLE, _recipient),
            "Invalid recipient"
        );
        require(
            _amount <= _FEE_COLLECTED_[_token],
            "amount too large"
        );

        _FEE_COLLECTED_[_token] -= _amount;

        _token.safeTransfer(
            _recipient,
            _amount
        );

        emit FeeWithdrawn(
            _recipient,
            _amount
        );
    }

    function setTrustedRemote(uint16 _remoteChainId, bytes calldata _path) external onlyRole(DEFAULT_ADMIN_ROLE) {
        trustedRemoteLookup[_remoteChainId] = _path;
        emit SetTrustedRemote(_remoteChainId, _path);
    }

    function setTrustedRemoteAddress(uint16 _remoteChainId, bytes calldata _remoteAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        trustedRemoteLookup[_remoteChainId] = abi.encodePacked(_remoteAddress, address(this));
    }

    // ===================== Other External Functions ===================== //

    /**
     * @notice Buy lottery tickets.
     * @param _lotteryId  the lottery to buy the tickets on
     * @param _bucketLowerBound  lower bound of the range to but tickets from
     * @param _buyTicketCount  number of tickets to buy
     */
    function buyTickets(
        uint256 _lotteryId,
        uint128 _bucketLowerBound,
        uint256 _buyTicketCount,
        address _receiver
    )
        external
        nonReentrant
        whenNotPaused
    {
        _buyTickets(_lotteryId,_bucketLowerBound,_buyTicketCount, _msgSender(), _receiver, false, address(0), 0);
    }

    /**
     * @notice Buy lottery tickets.
     * @param _lotteryId  the lottery to buy the tickets on
     * @param _multiBucketLowerBound  list of lower bounds of the ranges to buy tickets from
     * @param _multiBuyTicketCount  list of number of tickets to buy from each range
     */
    function buyMultipleTickets(
        uint256 _lotteryId,
        uint128[] calldata _multiBucketLowerBound,
        uint256[] calldata _multiBuyTicketCount,
        address _receiver
    )
        external
        nonReentrant
        whenNotPaused
    {
        require(_multiBucketLowerBound.length == _multiBuyTicketCount.length, "Invalid input");
        for(uint i = 0; i < _multiBucketLowerBound.length; i++){
            _buyTickets(_lotteryId,_multiBucketLowerBound[i],_multiBuyTicketCount[i], _msgSender(), _receiver, false, address(0), 0);
        }
    }

    /**
     * @notice Buy lottery tickets on a lottery that exists on a different chain.
     * @param _lotteryId  the lottery to buy the tickets on
     * @param _bucketLowerBound  lower bound of the range to but tickets from
     * @param _buyTicketCount  number of tickets to buy
     * @param _dstChainId  the chain on which the lottery exists
     * @param _srcPoolId  the pool id of the appropriate token on current chain
     * @param _dstPoolId  the pool id of the appropriate token on destination chain
     * @param _amountLD  the amount of tokens we want send to buy tickets
     * @param _minAmountLD  the min amount of tokens we want to get on other chain after slippage
     * @param _to  the address of prophet on the other chain.
     */
    function buyTicketsCrossChain(
        uint256 _lotteryId,
        uint128 _bucketLowerBound,
        uint256 _buyTicketCount,
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        uint256 _amountLD,
        uint256 _minAmountLD,
        address _to
    ) external payable nonReentrant whenNotPaused {
        PoolInfo memory poolInfo = _getPoolInfo(_srcPoolId);
        IERC20(poolInfo.token).safeTransferFrom(_msgSender(), address(this), _amountLD);

        // construct payload (buy info needed on dstChain)
        bytes memory payload = abi.encode(_msgSender(), _lotteryId, _bucketLowerBound, _buyTicketCount);

        // send token to the Prophet address on dstChain
        _sendToChain(_dstChainId, _srcPoolId, _dstPoolId, _amountLD, _minAmountLD, _to, true, payload);
    }

    /**
    * @param  - source chain identifier
    * @param  - source address identifier
    * @param  - message ordering nonce
    * @param _token - token contract
    * @param _amountLD - amount (local decimals) to recieve 
    * @param _payload - bytes containing the toAddress
    */
    function sgReceive(
        uint16,
        bytes memory,
        uint256,
        address _token,
        uint256 _amountLD,
        bytes memory _payload
    ) external override {
        // we use msg.sender here as stargate will not call using a gasless transaction.
        require(msg.sender == address(stargateStruct.STARGATE_COMPOSER), "stargate: only router");
        (
            address sender,
            uint256 lotteryId,
            uint128 bucketLowerBound,
            uint256 buyTicketCount
        ) = abi.decode(_payload, (address, uint256, uint128, uint256));
        _buyTickets(lotteryId, bucketLowerBound, buyTicketCount, sender, sender, true, _token, _amountLD);
    }

    /**
     * @notice claim winnings from lotteries on current chain.
     * @param _lotteryIds  the lotteries to claim winnings from
     */
    function claim(
        uint256[] calldata _lotteryIds
    )
        external
        nonReentrant
        whenNotPaused
    {
        address claimer = _msgSender();
        for (uint256 i = 0; i < _lotteryIds.length;) {
            uint256 lotteryId = _lotteryIds[i];
            _claim(lotteryId, claimer, false, 0, 0, 0);
            unchecked { i++; }
        }
    }

    /**
    * @notice   Trigger the claim process on dstChain by sending a LZ message
    * @dev      The Prophet address on dstChain will handle the request with lzReceive.
                If the lotteryId sent is 0, then the user will be claiming their refunds from the other chain.
     * @notice Buy lottery tickets on a lottery that exists on a different chain.
     * @param _lotteryId  the lottery to buy the tickets on
     * @param _dstChainId  the chain on which the lottery exists
     * @param _srcPoolId  the pool id of the appropriate token on current chain
     * @param _dstPoolId  the pool id of the appropriate token on destination chain
     * @param _dstChainGas  the gas we want to use on the transaction on the other chain
     */
    function claimOnChain(
        uint256 _lotteryId,
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        uint256 _dstChainGas
    )
        external
        payable
        nonReentrant
        whenNotPaused
    {
        address claimer = _msgSender();

        require(msg.value > fundBridgeFee[_dstChainId], "not enough fees");

        interchainTransactionFees+=fundBridgeFee[_dstChainId];
        require(_dstChainGas >= dstGasReserve[_dstChainId], "not enough dstgas");

        bytes memory trustedRemote = trustedRemoteLookup[_dstChainId];
        bytes memory adapterParams = abi.encodePacked(uint16(1), _dstChainGas);
        bytes memory payload = abi.encode(claimer, _lotteryId, _srcPoolId, _dstPoolId);
        layerZeroEndpoint.send{value: msg.value - fundBridgeFee[_dstChainId]}(_dstChainId, trustedRemote, payload, payable(_msgSender()), address(0x0), adapterParams);
    }

    /**
     * @notice Resolve a lottery that has matured.
     */
    function resolveLottery(
        uint256 _lotteryId
    )
        external
        nonReentrant
        whenNotPaused
    {
        _resolveLottery(_lotteryId);
    }

    function getLottery(
        uint256 _lotteryId
    ) external view returns (LotteryData memory) {
        Lottery storage lottery = _getLottery(_lotteryId);
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
        uint256 _lotteryId,
        uint256 _bucketLowerBound
    ) external view returns (uint256) {
        Lottery storage lottery = _getLottery(_lotteryId);
        return lottery.ticketsSoldCounts[_bucketLowerBound];
    }

    // ===================== Public Functions ===================== //

    function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 , bytes calldata _payload) public virtual override {
        // we use msg.sender here as layerzero will not call using a gasless transaction.
        require(msg.sender == address(layerZeroEndpoint));
        bytes memory trustedRemote = trustedRemoteLookup[_srcChainId];
        // if will still block the message pathway from (srcChainId, srcAddress). should not receive message from untrusted remote.
        require(
            _srcAddress.length == trustedRemote.length && trustedRemote.length > 0 && keccak256(_srcAddress) == keccak256(trustedRemote),
            "LzApp: invalid source sending contract"
        );
        (
            address sender,
            uint256 lotteryId,
            uint256 dstPoolId,
            uint256 srcPoolId
        ) = abi.decode(_payload, (address, uint256, uint256, uint256));
        if(lotteryId != 0){
            _claim(lotteryId, sender, true, _srcChainId, srcPoolId, dstPoolId);
        }
        else{
            _giveRefund(sender, _srcChainId, srcPoolId, dstPoolId);
        }
    }

    function quoteInterChainBuyFee(
        uint256 _lotteryId,
        uint128 _bucketLowerBound,
        uint256 _buyTicketCount,
        uint16 _dstChainId,
        uint256 _dstGasForCall,
        address _to
    ) external view returns(uint256, uint256) {
        bytes memory payload = abi.encode(_to, _lotteryId, _bucketLowerBound, _buyTicketCount);
        IStargateRouter.lzTxObj memory _sgTxParams;
        _sgTxParams.dstGasForCall += _dstGasForCall;
        _sgTxParams.dstNativeAddr = abi.encodePacked(_to);

        return stargateStruct.STARGATE_COMPOSER.quoteLayerZeroFee(_dstChainId, 1, abi.encodePacked(_to), payload, _sgTxParams);
    }

    function quoteInterChainClaimFee(
        uint256 _lotteryId,
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address _receiver,
        uint256 _dstChainGas
    )
        external
        view
        returns (uint)
    {
        bytes memory adapterParams = abi.encodePacked(uint16(1), _dstChainGas);
        bytes memory payload = abi.encode(_receiver, _lotteryId, _srcPoolId, _dstPoolId);
        (uint256 lzFee, ) = layerZeroEndpoint.estimateFees(_dstChainId, address(this), payload, false, adapterParams);

        return fundBridgeFee[_dstChainId] + lzFee;
    }

    function exists(
        uint256 _lotteryId
    )
        public
        view
        returns (bool)
    {
        return _lotteryId != 0 && _lotteryId <= _LAST_LOTTERY_ID_;
    }

    /**
     * @dev See {IERC1155-supportsInterface}.
     */
    function supportsInterface(
        bytes4 _interfaceId
    )
        public
        view
        override(AccessControlEnumerable)
        returns (bool)
    {
        return (
            _interfaceId == type(IProphet).interfaceId ||
            AccessControlEnumerable.supportsInterface(_interfaceId)
        );
    }

    // ===================== Internal Functions ===================== //

    function _buyTickets(
        uint256 _lotteryId,
        uint128 _bucketLowerBound,
        uint256 _buyTicketCount,
        address _sender,
        address _receiver,
        bool _fromOtherChain,
        address _collateralToken,
        uint256 _amountLD
    )
    internal
    {
        if(_fromOtherChain){
            if(!exists(_lotteryId)){
                _increaseRefund(_collateralToken, _receiver, _amountLD);
                return;
            }
        }
        Lottery storage lottery = _getLottery(_lotteryId);

        if (_fromOtherChain && _collateralToken != address(lottery.params.collateralToken)) {
            _lotteryId = 0;
        }
        if(block.timestamp < lottery.params.openTimestamp){
            _lotteryId = 0;
        }
        if(lottery.bucketTicketPrices.length <= 0){
            _lotteryId = 0;
        }
        if(block.timestamp >= lottery.params.closeTimestamp){
            _lotteryId = 0;
        }
        if(_buyTicketCount <= 0){
            _lotteryId = 0;
        }
        if(_bucketLowerBound % lottery.params.bucketSize != 0){
            _lotteryId = 0;
        }
        if(_lotteryId == 0){
            if(_fromOtherChain){
                _increaseRefund(_collateralToken, _receiver, _amountLD);
                return;
            }
            else{
                revert();
            }
        }

        // Determine whether the requested bucket is within the range of priced buckets.
        uint256 pricedRange = lottery.bucketTicketPrices.length * lottery.params.bucketSize;
        bool isPricedBucket = (
            _bucketLowerBound >= lottery.firstBucketLowerBound &&
            _bucketLowerBound < lottery.firstBucketLowerBound + pricedRange
        );

        // Get the index of the requested bucket within the priced buckets.
        // If the requested bucket is not within the range of priced buckets, the index will be 0
        // and will be unused.
        uint256 bucketId = isPricedBucket
            ? (
                (_bucketLowerBound - lottery.firstBucketLowerBound) /
                lottery.params.bucketSize
            )
            : 0;

        // Get the price of tickets from the requested bucket.
        uint256 ticketPrice = isPricedBucket
            ? lottery.bucketTicketPrices[bucketId]
            : lottery.minimumTicketPrice;

        // Calculate the total cost of the tickets.
        uint256 ticketsCost = _buyTicketCount * ticketPrice;

        // Charge the buyer for the tickets.
        //
        // Note: Intentionally violating CEI pattern under assumption we are protected by the
        //       reentrancy guard. Charge the buyer before minting tickets.
        if(!_fromOtherChain){
            _addProceedsViaTransfer(lottery, _sender, ticketsCost);
        }
        else{
            if(_amountLD < ticketsCost){
                _increaseRefund(_collateralToken, _receiver, _amountLD);
                return;
            }
            else{
                if((_amountLD - ticketsCost) > 0){
                    _increaseRefund(_collateralToken, _receiver, _amountLD - ticketsCost);
                }
                lottery.proceeds += ticketsCost;
            }
        }

        lottery.ticketsSoldCounts[_bucketLowerBound] += _buyTicketCount;

        ProphetTicketManager.mintTickets(
            _receiver,
            _lotteryId,
            _bucketLowerBound,
            _buyTicketCount,
            ""
        );

        emit BoughtTickets(
            _lotteryId,
            _receiver,
            _bucketLowerBound,
            _buyTicketCount,
            ticketsCost
        );
    }

    function _claim(
        uint256 _lotteryId,
        address _claimer,
        bool _isInterChain,
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId
    ) internal {
        Lottery storage lottery = _getLottery(_lotteryId);

        if (!lottery.isResolved) {
            _resolveLottery(_lotteryId);
        }

        // Note: This will revert if the resolved price does not fit in 128 bits. The lottery
        //       params and price oracle should be chosen to ensure that this cannot occur.
        //       If it does somehow occur, there will be no winning tickets for that lottery
        //       since we disallow purchasing tickets for prices that do not fit in 128 bits.
        uint128 winningBucketLowerBound = lottery.winningBucketLowerBound.toUint128();

        uint256 userWinningTicketBalance = ProphetTicketManager.ticketBalanceOf(
            _claimer,
            _lotteryId,
            winningBucketLowerBound
        );

        uint256 claimAmount = (
            userWinningTicketBalance *
            lottery.proceeds /
            lottery.ticketsSoldCounts[lottery.winningBucketLowerBound]
        );

        if(claimAmount > 0){
            if(_isInterChain){
                _sendToChain(_dstChainId, _srcPoolId, _dstPoolId, claimAmount, 0, _claimer, false, "");
            }
            else{
                lottery.params.collateralToken.safeTransfer(
                    _claimer,
                    claimAmount
                );
            }

            ProphetTicketManager.burnTickets(
                _claimer,
                _lotteryId,
                winningBucketLowerBound,
                userWinningTicketBalance
            );

            emit Claimed(
                _lotteryId,
                _claimer
            );
        }
    }

    function _giveRefund(address _sender, uint16 _srcChainId, uint256 _srcPoolId, uint256 _dstPoolId) internal {
        PoolInfo memory poolInfo = _getPoolInfo(_srcPoolId);
        uint256 claimAmount = _USER_REFUND_AMOUNT_[poolInfo.token][_sender];
        _USER_REFUND_AMOUNT_[poolInfo.token][_sender] = 0;

        _sendToChain(_srcChainId, _srcPoolId, _dstPoolId, claimAmount, 0, _sender, false, "");

        emit Refund(
            _sender,
            poolInfo.token,
            claimAmount,
            true
        );
    }

    /**
    * @dev Send token to another chain with Stargate pool swap
    * @param desChainId ChainID to swap to
    * @param _srcPoolId  Stargate PoolID on current chain
    * @param _dstPoolId  Stargate PoolID on destination Chain
    * @param _amount     Amount to swap
    * @param _minAmount     Min amount to receive
    * @param _receiver   Receiver address on destination chain
    **/
    function _sendToChain(
        uint16 desChainId,
        uint _srcPoolId,
        uint _dstPoolId,
        uint _amount,
        uint _minAmount,
        address _receiver,
        bool _useMsgValueForFee,
        bytes memory _payload
    ) internal {
	    PoolInfo memory poolInfo = _getPoolInfo(_srcPoolId);

		// remove dust
		if (poolInfo.convertRate > 1) _amount = ((_amount / poolInfo.convertRate) * poolInfo.convertRate);
        bytes memory claimerBytes = abi.encodePacked(_receiver);
		IStargateRouter.lzTxObj memory lzTxParams;
		lzTxParams.dstGasForCall = dstGasReserve[desChainId];
		lzTxParams.dstNativeAddr = claimerBytes;

		uint fee;
        address refundAddress;
		if (_useMsgValueForFee) {
			fee = msg.value;
            refundAddress = _msgSender();
		} else {
            // query fee in eth
			(fee, ) = stargateStruct.STARGATE_COMPOSER.quoteLayerZeroFee(desChainId, 1, claimerBytes, "", lzTxParams);
            refundAddress = address(this);
            if(interchainTransactionFees < fee){
                _increaseRefund(poolInfo.token, _receiver, _amount);
                return;
            }
		}

        if(_payload.length > 0){
            stargateStruct.STARGATE_COMPOSER.swap{value: fee}(
                desChainId,
                _srcPoolId,
                _dstPoolId,
                payable(refundAddress),
                _amount,
                _minAmount,
                lzTxParams,
                abi.encodePacked(_receiver),
                _payload
            );
        }
        else{
            stargateStruct.STARGATE_RELAYER.swap{value: fee}(
                desChainId,
                _srcPoolId,
                _dstPoolId,
                payable(refundAddress),
                _amount,
                _minAmount,
                lzTxParams,
                abi.encodePacked(_receiver),
                ""
            );
        }

        if(!_useMsgValueForFee){
            interchainTransactionFees-=fee;
        }
    }

    function _setFeeRate(
        uint256 _feeRate
    ) internal {
        require(
            _feeRate <= MAX_FEE_RATE,
            "feeRate too large"
        );

        _FEE_RATE_ = _feeRate;

        emit FeeRateChanged(
            _feeRate
        );
    }

    function _resolveLottery(
        uint256 _lotteryId
    )
        internal
    {
        Lottery storage lottery = _getLottery(_lotteryId);

        require(
            block.timestamp >= lottery.params.maturityTimestamp,
            "lottery not matured"
        );
        require(
            !lottery.isResolved,
            "lottery already resolved"
        );

        uint256 price = prophetPriceFeed.getHistoricalPrice(
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
            _lotteryId,
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
        Lottery storage _lottery,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20 token = _lottery.params.collateralToken;

        // Note: Intentionally violating CEI pattern to execute transfer before adding proceeds.
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(_spender, address(this), _amount);
        uint256 balanceAfter = token.balanceOf(address(this));

        require(balanceBefore + _amount == balanceAfter, "invalid ERC-20 transfer");

        _lottery.proceeds += _amount;
    }

    function _increaseRefund(address _token, address _user, uint _amount) internal {
        _USER_REFUND_AMOUNT_[_token][_user] += _amount;
        emit Refund(_user, _token, _amount, false);
    }

    function _getLottery(
        uint256 _lotteryId
    )
        internal
        view
        returns (Lottery storage)
    {
        require(
            exists(_lotteryId),
            "invalid lottery id"
        );

        return _LOTTERIES_[_lotteryId];
    }

    function getPoolInfo(uint256 _poolId) external returns (PoolInfo memory poolInfo) {
        return _getPoolInfo(_poolId);
    }

    function _getPoolInfo(uint256 _poolId) internal returns (PoolInfo memory poolInfo) {
        // return early if its already been called
        if (_POOL_ID_TO_INFO_[_poolId].poolAddress != address(0)) {
            return _POOL_ID_TO_INFO_[_poolId];
        }

        address pool = stargateStruct.STARGATE_FACTORY.getPool(_poolId);
        require(address(pool) != address(0), "stargate: pool does not exist");
        IERC20(pool).safeApprove(address(stargateStruct.STARGATE_COMPOSER), type(uint256).max);

        address token = IPool(pool).token();
        require(address(token) != address(0), "stargate: token does not exist");
        IERC20(token).safeApprove(address(stargateStruct.STARGATE_COMPOSER), type(uint256).max);
        IERC20(token).safeApprove(address(stargateStruct.STARGATE_RELAYER), type(uint256).max);

        uint256 convertRate = IPool(pool).convertRate();

        poolInfo = PoolInfo({token: token, poolAddress: pool, convertRate: convertRate});
        _POOL_ID_TO_INFO_[_poolId] = poolInfo;
    }

    receive() external payable {
        interchainTransactionFees+=msg.value;
    }

    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint _configType,
        bytes calldata _config
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        layerZeroEndpoint.setConfig(_version, _chainId, _configType, _config);
    }

    function setSendVersion(uint16 _version) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        layerZeroEndpoint.setSendVersion(_version);
    }

    function setReceiveVersion(uint16 _version) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        layerZeroEndpoint.setReceiveVersion(_version);
    }

    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        layerZeroEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }
}
