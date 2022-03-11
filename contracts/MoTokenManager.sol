// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./StableCoin.sol";
import "./MoToken.sol";
import "./RWADetails.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./access/RWAManager.sol";

/// @title Token manager
/// @notice This is a token manager which handles all operations related to the token
/// @dev Extending Ownable and RWAManager for role implementation and StableCoin for stable coin related functionalities

contract MoTokenManager is StableCoin, Ownable, RWAManager {
    /// @dev RWA Details contract address which stores real world asset details
    address rWADetails;

    /// @dev Limits the total supply of the token.
    uint256 tokenSupplyLimit;

    /** @notice This struct stores all the properties associated with the token
     *  id - MoToken id
     *  nav - NAV for the token
     *  pipeFiatStash - Fiat amount which is in transmission between the stable coin pipe and the RWA bank account
     *  totalAssetValue - Summation of all the assets owned by the RWA fund that is associated with the MoToken
     */

    struct tokenDetails {
        uint16 id;
        uint32 nav; // 6 decimal shifted
        uint64 pipeFiatStash; // 6 decimal shifted
        uint32 stashUpdateDate;
        uint128 totalAssetValue; // 6 decimal shifted
    }

    tokenDetails private _tokenDetails = tokenDetails(0, 0, 0, 0, 0);

    event Purchase(address indexed user, uint256 indexed tokens);
    event RWADetailsSet(address indexed _address);
    event FiatCurrencySet(bytes32 indexed _currency);
    event FiatCredited(uint64 indexed _amount, uint32 indexed _date);
    event FiatDebited(uint64 indexed _amount, uint32 indexed _date);
    event NAVUpdated(uint32 indexed _nav, uint32 indexed _date);

    /// @notice Initializes basic properties associated with the token
    /// @param _id MoToken Id
    /// @param _token token address
    /// @param _rWADetails RWADeteails contract address

    function initialize(
        uint16 _id,
        address _token,
        address _rWADetails
    ) external {
        require(_tokenDetails.id == 0, "AE");

        _tokenDetails.id = _id;
        token = _token;
        rWADetails = _rWADetails;
        _tokenDetails.nav = 1000000;
        tokenSupplyLimit = 10**24;
    }

    /// @notice Allows adding an address with RWA Manager role
    /// @param _account address to be granted RWA Manager role

    function addRWAManager(address _account) external onlyOwner {
        _addRWAManager(_account);
    }

    /// @notice Allows removing an address from RWA Manager role
    /// @param _account address from which RWA Manager role is to be removed

    function removeRWAManager(address _account) external onlyOwner {
        _removeRWAManager(_account);
    }

    /// @notice Provides address of MoH token
    /// @return address Address of MoH token

    function getTokenAddress() external view returns (address) {
        return token;
    }

    /// @notice Returns address of contract storing RWA details
    /// @return rWADetails Address of contract storing RWADetails

    function getRWADetailsAddress() external view returns (address) {
        return rWADetails;
    }

    /// @notice Setter for RWADetails contract associated with the MoToken
    /// @param _rWADetails Address of contract storing RWADetails

    function setRWADetailsAddress(address _rWADetails) external onlyOwner {
        rWADetails = _rWADetails;
        emit RWADetailsSet(rWADetails);
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

    /// @notice Allows setting fiatCurrecy associated with tokens
    /// @param _fiatCurrency fiatCurrency

    function setFiatCurrency(bytes32 _fiatCurrency) external onlyOwner {
        fiatCurrency = _fiatCurrency;
        emit FiatCurrencySet(fiatCurrency);
    }

    /// @notice Allows getting fiatCurrency associated with tokens
    /// @return bytes32 returns fiatCurrency

    function getFiatCurrency() external view returns (bytes32) {
        return fiatCurrency;
    }

    /// @notice Allows setting tokenSupplyLimit associated with tokens
    /// @param _tokenSupplyLimit limit to be set for the token supply

    function setTokenSupplyLimit(uint256 _tokenSupplyLimit)
        external
        onlyRWAManager
    {
        tokenSupplyLimit = _tokenSupplyLimit;
    }

    /// @notice Gets tokenSupplyLimit associated with tokens
    /// @return uint256 returns tokenSupplyLimit

    function getTokenSupplyLimit() external view returns (uint256) {
        return tokenSupplyLimit;
    }

    /// @notice This function is called by the purchaser of MoH tokens. The protocol transfers _depositCurrency 
	/// from the purchaser and mints and transfers MoH token to the purchaser
	/// @dev _tokenDetails.nav has the NAV (in USD) of the MoH token. The number of MoH tokens to mint = _depositAmount (in USD) / NAV
	/// @param _depositAmount is the amount in USD (shifted by 6 decimal places) that the purchaser wants to send to buy MoH tokens
	/// @param _depositCurrency is the token that purchaser wants to send the amount in (ex: USDC, USDT etc)

	function purchase(uint256 _depositAmount, bytes32 _depositCurrency)
        external
    {
        CurrencyOracle currencyOracle = CurrencyOracle(currencyOracleAddress);
        (uint64 stableToFiatConvRate, uint8 decimalsVal) = currencyOracle
            .getFeedLatestPriceAndDecimals(_depositCurrency, fiatCurrency);
        uint64 navValueInStableCoins = uint64(
            (_tokenDetails.nav * (10**decimalsVal)) / stableToFiatConvRate
        );
        uint256 tokensToMint = (_depositAmount *
            1000000 *
            10**(getDecimalsDiff(_depositCurrency))) / navValueInStableCoins;

        MoToken moToken = MoToken(token);
        require(
            tokenSupplyLimit + moToken.balanceOf(token) >
                moToken.totalSupply() + tokensToMint,
            "LE"
        );
        require(
            initiateTransferFrom({
                _from: msg.sender,
                _amount: _depositAmount,
                _symbol: _depositCurrency
            }),
            "PF"
        );

        moToken.mint(msg.sender, tokensToMint);

        emit Purchase(msg.sender, moToken.balanceOf(msg.sender));
    }

    /// @notice The function allows RWA manger to provide the increase in pipe fiat balances against the MoH token
    /// @param _amount the amount by which RWA manager is increasing the pipeFiatStash of the MoH token
    /// @param _date RWA manager is crediting pipe fiat for this date

    function creditPipeFiat(uint64 _amount, uint32 _date) external onlyRWAManager {
        _tokenDetails.pipeFiatStash += _amount;
        _tokenDetails.stashUpdateDate = _date;
        emit FiatCredited(_tokenDetails.pipeFiatStash, _date);
    }

    /// @notice The function allows RWA manger to decrease pipe fiat balances against the MoH token
    /// @param _amount the amount by which RWA manager is decreasing the pipeFiatStash of the MoH token
    /// @param _date RWA manager is debiting pipe fiat for this date

    function debitPipeFiat(uint64 _amount, uint32 _date) external onlyRWAManager {
        _tokenDetails.pipeFiatStash -= _amount;
        _tokenDetails.stashUpdateDate = _date;
        emit FiatDebited(_tokenDetails.pipeFiatStash, _date);
    }

    /// @notice Allows viewing of pipeFiatStash ([pipe] fiat balance against a MoH token)
    /// @return _tokenDetails.pipeFiatStash - the amount of pipe Fiat held against the MoH token

    function getPipeFiatStash() public view returns (uint64) {
        return _tokenDetails.pipeFiatStash;
    }

    /// @notice Provides the Value of RWA units (Asset Value) held against this MoH token
    /// @return _tokenDetails.totalAssetValue - the total value of RWA units (in pipe fiat) held against this MoH token

    function getAssetValue() external view returns (uint128) {
        return _tokenDetails.totalAssetValue;
    }

    /// @notice Provides the NAV of the MoH token
    /// @return _tokenDetails.nav NAV of the MoH token

    function getNAV() external view returns (uint32) {
        return _tokenDetails.nav;
    }

    /// @notice The function allows the RWA manager to update the NAV. NAV = (Asset value of AFI _ pipe fiat stash in Fiat +
    /// stablecoin balance) / Total supply of the MoH token.
    /// @dev getTotalRWAssetValue gets value of all RWA units held by this MoH token. totalBalanceInFiat() gets stablecoin balances
    /// held by this MoH token. _tokenDetails.pipeFiatStash gets the Fiat balances against this MoH token

    function updateNav() external onlyRWAManager {
        uint256 totalSupply = MoToken(token).totalSupply();
        require(totalSupply > 0, "ECT1");
        _tokenDetails.totalAssetValue = getTotalRWAssetValue(); // 6 decimals shifted

        uint256 totalValue = totalBalanceInFiat() +
            _tokenDetails.pipeFiatStash +
            _tokenDetails.totalAssetValue; // 6 decimals shifted

        _tokenDetails.nav = uint32(
            (totalValue * (10**(MoToken(token).decimals()))) / totalSupply
        ); //nav should be 6 decimals shifted

        emit NAVUpdated(_tokenDetails.nav, _tokenDetails.stashUpdateDate);
    }

    /// @notice Gets the summation of all the assets owned by the RWA fund that is associated with the MoToken in fiatCurrency
    /// @return totalRWAssetValue Value of all the assets associated with the MoToken

    function getTotalRWAssetValue()
        internal
        view
        returns (uint128 totalRWAssetValue)
    {
        RWADetails rWADetailsInstance = RWADetails(rWADetails);
        totalRWAssetValue = rWADetailsInstance.getRWAValueByTokenId(
            _tokenDetails.id,
            fiatCurrency,
            _tokenDetails.stashUpdateDate
        ); // 6 decimals shifted in fiatCurrency
    }

    /// @notice This function allows the RWA Manager to transfer stablecoins held by the MoH token to a preset address
    /// from where it can be invested in Real world assets
    /// @param _currency stablecoin to transfer
    /// @param _amount number of stablecoins to transfer
    /// @return bool a boolean value indicating if the transfer was successful or not

    function transferFundsToPipe(bytes32 _currency, uint256 _amount)
        external
        onlyRWAManager
        returns (bool)
    {
        return (_transferFundsToPipe(_currency, _amount));
    }

    /// @notice This function allows the protocol to accept a new stablecoin for purchases of MoH token. It also sets the address
    /// to which this stablecoin balances are sent in order to deploy in real world assets
    /// @param _symbol symbol of stablecoin to add
    /// @param _contractAddress address of stablecoin contract to add
    /// @param _pipeAddress Address to which stablecoin balances are to be transferred in order to deploy in real world assets

    function addStableCoin(
        bytes32 _symbol,
        address _contractAddress,
        address _pipeAddress
    ) external onlyOwner {
        _addStableCoin(_symbol, _contractAddress, _pipeAddress);
    }

    /// @notice This function allows the protocol to delete a stablecoin for purchases of MoH token
    /// @param _symbol symbol of stablecoin to be deleted

    function deleteStableCoin(bytes32 _symbol) external onlyOwner {
        _deleteStableCoin(_symbol);
    }
}
