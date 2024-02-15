//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface ISio2AdapterAssetManager {
    event AddAsset(address owner, string indexed assetName, address indexed assetAddress);
    event SwitchAssetStatus(address indexed owner, string indexed assetName, bool indexed _isActive);
    event SetAdapter(address who, address adapterAddress);
    event UpdateBalSuccess(address user, string utilityName, uint256 amount);
    event UpdateBalError(address user, string utilityName, uint256 amount, string reason);
    event Paused(address account);
    event Unpaused(address account);

    /// @notice Both parameters must be greater than zero
    error ZeroParams();

    /// @notice Lending pool should not be a zero address
    error ZeroAddressLP();

    /// @notice snASTR address should not be a zero address
    error ZeroAddressSNA();

    /// @notice Allowed to call only for Sio2Adapter
    error AllowedOnlyForAdapter();

    /// @notice Asset already added
    error AlreadyAdded();

    /// @notice Not allowed to add asset with an empty name
    error EmptyAssetName();

    /// @notice Not allowed to add more assets
    error AssetsLimitReached();

    /// @notice Not allowed to switch asset with zero address
    error NoSuchAsset();

    /// @notice This status is already set
    error SameStatus();

    /// @notice The maximum number of assets cannot be equal to zero
    error ZeroNumber();

    /// @notice Owner address should not be equal to zero
    error ZeroAddressOwner();

    /// @notice New owner must be different from the previous one
    error SameOwner();

    /// @notice Caller address should be the same as _grantedOwner
    error CallerIsNotGrantedOwner();
}
