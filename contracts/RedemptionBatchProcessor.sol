// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;
import "./MoTokenManager.sol";
import "./CurrencyOracle.sol";

/// @title Token Redemption Batch Processor
/// @notice This contract handles the token redemption process

contract RedemptionBatchProcessor is Ownable, RWAManager {
    /// @notice This struct holds the request details raised by a user

    struct RedemptionRequest {
        uint256 requestTokens;
        uint256 requestTokensPending;
    }

    /// notice This struct holds all the details regarding a redemption batch

    struct Batch {
        mapping(address => RedemptionRequest) requests;
        address[] userList;
        uint256 batchTokensPending;
    }

    /// @dev An array of all the Batch instances created till date
    Batch[] private allBatches;

    /// @dev Index of the batches which are yet to be fulfilled
    uint256 private batchHead;

    /// @dev Index beyond the latest batch
    uint256 private batchTail;

    /// @dev Token manager contract associated with the batch processor
    address private tokenManager;

    /// @dev The refund is always issued in a fixed assigned stablecoin
    bytes32 private assignedRefundCoin;

    /// @dev Assigned fiat currency for the token
    bytes32 private fiatCurrency = "USD";

    /// @dev Difference between the decimals of MoToken and assigned refund coin
    uint8 private decimalsDiff;

    /// @dev Currency Oracle Address contract associated with the batch processor
    address private currencyOracleAddress;

    event BatchCreated(uint256 indexed id, address indexed creator);
    event RedeemRequestCreated(address indexed user, uint256 indexed tokens);
    event RedeemRequestCancelled(address indexed user, uint256 indexed batchId);
    event BatchFulfilled(
        uint256 indexed id,
        uint256 indexed tokens,
        bool indexed closed
    );
    event CurrencyOracleAddressSet(address indexed currencyOracleAddress);
    event RefundCoinSet(bytes32 indexed _coin);
    event FiatCurrencySet(bytes32 indexed _currency);

    /// @notice Constructor initializes token manager
    /// @dev In addition to the above, the constructor is also assigning USDC as default refund coin
    /// @param _tokenManager Token manager address

    constructor(address _tokenManager) {
        tokenManager = _tokenManager;
        assignedRefundCoin = "USDC";
        decimalsDiff = MoTokenManager(_tokenManager).getDecimalsDiff(
            assignedRefundCoin
        );
    }

    /// @notice Setter for assigned refund coin
    /// @param _coin Refund coin symbol

    function setAssignedRefundCoin(bytes32 _coin) external onlyOwner {
        assignedRefundCoin = _coin;
        decimalsDiff = MoTokenManager(tokenManager).getDecimalsDiff(
            assignedRefundCoin
        );
        emit RefundCoinSet(assignedRefundCoin);
    }

    /// @notice Allows setting currencyOracleAddress
    /// @param _currencyOracleAddress address of the currency oracle

    function setCurrencyOracleAddress(address _currencyOracleAddress)
        external
        onlyOwner
    {
        currencyOracleAddress = _currencyOracleAddress;
        emit CurrencyOracleAddressSet(currencyOracleAddress);
    }

    /// @notice Allows getting currencyOracleAddress
    /// @return address returns currencyOracleAddress

    function getCurrencyOracleAddress() public view returns (address) {
        return currencyOracleAddress;
    }

    /// @notice Allows setting fiatCurrecy
    /// @param _fiatCurrency fiatCureency

    function setFiatCurrency(bytes32 _fiatCurrency) external onlyOwner {
        fiatCurrency = _fiatCurrency;
        emit FiatCurrencySet(fiatCurrency);
    }

    /// @notice Allows getting fiatCurrency associated with tokes
    /// @return bytes32 returns fiatCurrency

    function getFiatCurrency() external view returns (bytes32) {
        return fiatCurrency;
    }

    function addRWAManager(address _account) external onlyOwner {
        _addRWAManager(_account);
    }

    /// @notice Allows removing an address from RWA Manager role
    /// @param _account address from which RWA Manager role is to be removed

    function removeRWAManager(address _account) external onlyOwner {
        _removeRWAManager(_account);
    }

    /// @notice Creates a new batch\

    function createBatch() external onlyRWAManager {
        allBatches.push();
        batchTail++;
        emit BatchCreated(batchTail, msg.sender);
    }

    /// @notice Close all the completed batches

    function closeBatches() internal {
        while (
            batchHead < batchTail &&
            allBatches[batchHead].batchTokensPending == 0
        ) {
            batchHead++;
        }
    }

    /// @notice Create a new redeem request in the current batch
    /// @param _tokens The amount of tokens to redeem

    function createRedeemRequest(uint256 _tokens) external {
        require(
            _tokens > 0 &&
                allBatches[batchTail - 1]
                    .requests[msg.sender]
                    .requestTokensPending ==
                0,
            "NA"
        );

        MoTokenManager manager = MoTokenManager(tokenManager);
        MoToken token = MoToken(manager.getTokenAddress());
        require(token.balanceOf(msg.sender) >= _tokens, "NT");

        if (allBatches[batchTail - 1].requests[msg.sender].requestTokens == 0) {
            allBatches[batchTail - 1].requests[msg.sender] = RedemptionRequest(
                0,
                0
            );
            allBatches[batchTail - 1].userList.push(msg.sender);
        }

        require(token.receiveTokens(msg.sender, _tokens));
        allBatches[batchTail - 1].requests[msg.sender].requestTokens = _tokens;
        allBatches[batchTail - 1]
            .requests[msg.sender]
            .requestTokensPending = _tokens;
        allBatches[batchTail - 1].batchTokensPending =
            allBatches[batchTail - 1].batchTokensPending +
            _tokens;

        emit RedeemRequestCreated(msg.sender, _tokens);
    }

    /// @notice Cancel an existing redeem in the given batch
    /// @param _id Batch id where the redeem request is to be cancelled

    function cancelRedeemRequest(uint256 _id) external {
        require(
            allBatches[_id].requests[msg.sender].requestTokensPending > 0,
            "NR"
        );

        MoTokenManager manager = MoTokenManager(tokenManager);
        MoToken token = MoToken(manager.getTokenAddress());
        require(
            token.transferTokens(
                msg.sender,
                allBatches[_id].requests[msg.sender].requestTokensPending
            )
        );

        allBatches[_id].batchTokensPending =
            allBatches[_id].batchTokensPending -
            allBatches[_id].requests[msg.sender].requestTokensPending;
        allBatches[_id].requests[msg.sender].requestTokensPending = 0;

        emit RedeemRequestCancelled(msg.sender, _id);
    }

    /// @notice Fulfill the redeem requests in the given batch
    /// @param _id Batch Id
    /// @param _amount The stablecoin amount which is used to issue refunds

    function fulfillBatch(uint256 _id, uint256 _amount)
        external
        onlyRWAManager
    {
        if (allBatches[_id].batchTokensPending == 0) {
            closeBatches();
            return;
        }

        MoTokenManager manager = MoTokenManager(tokenManager);
        MoToken token = MoToken(manager.getTokenAddress());

        uint256 nav = uint256(manager.getNAV());
        uint256 refundTokens = (_amount * 10**6) / nav;

        require(
            _id >= batchHead &&
                allBatches[_id].batchTokensPending >= refundTokens,
            "BD"
        );

        CurrencyOracle currencyOracle = CurrencyOracle(currencyOracleAddress);
        (uint64 stableToFiatConvRate, uint8 decimalsVal) = currencyOracle
            .getFeedLatestPriceAndDecimals(assignedRefundCoin, fiatCurrency);

        //ensure sufficient balance
        require(
            ((_amount * 10**decimalsVal) / stableToFiatConvRate) <=
                manager.balanceOf(
                    assignedRefundCoin,
                    manager.getTokenAddress()
                ),
            "NF"
        );

        if (refundTokens == allBatches[_id].batchTokensPending) {
            for (
                uint256 itr = 0;
                itr < allBatches[_id].userList.length;
                itr++
            ) {
                address user = allBatches[_id].userList[itr];

                // refund amount in fiat
                uint256 refundAmount = ((allBatches[_id]
                    .requests[user]
                    .requestTokensPending * nav) / 10**6) / 10**(decimalsDiff);

                // refund amount in stable coins
                refundAmount =
                    (refundAmount * (10**decimalsVal)) /
                    stableToFiatConvRate;
                require(_transferStableCoins(user, refundAmount));
                token.burn(
                    allBatches[_id].requests[user].requestTokensPending,
                    manager.getTokenAddress()
                );
                allBatches[_id].requests[user].requestTokensPending = 0;
            }

            allBatches[_id].batchTokensPending = 0;
            closeBatches();
            emit BatchFulfilled(_id, refundTokens, true);
        } else {
            for (
                uint256 itr = 0;
                itr < allBatches[_id].userList.length;
                itr++
            ) {
                address user = allBatches[_id].userList[itr];
                uint256 userRefund = (allBatches[_id]
                    .requests[user]
                    .requestTokensPending * refundTokens) /
                    allBatches[_id].batchTokensPending;
                // refund amount in fiat
                uint256 refundAmount = ((userRefund * nav) / 10**6) /
                    10**(decimalsDiff);

                // refund amount in stable coins
                refundAmount =
                    (refundAmount * (10**decimalsVal)) /
                    stableToFiatConvRate;

                require(_transferStableCoins(user, refundAmount));
                token.burn(userRefund, manager.getTokenAddress());
                allBatches[_id].requests[user].requestTokensPending =
                    allBatches[_id].requests[user].requestTokensPending -
                    userRefund;
            }
            allBatches[_id].batchTokensPending =
                allBatches[_id].batchTokensPending -
                refundTokens;
            emit BatchFulfilled(_id, refundTokens, false);
        }
    }

    /// @notice Getter for batch range details
    /// @return head Index of the earliest unfulfilled batch
    /// @return tail Index beyond the latest batch

    function getOpenBatchRange()
        external
        view
        returns (uint256 head, uint256 tail)
    {
        return (batchHead, batchTail);
    }

    /// @notice Getter for all the users who have raised redemption request
    /// @param _id Batch Id
    /// @return userList Array of all the users who have raised redemption request

    function getBatchUsers(uint256 _id)
        external
        view
        returns (address[] memory userList)
    {
        return (allBatches[_id].userList);
    }

    /// @notice Getter for Request details
    /// @param _id Batch Id
    /// @param _user Address of user who has raised the redemption request
    /// @return request Total requested amount
    /// @return pending Requested amount pending

    function getBatchRequestDetails(uint256 _id, address _user)
        external
        view
        returns (uint256 request, uint256 pending)
    {
        return (
            allBatches[_id].requests[_user].requestTokens,
            allBatches[_id].requests[_user].requestTokensPending
        );
    }

    /// @notice Getter for tokens pending redemption in the whole batch
    /// @param _id Batch Id
    /// @return tokens Amount of tokens pending

    function getBatchTokensPending(uint256 _id)
        external
        view
        returns (uint256 tokens)
    {
        return (allBatches[_id].batchTokensPending);
    }

    /// @notice User can call this function to get total amount of tokens locked for redemption
    /// @return _tokens Amount of tokens locked

    function getLockedTokens() external view returns (uint256 _tokens) {
        for (uint256 id = batchHead; id < batchTail; id++) {
            _tokens =
                _tokens +
                allBatches[id].requests[msg.sender].requestTokensPending;
        }
    }

    /// @notice Initiates stablecoin transfer for refund
    /// @param _to User address who is to be issued refund
    /// @param _amount Stablecoin amount to be refunded
    /// @return bool Stablecoins transfer success/fail

    function _transferStableCoins(address _to, uint256 _amount)
        internal
        returns (bool)
    {
        MoTokenManager manager = MoTokenManager(tokenManager);
        require(
            _amount <=
                manager.balanceOf(
                    assignedRefundCoin,
                    manager.getTokenAddress()
                ),
            "NF"
        );

        MoToken token = MoToken(manager.getTokenAddress());
        return (
            token.transferStableCoins(
                manager.getContractAddress(assignedRefundCoin),
                _to,
                _amount
            )
        );
    }
}
