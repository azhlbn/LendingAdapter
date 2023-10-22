//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin-upgradeable/contracts/utils/AddressUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./interfaces/ISio2LendingPool.sol";
import "./interfaces/ISio2PriceOracle.sol";
import "./interfaces/ISio2IncentivesController.sol";
import "./interfaces/ISio2Adapter.sol";
import "./interfaces/IWASTR.sol";
import "./Sio2AdapterAssetManager.sol";

contract Sio2Adapter is
    ISio2Adapter,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using AddressUpgradeable for address payable;
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap; // used to extract risk parameters of an asset

    //Interfaces
    ISio2LendingPool public pool;
    IERC20Upgradeable public nastr;
    IERC20Upgradeable public snastrToken;
    IERC20Upgradeable public rewardToken;
    ISio2PriceOracle public priceOracle;
    ISio2IncentivesController public incentivesController; // used to extract risk parameters of an asset
    Sio2AdapterAssetManager public assetManager;

    uint256 public totalSupply;
    uint256 public lastUpdatedBlock;
    uint256 public lastSTokenBalance;
    uint256 public rewardPool;
    uint256 public revenuePool;
    uint256 public collateralLTV; // nASTR Loan To Value
    uint256 public collateralLT; // nASTR Liquidation Threshold
    uint256 public maxAmountToBorrow;

    uint256 public accCollateralRewardsPerShare; // accumulated collateral rewards per share
    uint256 public accSTokensPerShare; // accumulated sTokens per share

    uint256 private constant RISK_PARAMS_PRECISION = 1e4;
    uint256 private constant PRICE_PRECISION = 1e8;
    uint256 private constant SHARES_PRECISION = 1e36;
    uint256 public constant REVENUE_FEE = 10; // 10% of rewards goes to the revenue pool

    // mapping(string => Asset) public assetInfo;
    mapping(address => User) public userInfo;
    mapping(address => mapping(string => uint256)) public debts;
    mapping(address => mapping(string => uint256)) public userBorrowedAssetID;
    mapping(address => mapping(string => uint256)) public userBTokensIncomeDebt;
    mapping(address => mapping(string => uint256)) public userBorrowedRewardDebt;

    address[] public users;

    struct User {
        uint256 id;
        address addr;
        uint256 collateralAmount;
        uint256 rewards;
        string[] borrowedAssets;
        uint256 collateralRewardDebt;
        uint256 sTokensIncomeDebt;
        uint256 lastUpdatedBlock;
    }

    uint256 public liquidationPenalty;
    string public utilityName = "Sio2_Adapter";

    IWASTR private constant WASTR =
        IWASTR(0xAeaaf0e2c81Af264101B9129C00F4440cCF0F720);

    uint256 private rewardsPrecision; // A big number to perform mul and div operations
    uint256 public collateralRewardsWeight; // share of all sio2 collateral rewards

    bool private _paused;
    address private _grantedOwner;    

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        ISio2LendingPool _pool,
        IERC20Upgradeable _nastr,
        IERC20Upgradeable _snastrToken,
        ISio2IncentivesController _incentivesController,
        IERC20Upgradeable _rewardToken,
        Sio2AdapterAssetManager _assetManager,
        ISio2PriceOracle _priceOracle // ISio2PriceOracle(0x5f7c3639A854a27DFf64B320De5C9CAF9C4Bd323);
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        assetManager = _assetManager;
        pool = _pool;
        nastr = _nastr;
        snastrToken = _snastrToken;
        rewardToken = _rewardToken;
        incentivesController = _incentivesController;
        priceOracle = _priceOracle;
        lastUpdatedBlock = block.number;
        (collateralLT, liquidationPenalty, collateralLTV) = assetManager
            .getAssetParameters(address(nastr)); // set collateral params
        setMaxAmountToBorrow(15); // set the max amount of borrowed assets
        rewardsPrecision = 1e36;
        _updateCollateralRewardsWeight();

        _updateLastSTokenBalance();
    }

    modifier update(address _user) {
        _updates(_user);
        _;
        _updateLastSTokenBalance();
    }

    modifier whenNotPaused() {
        if (_paused) revert OnPause();
        _;
    }

    receive() external payable {
        if (msg.sender != address(WASTR)) revert TransferNotAllowed();
    }

    /// @notice Supply nASTR tokens as collateral
    /// @param _amount Number of nASTR tokens sended to supply
    function supply(uint256 _amount) external update(msg.sender) nonReentrant whenNotPaused {
        if (_amount == 0) revert ZeroAmountSupply();
        if (nastr.balanceOf(msg.sender) < _amount) revert NotEnoughNastr();

        User storage user = userInfo[msg.sender];

        // New user check. Add new if there is no such
        if (userInfo[msg.sender].id == 0 && user.collateralAmount == 0 && user.rewards == 0) {
            user.id = users.length;
            users.push(msg.sender);
        }

        user.collateralAmount += _amount;
        totalSupply += _amount;

        // take nastr from user
        nastr.safeTransferFrom(msg.sender, address(this), _amount);

        // deposit nastr to lending pool
        nastr.approve(address(pool), _amount);
        pool.deposit(address(nastr), _amount, address(this), 0);

        assetManager.updateBalanceInAdaptersDistributor(msg.sender);

        _updateUserCollateralIncomeDebts(user);

        emit Supply(msg.sender, _amount);
    }

    /// @notice Used to withdraw a deposit by a user
    /// @param _amount Amount of tokens to withdraw
    function withdraw(uint256 _amount) external update(msg.sender) whenNotPaused {
        _withdraw(msg.sender, _amount);
    }

    /// @notice Used to withdraw deposit by a user or liquidator
    /// @param _user Deposit holder's address
    /// @param _amount Amount of tokens to withdraw
    function _withdraw(
        address _user,
        uint256 _amount
    ) private nonReentrant returns (uint256) {
        if (_amount == 0) revert ZeroAmountWithdraw();

        // check ltv condition in case of user's call
        if (msg.sender == _user) {
            (, uint256 availableColToWithdraw) = assetManager
                .availableCollateralUSD(_user);
            // user can't withdraw collateral if his debt is too large
            if (availableColToWithdraw < toUSD(address(nastr), _amount)) revert NotEnoughCollateralWithdraw();
        }

        // get nASTR tokens from lending pool
        uint256 withdrawnAmount = pool.withdraw(
            address(nastr),
            _amount,
            address(this)
        );

        User storage user = userInfo[_user];

        totalSupply -= withdrawnAmount;
        user.collateralAmount -= withdrawnAmount;

        _updateLastSTokenBalance();

        assetManager.updateBalanceInAdaptersDistributor(_user);

        _updateUserCollateralIncomeDebts(user);

        // send collateral to user or liquidator
        nastr.safeTransfer(msg.sender, withdrawnAmount);

        // remove user if his collateral and rewards becomes equal to zero
        if (user.collateralAmount == 0 && user.rewards == 0) _removeUser();

        emit Withdraw(msg.sender, _amount);

        return withdrawnAmount;
    }

    /// @notice Used to borrow an asset by a user
    /// @param _assetName Borrowed token name
    /// @param _amount Amount of borrowed token in 18 decimals format
    function borrow(
        string memory _assetName,
        uint256 _amount
    ) external update(msg.sender) nonReentrant whenNotPaused {
        Sio2AdapterAssetManager.Asset memory asset = assetManager.getAssetInfo(_assetName);
        if (!asset.isActive) revert AssetIsNotActive();
        (uint256 availableColToBorrow, ) = assetManager.availableCollateralUSD(
            msg.sender
        );
        if (toUSD(asset.addr, _amount) > availableColToBorrow) revert NotEnoughCollateralBorrow();
        if (asset.addr == address(0)) revert WrongAssetBorrow();

        uint256 nativeAmount = assetManager.toNativeDecFormat(asset.addr, _amount);
        uint256 roundedAmount = assetManager.to18DecFormat(asset.addr, nativeAmount);

        debts[msg.sender][_assetName] += roundedAmount;
        assetManager.increaseAssetsTotalBorrowed(_assetName, roundedAmount);

        User storage user = userInfo[msg.sender];

        // check if user has such asset in borrowedAssets. Add it if not
        uint256 assetId = userBorrowedAssetID[msg.sender][_assetName];
        if (
            user.borrowedAssets.length == 0 ||
            keccak256(abi.encodePacked(user.borrowedAssets[assetId])) !=
            keccak256(abi.encodePacked(_assetName))
        ) {
            if (user.borrowedAssets.length >= maxAmountToBorrow) revert MaxAmountBassetsReached();
            userBorrowedAssetID[msg.sender][_assetName] = user
                .borrowedAssets
                .length;
            user.borrowedAssets.push(_assetName);
        }

        pool.borrow(asset.addr, nativeAmount, 2, 0, address(this));

        // update user's income debts for bTokens and borrowed rewards
        _updateUserBorrowedIncomeDebts(msg.sender, _assetName);

        // update bToken's last balance
        assetManager.updateLastBTokenBalance(_assetName);

        if (asset.addr == address(WASTR)) {
            WASTR.withdraw(nativeAmount);
            payable(msg.sender).sendValue(nativeAmount);
        } else {
            IERC20Upgradeable(asset.addr).safeTransfer(msg.sender, nativeAmount);
        }

        emit Borrow(msg.sender, _assetName, roundedAmount);
    }

    /// @dev when user calls repay(), _user and msg.sender are the same
    ///      and there is difference when liquidator calling function
    /// @param _assetName Asset name
    /// @param _amount Amount of tokens in 18 decimals
    function repayPart(
        string memory _assetName,
        uint256 _amount
    ) external payable update(msg.sender) nonReentrant {
        _repay(_assetName, _amount, msg.sender);
    }

    /// @notice Allows the user to fully repay his debt
    /// @param _assetName Asset name
    function repayFull(
        string memory _assetName
    ) external payable update(msg.sender) nonReentrant {
        uint256 fullDebtAmount = debts[msg.sender][_assetName];

        _repay(_assetName, fullDebtAmount, msg.sender);
    }

    /// @notice Needed to transfer collateral position to adapter
    /// @param _amount Amount of supply tokens to deposit
    function addSTokens(uint256 _amount) external update(msg.sender) whenNotPaused {
        if (snastrToken.balanceOf(msg.sender) < _amount) revert NotEnoughStokens();

        User storage user = userInfo[msg.sender];

        // New user check. Add new if there is no such
        if (userInfo[msg.sender].id == 0 && user.collateralAmount == 0 && user.rewards == 0) {
            user.id = users.length;
            users.push(msg.sender);
        }

        user.collateralAmount += _amount;
        totalSupply += _amount;

        snastrToken.safeTransferFrom(msg.sender, address(this), _amount);

        assetManager.updateBalanceInAdaptersDistributor(msg.sender);

        // update user's income debts for sTokens and collateral rewards
        _updateUserCollateralIncomeDebts(user);

        emit AddSToken(msg.sender, _amount);
    }

    /// @notice Сalled by liquidators to pay off the user's debt in case of an unhealthy position
    /// @param _debtToCover Debt amount
    /// @param _user Address of the user whose position will be liquidated
    /// @return Amount of collateral tokens forwarded to liquidator
    function liquidationCall(
        string memory _debtAsset,
        address _user,
        uint256 _debtToCover
    ) external returns (uint256) {
        Sio2AdapterAssetManager.Asset memory asset = assetManager.getAssetInfo(
            _debtAsset
        );
        address debtAssetAddr = asset.addr;

        // check user HF, debtUSD and update state
        (uint256 hf, uint256 userTotalDebtInUSD) = getLiquidationParameters(
            _user
        );
        if (hf >= 1e18) revert PosIsHealthyEnough();

        // get user's debt in a specific asset
        uint256 userDebtInAsset = debts[_user][_debtAsset];

        uint256 debtToCoverUSD = toUSD(debtAssetAddr, _debtToCover);

        // make sure that _debtToCover not exceeds 50% of user total debt and 100% of chosen asset debt
        if (_debtToCover > userDebtInAsset) revert TooLargeLiquidationAmount();
        if (debtToCoverUSD > userTotalDebtInUSD / 2) revert FiftyPercentExceeded();

        // repay debt for user by liquidator
        _repay(_debtAsset, _debtToCover, _user);

        // counting collateral before sending
        uint256 collateralToSendInUSD = (toUSD(debtAssetAddr, _debtToCover) *
            liquidationPenalty) / RISK_PARAMS_PRECISION;
        uint256 collateralToSend = fromUSD(
            address(nastr),
            collateralToSendInUSD
        );

        // withdraw collateral with liquidation penalty and send to liquidator
        uint256 collateralToLiquidator = _withdraw(_user, collateralToSend);

        emit LiquidationCall(msg.sender, _user, _debtAsset, _debtToCover);

        return collateralToLiquidator;
    }

    /// @dev HF = sum(collateral_i * liqThreshold_i) / totalBorrowsInUSD
    /// @notice to get HF for check healthy of user position
    /// @param _user User address
    function getLiquidationParameters(
        address _user
    ) public update(_user) returns (uint256 hf, uint256 debtUSD) {
        debtUSD = assetManager.calcEstimateUserDebtUSD(_user);
        if (debtUSD == 0) revert UserHasNoDebt();
        uint256 collateralUSD = toUSD(
            address(nastr),
            userInfo[_user].collateralAmount
        );
        hf =
            (collateralUSD * assetManager.getLT() * 1e18) /
            RISK_PARAMS_PRECISION /
            debtUSD;
    }

    /// @notice Updates user's s-tokens balance
    function _updateUserCollateralIncomeDebts(User storage _user) private {
        // update rewardDebt for user's collateral
        _user.sTokensIncomeDebt =
            (_user.collateralAmount * accSTokensPerShare) /
            rewardsPrecision;

        // update rewardDebt for user's collateral rewards
        _user.collateralRewardDebt =
            (_user.collateralAmount * accCollateralRewardsPerShare) /
            rewardsPrecision;
    }

    /// @notice Update all pools
    function _updates(address _user) private {
        // check sio2 rewards
        uint256 pendingRewards = incentivesController.getUserUnclaimedRewards(
            address(this)
        );

        // claim sio2 rewards if there is some
        if (pendingRewards > 0) _harvestRewards(pendingRewards);

        if (block.number > lastUpdatedBlock) {
            // update collateral and debt accumulated rewards per share
            _updatePools();

            lastUpdatedBlock = block.number;
        }

        User storage user = userInfo[_user];

        if (block.number > user.lastUpdatedBlock) {
            // update user's rewards, collateral and debt
            _updateUserRewards(_user);

            user.lastUpdatedBlock = block.number;
        }

        emit Updates(msg.sender, _user);
    }

    /// @notice Update last S token balance
    function _updateLastSTokenBalance() private {
        uint256 currentBalance = snastrToken.balanceOf(address(this));
        if (lastSTokenBalance != currentBalance) {
            lastSTokenBalance = currentBalance;
            emit UpdateLastSTokenBalance(msg.sender, currentBalance);
        }
    }

    /// @notice Updates user's b-tokens balance
    function _updateUserBorrowedIncomeDebts(
        address _user,
        string memory _assetName
    ) private {
        Sio2AdapterAssetManager.Asset memory asset = assetManager.getAssetInfo(_assetName);
        uint256 assetAccBTokensPerShare = asset.accBTokensPerShare;
        uint256 assetAccBorrowedRewardsPerShare = asset.accBorrowedRewardsPerShare;

        // update rewardDebt for user's bTokens
        userBTokensIncomeDebt[_user][_assetName] =
            (debts[_user][_assetName] * assetAccBTokensPerShare) /
            rewardsPrecision;

        // update rewardDebt for user's borrowed rewards
        userBorrowedRewardDebt[_user][_assetName] =
            (debts[_user][_assetName] * assetAccBorrowedRewardsPerShare) /
            rewardsPrecision;
    }

    /// @notice Claim rewards by user
    function claimRewards() external update(msg.sender) whenNotPaused {
        User storage user = userInfo[msg.sender];
        if (user.rewards == 0) revert UserHasNoAnyRewards();
        uint256 rewardsToClaim = user.rewards;
        user.rewards = 0;
        rewardPool -= rewardsToClaim;
        rewardToken.safeTransfer(msg.sender, rewardsToClaim);

        // remove user if his collateral and rewards becomes equal to zero
        if (user.collateralAmount == 0) _removeUser();

        emit ClaimRewards(msg.sender, rewardsToClaim);
    }

    /// @notice Repay logic
    function _repay(
        string memory _assetName,
        uint256 _amount,
        address _user
    ) private whenNotPaused {
        Sio2AdapterAssetManager.Asset memory repayAsset = assetManager.getAssetInfo(_assetName);
        address assetAddress = repayAsset.addr;

        IERC20Upgradeable asset = IERC20Upgradeable(assetAddress);

        uint256 nativeAmount = assetManager.toNativeDecFormat(assetAddress, _amount);
        uint256 roundedAmount = assetManager.to18DecFormat(assetAddress, nativeAmount);

        uint256 userBal;
        if (assetAddress != address(WASTR)) {
            userBal = asset.balanceOf(msg.sender);

            // add missing zeros for correct calculations if needed
            userBal = assetManager.to18DecFormat(assetAddress, userBal);

            if (userBal < roundedAmount) revert NotEnoughBalanceRepay();
            if (msg.value != 0) revert ValueMustBeEqZero();
        }

        // check balance of user or liquidator
        if (debts[_user][_assetName] == 0) revert NoDebtInThisAsset();
        if (roundedAmount == 0) revert ZeroAmountRepay();
        if (debts[_user][_assetName] < roundedAmount) revert TooLargeAmount();

        if (assetAddress == address(WASTR)) {
            if (msg.value < roundedAmount) revert NotEnoughValue();
            // return diff back to user
            if (msg.value > roundedAmount)
                payable(msg.sender).sendValue(msg.value - roundedAmount);
            // change astr to wastr
            WASTR.deposit{value: roundedAmount}();
        } else {
            // take borrowed asset from user or liquidator and reduce user's debt
            asset.safeTransferFrom(msg.sender, address(this), nativeAmount);
        }

        debts[_user][_assetName] -= roundedAmount;
        assetManager.decreaseAssetsTotalBorrowed(_assetName, roundedAmount);

        // remove the asset from the user's borrowedAssets if he is no longer a debtor
        if (debts[_user][_assetName] == 0) {
            _removeAssetFromUser(_assetName, _user);
        }

        asset.approve(address(pool), nativeAmount);
        pool.repay(assetAddress, nativeAmount, 2, address(this));

        // update user's income debts for bTokens and borrowed rewards
        _updateUserBorrowedIncomeDebts(_user, _assetName);

        // update bToken's last balance
        assetManager.updateLastBTokenBalance(_assetName);

        emit Repay(msg.sender, _user, _assetName, roundedAmount);
    }

    /// @notice Removes asset from user's assets list
    function _removeAssetFromUser(
        string memory _assetName,
        address _user
    ) private {
        string[] storage bAssets = userInfo[_user].borrowedAssets;
        uint256 assetId = userBorrowedAssetID[_user][_assetName];
        uint256 lastId = bAssets.length - 1;
        string memory lastAsset = bAssets[lastId];
        userBorrowedAssetID[_user][lastAsset] = assetId;
        bAssets[assetId] = bAssets[lastId];
        bAssets.pop();
        delete userBorrowedAssetID[_user][_assetName];
        emit RemoveAssetFromUser(_user, _assetName);
    }

    /// @notice Collect accumulated income of sio2 rewards
    function _harvestRewards(uint256 _pendingRewards) private {
        address[] memory bTokens = assetManager.getBTokens();
        string[] memory assets = assetManager.getAssetsNames();
        // receiving rewards from incentives controller
        // this rewards consists of collateral and debt rewards
        uint256 receivedRewards = incentivesController.claimRewards(
            bTokens,
            _pendingRewards,
            address(this)
        );

        // cut off the commission part specified in the documentation
        uint256 comissionPart = receivedRewards / REVENUE_FEE;
        rewardPool += receivedRewards - comissionPart;
        revenuePool += comissionPart;

        uint256 rewardsToDistribute = receivedRewards - comissionPart;

        // get total asset shares in pool to further calculate rewards for each asset
        uint256 sumOfAssetShares = (snastrToken.balanceOf(address(this)) *
            collateralRewardsWeight *
            SHARES_PRECISION) / snastrToken.totalSupply();

        uint256 assetsLen = assets.length;

        for (uint256 i; i < assetsLen; i++) {
            Sio2AdapterAssetManager.Asset memory asset = assetManager.getAssetInfo(assets[i]);
            address assetBTokenAddress = asset.bTokenAddress;
            uint256 assetRewardsWeight = asset.rewardsWeight;

            IERC20Upgradeable bToken = IERC20Upgradeable(assetBTokenAddress);

            uint256 adapterBalance = bToken.balanceOf(address(this));
            uint256 totalBalance = bToken.totalSupply();

            if (totalBalance != 0) {
                sumOfAssetShares +=
                    (assetRewardsWeight * adapterBalance * SHARES_PRECISION) /
                    totalBalance;
            }
        }

        // set accumulated rewards per share for each borrowed asset
        // needed for sio2 rewards distribution
        for (uint256 i; i < assetsLen; ) {
            Sio2AdapterAssetManager.Asset memory asset = assetManager.getAssetInfo(assets[i]);
            address assetBTokenAddress = asset.bTokenAddress;
            uint256 assetTotalBorrowed = asset.totalBorrowed;
            uint256 assetRewardsWeight = asset.rewardsWeight;

            if (assetTotalBorrowed > 0) {
                IERC20Upgradeable bToken = IERC20Upgradeable(
                    assetBTokenAddress
                );

                uint256 shareOfAsset = (bToken.balanceOf(address(this)) *
                    SHARES_PRECISION) / bToken.totalSupply();

                // calc rewards amount for asset according to its weight and pool share
                uint256 assetRewards = (rewardsToDistribute *
                    shareOfAsset *
                    assetRewardsWeight) / sumOfAssetShares;

                assetManager.increaseAccBorrowedRewardsPerShare(
                    assets[i],
                    assetRewards
                );
            }

            unchecked {
                ++i;
            }
        }

        // set accumulated rewards per share for collateral asset
        uint256 nastrShare = (snastrToken.balanceOf(address(this)) *
            SHARES_PRECISION) / snastrToken.totalSupply();
        uint256 collateralRewards = (rewardsToDistribute *
            nastrShare *
            collateralRewardsWeight) / sumOfAssetShares;
        accCollateralRewardsPerShare +=
            (collateralRewards * rewardsPrecision) /
            snastrToken.balanceOf(address(this));

        emit HarvestRewards(msg.sender, _pendingRewards);
    }

    /// @notice Collect accumulated b-tokens and s-tokens
    function _updatePools() private {
        uint256 currentSTokenBalance = snastrToken.balanceOf(address(this));
        string[] memory assets = assetManager.getAssetsNames();
        uint256 assetsLen = assets.length;

        // if sToken balance was changed, lastSTokenBalance updates
        if (currentSTokenBalance > lastSTokenBalance) {
            accSTokensPerShare +=
                ((currentSTokenBalance - lastSTokenBalance) *
                    rewardsPrecision) /
                lastSTokenBalance;
        }

        // update bToken debts
        for (uint256 i; i < assetsLen; ) {
            Sio2AdapterAssetManager.Asset memory asset = assetManager.getAssetInfo(assets[i]);
            address assetBTokenAddress = asset.bTokenAddress;
            uint256 assetLastBTokenBalance = asset.lastBTokenBalance;
            uint256 assetTotalBorrowed = asset.totalBorrowed;

            if (assetTotalBorrowed > 0) {
                uint256 bTokenBalance = IERC20Upgradeable(assetBTokenAddress)
                    .balanceOf(address(this));

                // add missing zeros for correct calculations
                bTokenBalance = assetManager.to18DecFormat(
                    assetBTokenAddress,
                    bTokenBalance
                );

                uint256 income;

                if (bTokenBalance > assetLastBTokenBalance) {
                    income = bTokenBalance - assetLastBTokenBalance;
                    assetManager.increaseAssetsTotalBorrowed(assets[i], income);
                    assetManager.increaseAccBTokensPerShare(assets[i], income);
                    assetManager.updateLastBTokenBalance(assets[i]);
                }
            }

            unchecked {
                ++i;
            }
        }
        emit UpdatePools(msg.sender);
    }

    /// @notice Update balances of b-tokens, s-tokens and rewards for user
    function _updateUserRewards(address _user) private {
        User storage user = userInfo[_user];
        uint256 userBAssetsLen = user.borrowedAssets.length;

        // moving by borrowing assets for current user
        for (uint256 i; i < userBAssetsLen; ) {
            Sio2AdapterAssetManager.Asset memory asset = assetManager.getAssetInfo(user.borrowedAssets[i]);
            string memory assetName = asset.name;
            uint256 assetAccBTokensPerShare = asset.accBTokensPerShare;
            uint256 assetAccBorrowedRewardsPerShare = asset.accBorrowedRewardsPerShare;

            // update bToken debt
            uint256 debtToHarvest = (debts[_user][assetName] *
                assetAccBTokensPerShare) /
                rewardsPrecision -
                userBTokensIncomeDebt[_user][assetName];
            debts[_user][assetName] += debtToHarvest;
            userBTokensIncomeDebt[_user][assetName] =
                (debts[_user][assetName] * assetAccBTokensPerShare) /
                rewardsPrecision;

            // harvest sio2 rewards amount for each borrowed asset
            user.rewards +=
                (debts[_user][assetName] * assetAccBorrowedRewardsPerShare) /
                rewardsPrecision -
                userBorrowedRewardDebt[_user][assetName];

            userBorrowedRewardDebt[_user][assetName] =
                (debts[_user][assetName] * assetAccBorrowedRewardsPerShare) /
                rewardsPrecision;

            unchecked {
                ++i;
            }
        }

        // user collateral update
        uint256 collateralToHarvest = (user.collateralAmount *
            accSTokensPerShare) /
            rewardsPrecision -
            user.sTokensIncomeDebt;
        user.collateralAmount += collateralToHarvest;
        user.sTokensIncomeDebt =
            (user.collateralAmount * accSTokensPerShare) /
            rewardsPrecision;

        // harvest sio2 rewards for user's collateral
        user.rewards +=
            (user.collateralAmount * accCollateralRewardsPerShare) /
            rewardsPrecision -
            user.collateralRewardDebt;
        user.collateralRewardDebt =
            (user.collateralAmount * accCollateralRewardsPerShare) /
            rewardsPrecision;

        // increase the total amount of collateral by the received user collateral
        totalSupply += collateralToHarvest;

        emit UpdateUserRewards(_user);
    }

    /// @notice Removes user if his deposit amount equal to zero
    function _removeUser() private {
        uint256 lastId = users.length - 1;
        uint256 userId = userInfo[msg.sender].id;
        userInfo[users[lastId]].id = userId;
        delete userInfo[users[userId]];
        users[userId] = users[lastId];
        users.pop();
        emit RemoveUser(msg.sender);
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // ADMIN LOGIC
    //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Withdraw revenue by owner
    /// @param _amount Amount of sio2 tokens
    function withdrawRevenue(uint256 _amount) external onlyOwner {
        if (_amount == 0) revert ZeroAmountWithdrawRevenue();
        if (rewardToken.balanceOf(address(this)) < _amount) revert NotEnoughRevenueTokens();
        if (_amount > revenuePool) revert AmountExceedsRevenuePool();

        revenuePool -= _amount;
        rewardToken.safeTransfer(msg.sender, _amount);

        emit WithdrawRevenue(msg.sender, _amount);
    }

    /// @notice Sets the maximum amount of borrowed assets by the owner
    /// @param _amount Amount of assets
    function setMaxAmountToBorrow(uint256 _amount) public onlyOwner {
        maxAmountToBorrow = _amount;
    }

    /// @notice Sets internal parameters for proper operation
    function updateParams() external onlyOwner {
        if(rewardsPrecision == 1e36) revert AlreadyUpdated();

        rewardsPrecision = 1e36;
        
        // sync accumulated rewards
        accCollateralRewardsPerShare *= 1e24;
        accSTokensPerShare *= 1e24;

        _updateCollateralRewardsWeight();

        assetManager.updateParams();
    }

    /// @notice Sync a collateral rewards weight with the sio2 protocol
    function _updateCollateralRewardsWeight() internal {
        collateralRewardsWeight = assetManager.getAssetWeight(address(nastr), incentivesController);
    }

    /// @notice Disabling funcs with the whenNotPaused modifier
    function pause() external onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Enabling funcs with the whenNotPaused modifier
    function unpause() external onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice propose a new owner
    /// @param _newOwner => new contract owner
    function grantOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert OwnerCannotBeZeroAddress();
        if (_newOwner == owner()) revert NewOwnerSameAsPrevious();
        _grantedOwner = _newOwner;
    }

    /// @notice claim ownership by granted address
    function claimOwnership() external {
        if (_grantedOwner != msg.sender) revert CallerIsNotGrantedOwner();
        _transferOwnership(_grantedOwner);
        _grantedOwner = address(0);
    }

    /// @notice Disabling transfer and renounce of ownership for security reasons 
    function transferOwnership(address) public override { revert("Not allowed"); } 

    /// @notice Disabling transfer and renounce of ownership for security reasons 
    function renounceOwnership() public override { revert("Not allowed"); }
    
    ////////////////////////////////////////////////////////////////////////////
    //
    // READERS
    //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Convert tokens value to USD
    /// @param _asset Asset address
    /// @param _amount Amount of token with 18 decimals
    /// @return USD price with 18 decimals
    function toUSD(
        address _asset,
        uint256 _amount
    ) public view returns (uint256) {
        return assetManager.toUSD(_asset, _amount);
    }

    /// @notice Convert tokens value from USD
    /// @param _asset Asset address
    /// @param _amount Price in USD with 18 decimals
    /// @return Token amount with 18 decimals
    function fromUSD(
        address _asset,
        uint256 _amount
    ) public view returns (uint256) {
        return assetManager.fromUSD(_asset, _amount);
    }

    /// @notice Get user info
    /// @param _user User address
    /// @return User's params
    function getUser(address _user) external view returns (User memory) {
        return userInfo[_user];
    }

    /// @notice Get users list
    function getUsers() external view returns (address[] memory) {
        return users;
    }

    /// @notice Get length of users array
    function getUsersCount() external view returns (uint256) {
        return users.length;
    }
}