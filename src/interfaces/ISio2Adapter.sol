//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface ISio2Adapter {
    event Supply(address indexed user, uint256 indexed amount);
    event Withdraw(address indexed user, uint256 indexed amount);
    event Borrow(
        address indexed who,
        string indexed assetName,
        uint256 indexed amount
    );
    event AddSToken(address indexed who, uint256 indexed amount);
    event LiquidationCall(
        address indexed liquidatorAddr,
        address indexed userAddr,
        string indexed debtAsset,
        uint256 debtToCover
    );
    event ClaimRewards(address indexed who, uint256 rewardsToClaim);
    event WithdrawRevenue(address indexed who, uint256 indexed amount);
    event Repay(
        address indexed who,
        address indexed user,
        string indexed assetName,
        uint256 amount
    );
    event Updates(address indexed who, address indexed user);
    event RemoveAssetFromUser(address indexed user, string assetName);
    event HarvestRewards(address indexed who, uint256 pendingRewards);
    event UpdatePools(address indexed who);
    event UpdateUserRewards(address indexed user);
    event RemoveUser(address indexed user);
    event UpdateLastSTokenBalance(address indexed who, uint256 currentBalance);
    event Paused(address account);
    event Unpaused(address account);

    /// @notice Contract on pause
    error OnPause();

    /// @notice Transfer ASTR to this contract is only allowed for wASTR contract
    error TransferNotAllowed();

    /// @notice Zero amount not allowed due to withdraw
    error ZeroAmountWithdraw();

    /// @notice Zero amount not allowed due to withdrawRevenue
    error ZeroAmountWithdrawRevenue();

    /// @notice Supply amount should be > 0
    error ZeroAmountSupply();

    /// @notice Not enough nASTR on a wallet balance 
    error NotEnoughNastr();

    /// @notice The amount is too large for the existing value of the collateral
    error NotEnoughCollateralWithdraw();

    /// @notice Asset deactivated
    error AssetIsNotActive();

    /// @notice The borrow amount is too large for the existing value of the collateral
    error NotEnoughCollateralBorrow();

    /// @notice The user has reached the maximum amount of assets to borrow
    error MaxAmountBassetsReached();

    /// @notice There are not enough tokens on the user’s wallet balance
    error NotEnoughStokens();

    /// @notice User has healthy enough position
    error PosIsHealthyEnough();

    /// @notice The user's debt is less than the amount transferred for repayment
    error TooLargeLiquidationAmount();

    /// @notice Liquidation threshold of 50 percent exceeded
    error FiftyPercentExceeded();

    /// @notice The address of the borrowed asset must not be equal to the zero address.
    error WrongAssetBorrow();

    /// @notice User has no debts
    error UserHasNoDebt();

    /// @notice The user does not have enough tokens to repay
    error NotEnoughBalanceRepay();

    /// @notice In case of wASTR debt repayment, value must be greater than zero
    error ValueMustBeEqZero();

    /// @notice The user's debt is less than amount
    error TooLargeAmount();

    /// @notice Not enough value to repay
    error NotEnoughValue();

    /// @notice There are not enough reward tokens on the contract balance
    error NotEnoughRevenueTokens();

    /// @notice updateParams() already called
    error AlreadyUpdated();

    /// @notice Owner address should be different from zero
    error OwnerCannotBeZeroAddress();

    /// @notice The new owner's address must be different from the previous owner's address.
    error NewOwnerSameAsPrevious();

    /// @notice Caller address must be eq to _grantedOwner
    error CallerIsNotGrantedOwner();

    /// @notice User has no rewards
    error UserHasNoAnyRewards();

    /// @notice User has no debt in this asset
    error NoDebtInThisAsset();

    /// @notice Amount to repay must be greater than zero
    error ZeroAmountRepay();

    /// @notice Amount too large
    error AmountExceedsRevenuePool();    

    /// @notice Wrong amount due too redirect reward tokens
    error WrongAmountRedirect();    
}
