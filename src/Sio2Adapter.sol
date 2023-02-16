//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin-upgradeable/contracts/utils/AddressUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./interfaces/ISio2LendingPool.sol";
import "./interfaces/ISio2PriceOracle.sol";
import "./interfaces/ISio2IncentivesController.sol";
import "./Sio2AdapterAssetManager.sol";

contract Sio2Adapter is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
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

    uint256 public accCollateralRewardsPerShare; // accumulated collateral rewards per share
    uint256 public accSTokensPerShare; // accumulated sTokens per share

    uint256 private constant REWARDS_PRECISION = 1e12; // A big number to perform mul and div operations
    uint256 private constant RISK_PARAMS_PRECISION = 1e4;
    uint256 private constant DOT_PRECISION = 1e8;
    uint256 private constant PRICE_PRECISION = 1e8;
    uint256 private constant SHARES_PRECISION = 1e36;
    uint256 private constant COLLATERAL_REWARDS_WEIGHT = 5; // 5% of all sio2 collateral rewards go to the nASTR pool
    uint256 public constant REVENUE_FEE = 10; // 10% of rewards goes to the revenue pool

    address public constant DOT_ADDR = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;

    // mapping(string => Asset) public assetInfo;
    mapping(address => User) public userInfo;
    mapping(address => mapping(string => uint256)) public debts;
    mapping(address => mapping(string => uint256)) public userBorrowedAssetID;
    mapping(address => mapping(string => uint256)) public userBTokensIncomeDebt;
    mapping(address => mapping(string => uint256)) public userBorrowedRewardDebt;

    address[] public users;

    struct Asset {
        uint256 id;
        string name;
        address addr;
        address bTokenAddress;
        uint256 liquidationThreshold;
        uint256 lastBTokenBalance;
        uint256 totalBorrowed;
        uint256 rewardsWeight;
        uint256 accBTokensPerShare;
        uint256 accBorrowedRewardsPerShare;
    }

    struct User {
        uint256 id;
        address addr;
        uint256 collateralAmount;
        uint256 rewards;
        string[] borrowedAssets;
        uint256 collateralRewardDebt;
        uint256 sTokensIncomeDebt;
    }

    uint256 public x;

    //Events
    event Supply(address indexed user, uint256 indexed amount);
    event Withdraw(address indexed user, uint256 indexed amount);
    event Borrow(address indexed who, string indexed assetName, uint256 indexed amount);
    event AddSToken(address indexed who, uint256 indexed amount);
    event LiquidationCall(address indexed liquidatorAddr, address indexed userAddr, string indexed debtAsset, uint256 debtToCover);
    event ClaimRewards(address indexed who, uint256 rewardsToClaim);
    event WithdrawRevenue(address indexed who, uint256 indexed amount);
    event Repay(address indexed who, address indexed user, string indexed assetName, uint256 amount);
    event Updates(address indexed who, address indexed user);
    event RemoveAssetFromUser(address user, string assetName);
    event HarvestRewards(address who, uint256 pendingRewards);
    event UpdatePools(address who);
    event UpdateUserRewards(address user);
    event RemoveUser(address user);
    event UpdateLastSTokenBalance(address who, uint256 currentBalance);
    event SetupCollateralParams(address who, uint256 collateralLTV, uint256 collaterlLT);

    /* /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    } */

    function initialize(
        ISio2LendingPool _pool,
        IERC20Upgradeable _nastr,
        IERC20Upgradeable _snastrToken,
        ISio2IncentivesController _incentivesController,
        IERC20Upgradeable _rewardToken,
        Sio2AdapterAssetManager _assetManager,
        ISio2PriceOracle _priceOracle // ISio2PriceOracle(0x5f7c3639A854a27DFf64B320De5C9CAF9C4Bd323);

    ) public initializer {
        __Ownable_init();
        
        assetManager = _assetManager;
        pool = _pool;
        nastr = _nastr;
        snastrToken = _snastrToken;
        rewardToken = _rewardToken;
        incentivesController = _incentivesController;
        assetManager.addBTokens(address(_snastrToken));
        priceOracle = _priceOracle;
        lastUpdatedBlock = block.number;

        _updateLastSTokenBalance();
    }

    modifier update(address _user) {
        _updates(_user);
        _;
        _updateLastSTokenBalance();
    }

    // @notice Supply nASTR tokens as collateral
    // @param _amount Number of nASTR tokens sended to supply
    function supply(uint256 _amount) external update(msg.sender) nonReentrant {
        require(_amount > 0, "Should be greater than zero");
        require(
            nastr.balanceOf(msg.sender) >= _amount,
            "Not enough nASTR tokens on the user balance"
        );

        User storage user = userInfo[msg.sender];

        // check for new user. And create new if there is no such
        if (userInfo[msg.sender].addr == address(0)) {
            user.id = users.length;
            user.addr = msg.sender;
            users.push(msg.sender);
        }

        // take nastr from user
        nastr.safeTransferFrom(msg.sender, address(this), _amount);

        // deposit nastr to lending pool
        nastr.approve(address(pool), _amount);
        pool.deposit(address(nastr), _amount, address(this), 0);

        user.collateralAmount += _amount;
        totalSupply += _amount;

        _updateUserCollateralIncomeDebts(user);

        emit Supply(msg.sender, _amount);
    }

    // @notice Used to withdraw a deposit by a user
    // @param _amount Amount of tokens to withdraw
    function withdraw(uint256 _amount) external update(msg.sender) {
        _withdraw(msg.sender, _amount);
    }
    
    // @notice Used to withdraw deposit by a user or liquidator
    // @param _user Deposit holder's address
    // @param _amount Amount of tokens to withdraw
    function _withdraw(address _user, uint256 _amount) private nonReentrant {
        require(_amount > 0, "Should be greater than zero");

        // check ltv condition in case of user's call
        if (msg.sender == _user) {
            ( , uint256 availableColToWithdraw) = availableCollateralUSD(_user);
            require(
                // user can't withdraw collateral if his debt is too large
                availableColToWithdraw >= _toUSD(address(nastr), _amount),
                "Not enough deposited nASTR"
            );
        }

        // get nASTR tokens from lending pool
        uint256 withdrawnAmount = pool.withdraw(
            address(nastr),
            _amount,
            address(this)
        );

        _updateLastSTokenBalance();

        User storage user = userInfo[_user];

        totalSupply -= withdrawnAmount;
        user.collateralAmount -= withdrawnAmount;

        _updateUserCollateralIncomeDebts(user);

        // send collateral to user or liquidator
        nastr.safeTransfer(msg.sender, withdrawnAmount);

        // remove user if his collateral becomes equal to zero
        if (userInfo[_user].collateralAmount == 0) _removeUser();

        emit Withdraw(msg.sender, _amount);
    }

    // @notice Used to borrow an asset by a user
    // @param _assetName Borrowed token name
    // @param _amount Amount of borrowed token
    function borrow(string memory _assetName, uint256 _amount) external update(msg.sender) nonReentrant {
        ( , , address assetAddr, , , , , , , ) = assetManager.assetInfo(_assetName);
        (uint256 availableColToBorrow, ) = availableCollateralUSD(msg.sender);
        require(
            _toUSD(assetAddr, _amount) <= availableColToBorrow,
            "Not enough collateral to borrow"
        );
        require(assetAddr != address(0), "Wrong asset!");

        // convert price to correct format in case of dot borrowings
        if (assetAddr == DOT_ADDR) {
            _amount /= DOT_PRECISION;
        }

        debts[msg.sender][_assetName] += _amount;
        assetManager.increaseAssetsTotalBorrowed(_assetName, _amount);

        User storage user = userInfo[msg.sender];

        // check if user has such asset in borrowedAssets. Add it if not
        uint256 assetId = userBorrowedAssetID[msg.sender][_assetName];
        if (
            user.borrowedAssets.length == 0 || 
            keccak256(abi.encode(user.borrowedAssets[assetId])) != keccak256(abi.encode(_assetName))
        ) {
            userBorrowedAssetID[msg.sender][_assetName] = user.borrowedAssets.length;
            user.borrowedAssets.push(_assetName);
        }

        pool.borrow(assetAddr, _amount, 2, 0, address(this));

        // update user's income debts for bTokens and borrowed rewards
        _updateUserBorrowedIncomeDebts(user.addr, _assetName);

        // update bToken's last balance
        assetManager.updateLastBTokenBalance(_assetName);

        IERC20Upgradeable(assetAddr).safeTransfer(msg.sender, _amount);

        emit Borrow(msg.sender, _assetName, _amount);
    }

    // @dev when user calls repay(), _user and msg.sender are the same
    //      and there is difference when liquidator calling function
    // @param _assetName Asset name
    // @param _amount Amount of tokens
    function repayPart(string memory _assetName, uint256 _amount) external update(msg.sender) nonReentrant {
        _repay(_assetName, _amount, msg.sender);
    }

    // @notice Allows the user to fully repay his debt
    // @param _assetName Asset name
    function repayFull(string memory _assetName) external update(msg.sender) nonReentrant {
        ( , , address assetAddr, , , , , , , ) = assetManager.assetInfo(_assetName);
        uint256 fullDebtAmount = debts[msg.sender][_assetName];
        if (assetAddr == DOT_ADDR) {
            fullDebtAmount *= DOT_PRECISION;
        }
        _repay(_assetName, fullDebtAmount, msg.sender);
    }

    // @notice Needed to transfer collateral position to adapter
    // @param _amount Amount of supply tokens to deposit
    function addSTokens(uint256 _amount) external update(msg.sender) {
        require(
            snastrToken.balanceOf(msg.sender) >= _amount,
            "Not enough sTokens on user balance"
        );

        User storage user = userInfo[msg.sender];

        // check for new user. And add to arr if there is no such
        if (userInfo[msg.sender].addr == address(0)) {
            user.id = users.length;
            user.addr = msg.sender;
            users.push(msg.sender);
        }

        snastrToken.safeTransferFrom(msg.sender, address(this), _amount);

        user.collateralAmount += _amount;
        totalSupply += _amount;

        // update user's income debts for sTokens and collateral rewards
        _updateUserCollateralIncomeDebts(user);

        emit AddSToken(msg.sender, _amount);
    }

    // @notice Сalled by liquidators to pay off the user's debt in case of an unhealthy position
    // @param _debtToCover Debt amount
    // @param _user Address of the user whose position will be liquidated
    function liquidationCall(
        string memory _debtAsset,
        address _user,
        uint256 _debtToCover
    ) external nonReentrant {
        ( , , address debtAssetAddr, , , , , , , ) = assetManager.assetInfo(_debtAsset);
        address liquidator = msg.sender;

        // check user HF and update state
        require(getHF(_user) < 1e18, "User has healthy enough position");
        
        // get total user debt in usd and a specific asset
        uint256 userTotalDebtInUSD = calcEstimateUserDebtUSD(_user);
        uint256 userDebtInAsset = debts[_user][_debtAsset];
        uint256 debtToCoverUSD = _toUSD(debtAssetAddr, _debtToCover);

        // make sure that _debtToCover not exceeds 50% of user total debt and 100% of chosen asset debt
        require(_debtToCover <= userDebtInAsset, "_debtToCover exceeds the user's debt amount");
        require(debtToCoverUSD <= userTotalDebtInUSD / 2, "Debt to cover need to be lower than 50% of users debt");

        // repay debt for user by liquidator
        _repay(_debtAsset, _debtToCover, _user);

        // counting collateral before sending
        (, uint256 liquidationPenalty) = _getAssetParameters(debtAssetAddr);
        uint256 collateralToSendInUSD = _toUSD(debtAssetAddr, _debtToCover) * liquidationPenalty / RISK_PARAMS_PRECISION;
        uint256 collateralToSend = _fromUSD(address(nastr), collateralToSendInUSD);

        // withdraw collateral with liquidation penalty and send to liquidator
        _withdraw(_user, collateralToSend);

        emit LiquidationCall(liquidator, _user, _debtAsset, _debtToCover);
    }

    // @dev HF = sum(collateral_i * liqThreshold_i) / totalBorrowsInUSD
    // @notice to get HF for check healthy of user position
    // @param _user User address
    function getHF(address _user) public update(_user) returns (uint256 hf) {
        uint256 debtUSD = calcEstimateUserDebtUSD(_user);
        require(debtUSD > 0, "User has no debts");
        uint256 collateralUSD = _toUSD(address(nastr), userInfo[_user].collateralAmount);
        hf = collateralUSD * collateralLT * 1e18 / RISK_PARAMS_PRECISION / debtUSD;
    }

    // @dev setup to get collateral info
    function setup() public onlyOwner {
        ( , , , , collateralLTV, ) = pool.getUserAccountData(address(this));
        ( , , , collateralLT, , ) = pool.getUserAccountData(address(this));
        emit SetupCollateralParams(msg.sender, collateralLTV, collateralLT);
    }

    // @notice Updates user's s-tokens balance
    function _updateUserCollateralIncomeDebts(User storage _user) private {
        // update rewardDebt for user's collateral
        _user.sTokensIncomeDebt = _user.collateralAmount * accSTokensPerShare / REWARDS_PRECISION;

        // update rewardDebt for user's collateral rewards
        _user.collateralRewardDebt = _user.collateralAmount * accCollateralRewardsPerShare / REWARDS_PRECISION;
    }

    // @notice Update all pools
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

            // update user's rewards, collateral and debt
            _updateUserRewards(_user);

            lastUpdatedBlock = block.number;
        }

        emit Updates(msg.sender, _user);
    }

    // @notice Update last S token balance
    function _updateLastSTokenBalance() private {
        uint256 currentBalance = snastrToken.balanceOf(address(this));
        if (lastSTokenBalance != currentBalance) {
            lastSTokenBalance = currentBalance;
        }
        emit UpdateLastSTokenBalance(msg.sender, currentBalance);
    }

    // @notice Updates user's b-tokens balance
    function _updateUserBorrowedIncomeDebts(address _user, string memory _assetName) private {
        ( , , , , , , , ,
            uint256 assetAccBTokensPerShare, 
            uint256 assetAccBorrowedRewardsPerShare
        ) = assetManager.assetInfo(_assetName);

        // update rewardDebt for user's bTokens
        userBTokensIncomeDebt[_user][_assetName] = debts[_user][_assetName] * assetAccBTokensPerShare /
            REWARDS_PRECISION;

        // update rewardDebt for user's borrowed rewards
        userBorrowedRewardDebt[_user][_assetName] = debts[_user][_assetName] * assetAccBorrowedRewardsPerShare /
            REWARDS_PRECISION;
    }

    // @notice Claim rewards by user
    function claimRewards() external update(msg.sender) {
        User storage user = userInfo[msg.sender];
        require(user.rewards > 0, "User has no any rewards");
        uint256 rewardsToClaim = user.rewards;
        user.rewards = 0;
        rewardPool -= rewardsToClaim;
        rewardToken.safeTransfer(msg.sender, rewardsToClaim);

        emit ClaimRewards(msg.sender, rewardsToClaim);
    }

    // @notice Withdraw revenue by owner
    // @param _amount Amount of sio2 tokens
    function withdrawRevenue(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Should be greater than zero");
        require(
            rewardToken.balanceOf(address(this)) >= _amount,
            "Not enough SIO2 revenue tokens"
        );

        revenuePool -= _amount;
        rewardToken.safeTransfer(msg.sender, _amount);

        emit WithdrawRevenue(msg.sender, _amount);
    }

    // @notice Repay logic
    function _repay(string memory _assetName, uint256 _amount, address _user) private {
        ( , , address assetAddress, , , , , , , ) = assetManager.assetInfo(_assetName);
        IERC20Upgradeable asset = IERC20Upgradeable(assetAddress);

        // convert price to correct format in case of dot borrowings
        if (assetAddress == DOT_ADDR) {
            _amount /= DOT_PRECISION;
        }

        // check balance of user or liquidator
        require(debts[_user][_assetName] > 0, "The user has no debt in this asset");
        require(asset.balanceOf(msg.sender) >= _amount, "Not enough wallet balance to repay");
        require(_amount > 0, "Amount should be greater than zero");
        require(debts[_user][_assetName] >= _amount, "Too large amount, debt is smaller");

        // take borrowed asset from user or liquidator and reduce user's debt
        asset.safeTransferFrom(msg.sender, address(this), _amount);

        debts[_user][_assetName] -= _amount;
        assetManager.decreaseAssetsTotalBorrowed(_assetName, _amount);

        // remove the asset from the user's borrowedAssets if he is no longer a debtor
        if (debts[_user][_assetName] == 0) {
            _removeAssetFromUser(_assetName, _user);
        }

        asset.approve(address(pool), _amount);
        pool.repay(assetAddress, _amount, 2, address(this));

        // update user's income debts for bTokens and borrowed rewards
        _updateUserBorrowedIncomeDebts(_user, _assetName);

        // update bToken's last balance
        assetManager.updateLastBTokenBalance(_assetName);

        emit Repay(msg.sender, _user, _assetName, _amount);
    }

    // @notice Removes asset from user's assets list
    function _removeAssetFromUser(string memory _assetName, address _user) private {
        string[] storage bAssets = userInfo[_user].borrowedAssets;
        uint256 assetId = userBorrowedAssetID[_user][_assetName];
        uint256 lastId = bAssets.length - 1;
        string memory lastAsset = bAssets[lastId];
        userBorrowedAssetID[_user][lastAsset] = assetId;
        bAssets[assetId] = bAssets[lastId];
        bAssets.pop();
        emit RemoveAssetFromUser(_user, _assetName);
    }

    // @notice Collect accumulated income of sio2 rewards
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
        uint256 sumOfAssetShares = snastrToken.balanceOf(address(this)) * COLLATERAL_REWARDS_WEIGHT * SHARES_PRECISION / snastrToken.totalSupply();
        for (uint256 i; i < assets.length; i++ ) {
            (
                , , ,
                address assetBTokenAddress,
                , ,
                uint256 assetTotalBorrowed,
                uint256 assetRewardsWeight,
                ,
            ) = assetManager.assetInfo(assets[i]);
            IERC20Upgradeable bToken = IERC20Upgradeable(assetBTokenAddress);
            uint256 adapterBalance = bToken.balanceOf(address(this));
            uint256 totalBalance = bToken.totalSupply();
            if (totalBalance != 0) {
                sumOfAssetShares += assetRewardsWeight * adapterBalance * SHARES_PRECISION / totalBalance;
            }
        }

        // set accumulated rewards per share for each borrowed asset
        // needed for sio2 rewards distribution
        for (uint256 i; i < assets.length;) {
            (
                , , ,
                address assetBTokenAddress,
                , ,
                uint256 assetTotalBorrowed,
                uint256 assetRewardsWeight,
                ,
            ) = assetManager.assetInfo(assets[i]);

            if (assetTotalBorrowed > 0) {
                IERC20Upgradeable bToken = IERC20Upgradeable(assetBTokenAddress);

                uint256 shareOfAsset = bToken.balanceOf(address(this)) * SHARES_PRECISION / bToken.totalSupply();

                // calc rewards amount for asset according to its weight and pool share
                uint256 assetRewards = rewardsToDistribute * shareOfAsset * assetRewardsWeight / 
                    sumOfAssetShares;
                x = assetRewards;
                assetManager.increaseAccBorrowedRewardsPerShare(assets[i], assetRewards);
            }
            
            unchecked { ++i; }
        }

        // set accumulated rewards per share for collateral asset
        uint256 nastrShare = snastrToken.balanceOf(address(this)) * SHARES_PRECISION / snastrToken.totalSupply();
        uint256 collateralRewards = rewardsToDistribute * nastrShare * COLLATERAL_REWARDS_WEIGHT / sumOfAssetShares;
        accCollateralRewardsPerShare += (collateralRewards * REWARDS_PRECISION) / totalSupply;

        emit HarvestRewards(msg.sender, _pendingRewards);
    }

    // @notice Collect accumulated b-tokens and s-tokens
    function _updatePools() private {
        uint256 currentSTokenBalance = snastrToken.balanceOf(address(this));
        string[] memory assets = assetManager.getAssetsNames();

        // if sToken balance was changed, lastSTokenBalance updates
        if (currentSTokenBalance > lastSTokenBalance) {
            accSTokensPerShare += ((currentSTokenBalance - lastSTokenBalance) *
                    REWARDS_PRECISION) / totalSupply;
        }

        // update bToken debts
        for (uint256 i; i < assets.length; ) {
            (
                , , ,
                address assetBTokenAddress,
                ,
                uint256 assetLastBTokenBalance,
                uint256 assetTotalBorrowed,
                , ,
            ) = assetManager.assetInfo(assets[i]);

            if (assetTotalBorrowed > 0) {
                uint256 bTokenBalance = IERC20Upgradeable(assetBTokenAddress).balanceOf(address(this));
                uint256 income;

                if (bTokenBalance > assetLastBTokenBalance) {
                    income = bTokenBalance - assetLastBTokenBalance;
                    assetManager.increaseAccBTokensPerShare(assets[i], income);
                    assetManager.updateLastBTokenBalance(assets[i]);
                }
            }

            unchecked { ++i; }
        }
        emit UpdatePools(msg.sender);
    }

    // @notice Update balances of b-tokens, s-tokens and rewards for user
    function _updateUserRewards(address _user) private {
        User storage user = userInfo[_user];

        // moving by borrowing assets for current user
        for (uint256 i; i < user.borrowedAssets.length; ) {
            (
                ,
                string memory assetName,
                , , , , , ,
                uint256 assetAccBTokensPerShare,
                uint256 assetAccBorrowedRewardsPerShare
            ) = assetManager.assetInfo(user.borrowedAssets[i]);

            // update bToken debt
            uint256 debtToHarvest = (debts[_user][assetName] * assetAccBTokensPerShare) / 
                REWARDS_PRECISION - userBTokensIncomeDebt[_user][assetName];
            debts[_user][assetName] += debtToHarvest;
            userBTokensIncomeDebt[_user][assetName] = (debts[_user][assetName] * assetAccBTokensPerShare) /
                REWARDS_PRECISION;

            // harvest sio2 rewards amount for each borrowed asset
            user.rewards += debts[_user][assetName] * assetAccBorrowedRewardsPerShare / 
            REWARDS_PRECISION - userBorrowedRewardDebt[_user][assetName];

            userBorrowedRewardDebt[_user][assetName] = debts[_user][assetName] * assetAccBorrowedRewardsPerShare / REWARDS_PRECISION;

            // update total amount of total borrowed for current asset
            assetManager.increaseAssetsTotalBorrowed(assetName, debtToHarvest);

            unchecked { ++i; }
        }

        // harvest sio2 rewards for user's collateral
        user.rewards += user.collateralAmount * accCollateralRewardsPerShare / REWARDS_PRECISION - user.collateralRewardDebt;
        user.collateralRewardDebt = user.collateralAmount * accCollateralRewardsPerShare / REWARDS_PRECISION;

        // user collateral update
        uint256 collateralToHarvest = (user.collateralAmount * accSTokensPerShare) / REWARDS_PRECISION -
            user.sTokensIncomeDebt;
        user.collateralAmount += collateralToHarvest;
        user.sTokensIncomeDebt = (user.collateralAmount * accSTokensPerShare) /
            REWARDS_PRECISION;

        // uncrease total collateral amount by received user's collateral
        totalSupply += collateralToHarvest;

        emit UpdateUserRewards(_user);
    }

    // @notice Removes user if his deposit amount equal to zero
    function _removeUser() private {
        uint256 lastId = users.length - 1;
        uint256 userId = userInfo[msg.sender].id;
        userInfo[users[lastId]].id = userId;
        delete userInfo[users[userId]];
        users[userId] = users[lastId];
        users.pop();
        emit RemoveUser(msg.sender);
    }

    // @notice Predict healthy of user position without state updates
    // @param _user User address
    // @return User's health factor
    function estimateHF(address _user) public view returns (uint256 hf) {
        uint256 collateralUSD = calcEstimateUserCollateralUSD(_user);

        // get est borrowed accRPS for assets
        // calc est user's debt
        uint256 debtUSD = calcEstimateUserDebtUSD(_user);

        require(debtUSD > 0, "User has no debts");

        hf = collateralUSD * collateralLT * 1e18 / RISK_PARAMS_PRECISION / debtUSD;
    }

    // @notice Check user collateral amount without state updates
    // @param _userAddr User address
    // @return User's collateral value in USD
    function calcEstimateUserCollateralUSD(address _userAddr) public view returns (uint256 coll) {
        User memory user = userInfo[_userAddr];
        // get est collateral accRPS
        uint256 estAccSTokensPerShare = accSTokensPerShare;
        uint256 estUserCollateral = user.collateralAmount;

        if (snastrToken.balanceOf(address(this)) > lastSTokenBalance) {
            estAccSTokensPerShare += ((snastrToken.balanceOf(address(this)) - lastSTokenBalance) *
                    REWARDS_PRECISION) / totalSupply;
        }

        estUserCollateral += estUserCollateral * estAccSTokensPerShare / 
            REWARDS_PRECISION - user.sTokensIncomeDebt;

        coll = _toUSD(address(nastr), estUserCollateral);
    }

    // @notice Check user debt amount without state updates
    // @param _userAddr User address
    // @return User's debt value in USD
    function calcEstimateUserDebtUSD(address _userAddr) public view returns (uint256 debtUSD) {
        User memory user = userInfo[_userAddr];
        for (uint256 i; i < user.borrowedAssets.length;) {
            (
                , 
                string memory assetName,
                address assetAddr,
                address assetBTokenAddress,
                ,
                uint256 assetLastBTokenBalance,
                uint256 assetTotalBorrowed,
                ,
                uint256 assetAccBTokensPerShare,
            ) = assetManager.assetInfo(user.borrowedAssets[i]);

            // uint256 bTokenBalance = IERC20Upgradeable(asset.addr).balanceOf(address(this));
            uint256 debt = debts[user.addr][assetName];
            uint256 income;
            uint256 estAccBTokenRPS = assetAccBTokensPerShare;

            if (IERC20Upgradeable(assetBTokenAddress).balanceOf(address(this)) > assetLastBTokenBalance) {
                income = IERC20Upgradeable(assetBTokenAddress).balanceOf(address(this)) - assetLastBTokenBalance;
            }

            if (assetTotalBorrowed > 0 && income > 0) {
                estAccBTokenRPS += income * REWARDS_PRECISION / assetTotalBorrowed;
                debt += debt * estAccBTokenRPS / REWARDS_PRECISION - userBTokensIncomeDebt[user.addr][assetName];
            }

            // convert price to correct format in case of dot borrowings
            if (assetAddr == DOT_ADDR) {
                debt *= DOT_PRECISION;
            }

            debtUSD += _toUSD(assetAddr, debt);
            
            unchecked { ++i; }
        }
    }

    // @notice To get the available amount to borrow expressed in usd
    // @param _userAddr User addresss
    // @return toBorrow Amount of collateral in usd available to borrow
    // @return toWithdraw Amount of collateral in usd available to withdraw
    function availableCollateralUSD(address _userAddr)
        public
        view
        returns (uint256 toBorrow, uint256 toWithdraw)
    {
        if (userInfo[_userAddr].collateralAmount == 0) return (0, 0);
        uint256 debt = calcEstimateUserDebtUSD(_userAddr);
        uint256 userCollateral = calcEstimateUserCollateralUSD(_userAddr);
        uint256 collateralAfterLTV = (userCollateral * collateralLTV) / RISK_PARAMS_PRECISION;
        if (collateralAfterLTV > debt) toBorrow = collateralAfterLTV - debt;
        uint256 debtAfterLTV = debt * RISK_PARAMS_PRECISION / collateralLTV;
        if (userCollateral > debtAfterLTV) toWithdraw = userCollateral - debtAfterLTV;
    }

    // @notice Convert tokens value to USD
    function _toUSD(address _asset, uint256 _amount) private view returns (uint256) {
        uint256 price = priceOracle.getAssetPrice(_asset);
        return (_amount * price) / PRICE_PRECISION;
    }

    // @notice Convert tokens value from USD
    function _fromUSD(address _asset, uint256 _amount) private view returns (uint256) {
        uint256 price = priceOracle.getAssetPrice(_asset);
        return _amount * PRICE_PRECISION / price;
    }

    // @notice Used to get assets params
    function _getAssetParameters(address _assetAddr) private view returns (
        uint256 liquidationThreshold,
        uint256 liquidationPenalty
        ) {
        DataTypes.ReserveConfigurationMap memory data = pool.getConfiguration(_assetAddr);
        liquidationThreshold = data.getLiquidationThreshold();
        liquidationPenalty = data.getLiquidationBonus();
    }

    // @notice Get user info
    // @param _user User address
    // @return User's params
    function getUser(address _user) public view returns (User memory) {
        return userInfo[_user];
    }
}