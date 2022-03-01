// SPDX-License-Identifier: MIT

pragma solidity 0.8.2;

import "../library/Roles.sol";

/// @title RWAManager
/// @notice This is a role contract which will contain addresses which can perform RWAmanager functions
/// @dev Implementing Roles library to add or remove addresses from RWAManager role.

abstract contract RWAManager {
    /// @dev Using Roles library for role implementation
    using Roles for Roles.Role;

    event RWAManagerAdded(address indexed account);
    event RWAManagerRemoved(address indexed account);

    /// @dev Stores the address in the role.
    Roles.Role private rWAManager;

    /// @notice Checks whether msg.sender has RWA Manager role.
    /// @dev Only addresses added to the role rWAManager will be allowed to call the function.

    modifier onlyRWAManager() {
        require(isRWAManager(msg.sender), "ECA3");
        _;
    }

    /// @notice This function checks whether input address is a RWAManager
    /// @param account address whose role needs to be verified
    /// @return bool Boolean indicating whether input address is RWAManager

    function isRWAManager(address account) public view returns (bool) {
        return rWAManager.has(account);
    }

    /// @notice This function adds an address to RWAManager role
    /// @param account address which should get RWAManager role

    function _addRWAManager(address account) internal {
        rWAManager.add(account);
        emit RWAManagerAdded(account);
    }

    /// @notice This function removes an address from RWAManager role
    /// @param account address which should be removed RWAManager role

    function _removeRWAManager(address account) internal {
        rWAManager.remove(account);
        emit RWAManagerRemoved(account);
    }
}
