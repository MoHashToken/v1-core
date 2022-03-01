// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./MoToken.sol";
import "./MoTokenManager.sol";
import "./utils/StringUtil.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Factory contract for MoTokenManager
/** @notice This contract creates MoTokenManager for a given MoToken.
 *  This also gives us a way to get MoTokenManager give a token symbol.
 */
contract MoTokenManagerFactory is Ownable {
    /// @dev Mapping points to the token manager of a given token's symbol
    mapping(bytes32 => address) private symbolToTokenManager;

    /// @dev Index used while creating MoTokenManager
    uint16 private tokenId;

    event MoTokenManagerAdded(
        address indexed _from,
        bytes32 indexed _tokenSymbol,
        address indexed _tokenManager
    );

    /// @notice Adds MoTokenManager for a given MoToken
    /// @param _token Address of MoToken contract
    /// @param _tokenManager Address of MoTokenManager contract
    /// @param _rWADetails Address of RWADetails contract

    function addTokenManager(
        address _token,
        address _tokenManager,
        address _rWADetails
    ) external onlyOwner {
        MoToken mt = MoToken(_token);
        string memory tokenSymbol = mt.symbol();
        require((bytes(tokenSymbol).length > 0), "AE");

        bytes32 tokenBytes = StringUtil.stringToBytes32(tokenSymbol);
        require(symbolToTokenManager[tokenBytes] == address(0), "AE");

        tokenId = tokenId + 1;

        MoTokenManager tManager = MoTokenManager(_tokenManager);
        tManager.initialize(tokenId, _token, _rWADetails);

        symbolToTokenManager[tokenBytes] = _tokenManager;
        emit MoTokenManagerAdded(msg.sender, tokenBytes, _tokenManager);
    }

    /// @notice Getter for MoTokenManager
    /// @param _tokenSymbol The input token symbol
    /// @return address The MoTokenManager associated with the token symbol

    function getTokenManagerAddress(bytes32 _tokenSymbol)
        external
        view
        returns (address)
    {
        return symbolToTokenManager[_tokenSymbol];
    }
}
