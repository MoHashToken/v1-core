// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "./interfaces/IERC20Basic.sol";

/// @title The ERC20 token contract
/** @dev This contract is an extension of ERC20PresetMinterPauser which has implementations of ERC20, Burnable, Pausable,
 *  Access Control and Context.
 *  In addition to serve as the ERC20 implementation this also serves as a vault which will hold
 *  1. stablecoins transferred from the users during token purchase and
 *  2. tokens themselves which are transferred from the users while requesting for redemption
 */

contract MoToken is ERC20PresetMinterPauser {
    /// @notice Constructor which only serves as passthrough for _tokenName and _tokenSymbol

    constructor(string memory _tokenName, string memory _tokenSymbol)
        ERC20PresetMinterPauser(_tokenName, _tokenSymbol)
    {
        // Do Nothing
    }

    /// @notice Overriding the ERC20Burable burn() function
    /// @param _tokens The amount of tokens to burn
    /// @param _address The address which holds the tokens

    function burn(uint256 _tokens, address _address) external {
        require(hasRole(MINTER_ROLE, msg.sender), "NM");
        require(balanceOf(_address) >= _tokens, "NT");
        _burn(_address, _tokens);
    }

    /// @notice Transfers MoTokens from self to an external address
    /// @param _address External address to transfer tokens to
    /// @param _tokens The amount of tokens to transfer
    /// @return bool Boolean indicating whether the transfer was success/failure

    function transferTokens(address _address, uint256 _tokens)
        external
        returns (bool)
    {
        require(hasRole(MINTER_ROLE, msg.sender), "NM");
        IERC20Basic ier = IERC20Basic(address(this));
        return (ier.transfer(_address, _tokens));
    }

    /// @notice Transfers stablecoins from self to an external address
    /// @param _contractAddress Stablecoin contract address on chain
    /// @param _address External address to transfer stablecoins to
    /// @param _amount The amount of stablecoins to transfer
    /// @return bool Boolean indicating whether the transfer was success/failure

    function transferStableCoins(
        address _contractAddress,
        address _address,
        uint256 _amount
    ) external returns (bool) {
        require(hasRole(MINTER_ROLE, msg.sender), "NM");
        IERC20Basic ier = IERC20Basic(_contractAddress);
        return (ier.transfer(_address, _amount));
    }

    /// @notice Transfers MoTokens from an external address to self
    /// @param _address External address to transfer tokens from
    /// @param _tokens The amount of tokens to transfer
    /// @return bool Boolean indicating whether the transfer was success/failure

    function receiveTokens(address _address, uint256 _tokens)
        external
        returns (bool)
    {
        IERC20Basic ier = IERC20Basic(address(this));
        return (ier.transferFrom(_address, address(this), _tokens));
    }

    /// @notice Transfers stablecoins from an external address to self
    /// @param _contractAddress Stablecoin contract address on chain
    /// @param _address External address to transfer stablecoins from
    /// @param _amount The amount of stablecoins to transfer
    /// @return bool Boolean indicating whether the transfer was success/failure

    function receiveStableCoins(
        address _contractAddress,
        address _address,
        uint256 _amount
    ) external returns (bool) {
        IERC20Basic ier = IERC20Basic(_contractAddress);
        return (ier.transferFrom(_address, address(this), _amount));
    }
}
