pragma solidity 0.8.4;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./interfaces/ISio2LendingPool.sol";
import "./interfaces/ISio2PriceOracle.sol";
import "./interfaces/ISio2IncentivesController.sol";

/* 
TASKS:
- fix visibilies
- mb change uint types in structs
- mb rename bToken to vdToken
- add more comments
*/

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

    uint256 public totalSupply;
    uint256 public lastUpdatedBlock;
    uint256 public lastSTokenBalance;
    uint256 public rewardPool;
    uint256 public revenuePool;
    uint256 public totalRewardsWeight; // the sum of the weights of collateral and borrowed assets
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

    mapping(string => Asset) public assetInfo;
    mapping(address => User) public userInfo;
    mapping(address => mapping(string => uint256)) public debts;
    mapping(address => mapping(string => uint256)) public userBorrowedAssetID;
    mapping(address => mapping(string => uint256)) public userBTokensIncomeDebt;
    mapping(address => mapping(string => uint256)) public userBorrowedRewardDebt;

    string[] public assets;
    address[] public users;
    address[] public assetsAddresses;
    address[] public bTokens;

    struct Asset { // --> consider using different types for optimize storage space. Maybe use bitmaps
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

    //Events
    event Supply(address indexed user, uint256 indexed amount);
    event Withdraw(address indexed user, uint256 indexed amount);
    event AddAsset(address owner, string indexed assetName, address indexed assetAddress);
    event RemoveAsset(address owner, string indexed assetName);
    event Borrow(address indexed who, string indexed assetName, uint256 indexed amount);
    event AddSToken(address indexed who, uint256 indexed amount);
    event LiquidationCall(address indexed liquidatorAddr, address indexed userAddr, string indexed debtAsset, uint256 debtToCover);
    event ClaimRewards(address indexed who, uint256 rewardsToClaim);
    event WithdrawRevenut(address indexed who, uint256 indexed amount);
    event Repay(address indexed who, address indexed user, string indexed assetName, uint256 amount);
    event Updates(address indexed who, address indexed user);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        ISio2LendingPool _pool,
        IERC20Upgradeable _nastr,
        IERC20Upgradeable _snastrToken,
        ISio2IncentivesController _incentivesController,
        IERC20Upgradeable _rewardToken
    ) public initializer {
        __Ownable_init();
        pool = _pool;
        nastr = _nastr;
        snastrToken = _snastrToken;
        rewardToken = _rewardToken;
        incentivesController = _incentivesController;
        bTokens.push(address(_snastrToken));
        priceOracle = ISio2PriceOracle(0x5f7c3639A854a27DFf64B320De5C9CAF9C4Bd323);
        totalRewardsWeight += COLLATERAL_REWARDS_WEIGHT;
        lastUpdatedBlock = block.number;

        _updateLastSTokenBalance();
        
        // addAsset("DOT", 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);
        // addAsset("WETH", 0x81ECac0D6Be0550A00FF064a4f9dd2400585FE9c);
    }

    modifier update(address _user) {
        _updates(_user);
        _;
        _updateLastSTokenBalance();
    }

    // @dev send nASTR to adapter, and to lending pool next
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

    function withdraw(uint256 _amount) external update(msg.sender) nonReentrant {
        require(_amount > 0, "Should be greater than zero");
        (, uint256 availableColToWithdraw) = _availableCollateralUSD(msg.sender);
        require(
            availableColToWithdraw >= _toUSD(address(nastr), _amount), // user can't withdraw collateral if his debt is too large
            "Not enough deposited nASTR"
        );

        //get nASTR tokens from lending pool
        uint256 withdrawnAmount = pool.withdraw(
            address(nastr),
            _amount,
            address(this)
        );

        User storage user = userInfo[msg.sender];

        totalSupply -= withdrawnAmount;
        user.collateralAmount -= withdrawnAmount;

        _updateUserCollateralIncomeDebts(user);

        nastr.safeTransfer(msg.sender, withdrawnAmount);

        // remove user if his collateral becomes equal to zero
        if (userInfo[msg.sender].collateralAmount == 0) _removeUser();

        emit Withdraw(msg.sender, _amount);
    }

    function borrow(string memory _assetName, uint256 _amount) external update(msg.sender) nonReentrant {
        address assetAddr = assetInfo[_assetName].addr;
        (uint256 availableColToBorrow, ) = _availableCollateralUSD(msg.sender);
        require(
            _toUSD(assetAddr, _amount) <= availableColToBorrow,
            "Not enough collateral to borrow"
        );
        require(assetAddr != address(0), "Wrong asset!");

        // convert price to correct format in case of dot borrowings
        if (assetInfo[_assetName].addr == assetInfo["DOT"].addr) {
            _amount /= DOT_PRECISION;
        }

        debts[msg.sender][_assetName] += _amount;
        assetInfo[_assetName].totalBorrowed += _amount;

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
        _updateLastBTokenBalance(assetInfo[_assetName]);

        IERC20Upgradeable(assetAddr).safeTransfer(msg.sender, _amount);

        emit Borrow(msg.sender, _assetName, _amount);
    }

    // @dev when user calls repay(), _user and msg.sender are the same
    //      and there is difference when liquidator calling function
    function repayPart(string memory _assetName, uint256 _amount) external update(msg.sender) nonReentrant {
        _repay(_assetName, _amount, msg.sender);
    }

    // @notice Allows the user to fully repay his debt
    function repayFull(string memory _assetName) external update(msg.sender) nonReentrant {
        uint256 fullDebtAmount = debts[msg.sender][_assetName];
        _repay(_assetName, fullDebtAmount, msg.sender);
    }

    // @notice Needed to transfer collateral position to adapter
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

        snastrToken.transferFrom(msg.sender, address(this), _amount);

        user.collateralAmount += _amount;
        totalSupply += _amount;

        // update user's income debts for sTokens and collateral rewards
        _updateUserCollateralIncomeDebts(user);

        emit AddSToken(msg.sender, _amount);
    }

    // @notice Allows owner to add new asset
    function addAsset(
        string memory _assetName,
        address _assetAddress,
        address _bToken,
        uint256 _rewardsWeight
    ) external onlyOwner {
        require(assetInfo[_assetName].addr == address(0), "Asset already added");
        require(_assetAddress != address(0), "Zero address alarm!");

        // get liquidationThreshold for asset from sio2
        DataTypes.ReserveConfigurationMap memory data = pool.getConfiguration(_assetAddress);
        uint256 lt = data.getLiquidationThreshold();

        Asset memory asset = Asset({
            id: assets.length,
            name: _assetName,
            addr: _assetAddress,
            bTokenAddress: _bToken,
            liquidationThreshold: lt,
            lastBTokenBalance: IERC20Upgradeable(_bToken).balanceOf(address(this)),
            accBTokensPerShare: 0,
            totalBorrowed: 0,
            rewardsWeight: _rewardsWeight,
            accBorrowedRewardsPerShare: 0
        });

        assets.push(asset.name);
        assetsAddresses.push(asset.addr);
        assetInfo[_assetName] = asset;
        bTokens.push(_bToken);
        totalRewardsWeight += _rewardsWeight;

        emit AddAsset(msg.sender, _assetName, _assetAddress);
    }

    // @notice Removes an asset
    function removeAsset(string memory _assetName) external onlyOwner {
        require(
            assetInfo[_assetName].addr != address(0),
            "There is no such asset"
        );

        Asset memory asset = assetInfo[_assetName];

        // remove from assets
        string memory lastAsset = assets[assets.length - 1];
        assets[asset.id] = lastAsset;
        assets.pop();

        // remove from assetsAddresses
        address lastAddr = assetsAddresses[assetsAddresses.length - 1];
        assetsAddresses[asset.id] = lastAddr;
        assetsAddresses.pop();

        // remove addr from bTokens
        address lastBAddr = bTokens[bTokens.length - 1];
        bTokens[asset.id] = lastBAddr;
        bTokens.pop();

        // update totalRewardsWeight
        totalRewardsWeight -= asset.rewardsWeight;

        // update id of last asset and remove deleted struct
        assetInfo[lastAsset].id = asset.id;
        delete assetInfo[_assetName];

        emit RemoveAsset(msg.sender, _assetName);
    }

    function liquidationCall(
        string memory _debtAsset,
        address _user,
        uint256 _debtToCover
    ) external update(_user) {
        User storage user = userInfo[_user];
        Asset memory asset = assetInfo[_debtAsset];

        // check user HF and update state
        require(getHF(_user) < 1, "User has healthy enough position");
        
        // get total user debt in usd and a specific asset
        uint256 userTotalDebtInUSD = _getDebtUSD(_user);
        uint256 userDebtInAsset = debts[_user][_debtAsset];

        // make sure that _debtToCover not exceeds 50% of user total debt and 100% of chosen asset debt
        require(_debtToCover <= userTotalDebtInUSD / 2, "Debt to cover need to be lower than 50% of users debt");
        require(_debtToCover <= userDebtInAsset, "_debtToCover exceeds the user's debt amount");

        // repay debt for user by liquidator
        _repay(_debtAsset, _debtToCover, _user);

        // counting collateral before sending
        (, uint256 liquidationPenalty) = _getAssetParameters(asset.addr);
        uint256 collateralToSendInUSD = _toUSD(asset.addr, _debtToCover) * liquidationPenalty / RISK_PARAMS_PRECISION;
        uint256 collateralToSend = _fromUSD(address(nastr), collateralToSendInUSD);
        
        // decrease user's collateral amount
        user.collateralAmount -= collateralToSend;

        // update collateral income debts for user
        _updateUserCollateralIncomeDebts(user);

        // send collateral with lp to liquidator
        IERC20Upgradeable(asset.addr).safeTransfer(msg.sender, collateralToSend);

        emit LiquidationCall(msg.sender, _user, _debtAsset, _debtToCover);
    }

    // @dev to get HF for check healthy of user position
    // @dev HF = sum(collateral_i * liqThreshold_i) / totalBorrowsInUSD
    function getHF(address _user) public update(_user) returns (uint256 hf) {
        uint256 debtUSD = _getDebtUSD(_user);
        require(debtUSD > 0, "User has no debts");
        uint256 collateralUSD = _toUSD(address(nastr), userInfo[_user].collateralAmount);
        hf = collateralUSD * collateralLT * 1e18 / RISK_PARAMS_PRECISION / debtUSD;
    }

    function estimateHF(address _user) public view returns (uint256 hf) {
        User memory user = userInfo[_user];

        // get est collateral accRPS
        uint256 estAccSTokensPerShare = accSTokensPerShare;
        uint256 estUserCollateral = user.collateralAmount;

        if (snastrToken.balanceOf(address(this)) > lastSTokenBalance) {
            estAccSTokensPerShare += ((snastrToken.balanceOf(address(this)) - lastSTokenBalance) *
                    REWARDS_PRECISION) / totalSupply;
        }

        // cals est user's collateral
        estUserCollateral += estUserCollateral * estAccSTokensPerShare / 
            REWARDS_PRECISION - user.sTokensIncomeDebt;

        uint256 collateralUSD = _toUSD(address(nastr), estUserCollateral);

        // get est borrowed accRPS for assets
        // calc est user's debt
        uint256 debtUSD;
        for (uint256 i; i < user.borrowedAssets.length;) {
            Asset memory asset = assetInfo[user.borrowedAssets[i]];

            // uint256 bTokenBalance = IERC20Upgradeable(asset.addr).balanceOf(address(this));
            uint256 debt = debts[user.addr][asset.name];
            uint256 income;
            uint256 estAccBTokenRPS = asset.accBTokensPerShare;

            if (IERC20Upgradeable(asset.bTokenAddress).balanceOf(address(this)) > asset.lastBTokenBalance) {
                income = IERC20Upgradeable(asset.bTokenAddress).balanceOf(address(this)) - asset.lastBTokenBalance;
            }

            if (asset.totalBorrowed > 0 && income > 0) {
                estAccBTokenRPS += income * REWARDS_PRECISION / asset.totalBorrowed;
                debt += debt * estAccBTokenRPS / REWARDS_PRECISION - userBTokensIncomeDebt[_user][asset.name];
            }

            // convert price to correct format in case of dot borrowings
            if (asset.addr == assetInfo["DOT"].addr) {
                debt *= DOT_PRECISION;
            }

            debtUSD += _toUSD(asset.addr, debt);
            
            unchecked { ++i; }
        }
        
        // calc hf
        require(debtUSD > 0, "User has no debts");

        hf = collateralUSD * collateralLT * 1e18 / RISK_PARAMS_PRECISION / debtUSD;
    }

    // @info Claim rewards by user
    function claimRewards() external {
        User storage user = userInfo[msg.sender];

        require(user.rewards > 0, "User has no any rewards");

        uint256 rewardsToClaim = user.rewards;

        user.rewards = 0;
        rewardPool -= rewardsToClaim;

        rewardToken.safeTransfer(msg.sender, rewardsToClaim);

        emit ClaimRewards(msg.sender, rewardsToClaim);
    }

    // @notice Withdraw revenue by owner
    function withdrawRevenue(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Should be greater than zero");
        require(
            rewardToken.balanceOf(address(this)) >= _amount,
            "Not enough SIO2 revenue tokens"
        );

        revenuePool -= _amount;

        rewardToken.safeTransfer(msg.sender, _amount);

        emit WithdrawRevenut(msg.sender, _amount);
    }

    function _repay(string memory _assetName, uint256 _amount, address _user) private {
        address assetAddress = assetInfo[_assetName].addr;
        IERC20Upgradeable asset = IERC20Upgradeable(assetAddress);

        // convert price to correct format in case of dot borrowings
        if (assetInfo[_assetName].addr == assetInfo["DOT"].addr) {
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
        assetInfo[_assetName].totalBorrowed -= _amount;

        // remove the asset from the user's borrowedAssets if he is no longer a debtor
        if (debts[_user][_assetName] == 0) {
            _removeAssetFromUser(_assetName, _user);
        }

        // approve asset for pool and repay
        asset.approve(address(pool), _amount);
        pool.repay(assetAddress, _amount, 2, address(this));

        // update user's income debts for bTokens and borrowed rewards
        _updateUserBorrowedIncomeDebts(msg.sender, _assetName);

        // update bToken's last balance
        _updateLastBTokenBalance(assetInfo[_assetName]);

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
    }

    function _harvestRewards(uint256 _pendingRewards) public { // <= change to private
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
        uint256 sumOfAssetShares = snastrToken.balanceOf(address(this));
        for (uint256 i; i < bTokens.length; i++ ) {
            IERC20Upgradeable bToken = IERC20Upgradeable(bTokens[i]);
            uint256 adapterBalance = bToken.balanceOf(address(this));
            uint256 totalBalance = bToken.totalSupply();

            sumOfAssetShares += adapterBalance * SHARES_PRECISION / totalBalance;
        }

        // set accumulated rewards per share for each borrowed asset
        // needed for sio2 rewards distribution
        for (uint256 i; i < assets.length;) {
            Asset storage asset = assetInfo[assets[i]];

            if (asset.totalBorrowed > 0) {
                IERC20Upgradeable bToken = IERC20Upgradeable(assetInfo[assets[i]].bTokenAddress);

                uint256 shareOfAsset = bToken.balanceOf(address(this)) * SHARES_PRECISION / bToken.totalSupply();

                // calc rewards amount for asset according to its weight and pool share
                uint256 assetRewards = rewardsToDistribute * shareOfAsset * asset.rewardsWeight / 
                    (sumOfAssetShares * totalRewardsWeight);

                asset.accBorrowedRewardsPerShare += assetRewards * REWARDS_PRECISION / asset.totalBorrowed;
            }
            
            unchecked { ++i; }
        }

        // set accumulated rewards per share for collateral asset
        uint256 nastrShare = snastrToken.balanceOf(address(this)) * SHARES_PRECISION / snastrToken.totalSupply();
        uint256 collateralRewards = receivedRewards * nastrShare * COLLATERAL_REWARDS_WEIGHT / (totalRewardsWeight * sumOfAssetShares);
        accCollateralRewardsPerShare += (collateralRewards * REWARDS_PRECISION) / totalSupply;
    }

    function _updatePools() public { // <= change to private
        uint256 currentSTokenBalance = snastrToken.balanceOf(address(this));

        // if sToken balance was changed, lastSTokenBalance updates
        if (currentSTokenBalance > lastSTokenBalance) {
            accSTokensPerShare += ((currentSTokenBalance - lastSTokenBalance) *
                    REWARDS_PRECISION) / totalSupply;
        }

        // update bToken debts
        for (uint256 i; i < assets.length; ) {
            Asset storage asset = assetInfo[assets[i]];

            if (asset.totalBorrowed > 0) {
                uint256 bTokenBalance = IERC20Upgradeable(assetInfo[assets[i]].bTokenAddress).balanceOf(address(this));
                uint256 income;

                if (bTokenBalance > asset.lastBTokenBalance) {
                    income = bTokenBalance - asset.lastBTokenBalance;
                    asset.accBTokensPerShare += income * REWARDS_PRECISION / asset.totalBorrowed;
                    asset.lastBTokenBalance = bTokenBalance;
                }
            }

            unchecked { ++i; }
        }
    }

    function _updateUserRewards(address _user) public { // <= change to private
        User storage user = userInfo[_user];

        // moving by borrowing assets for current user
        for (uint256 i; i < user.borrowedAssets.length; ) {
            Asset storage asset = assetInfo[user.borrowedAssets[i]];

            // update bToken debt
            uint256 debtToHarvest = (debts[_user][asset.name] * asset.accBTokensPerShare) / // <= CHECK
                REWARDS_PRECISION - userBTokensIncomeDebt[_user][asset.name];
            debts[_user][asset.name] += debtToHarvest;
            userBTokensIncomeDebt[_user][asset.name] = (debts[_user][asset.name] * asset.accBTokensPerShare) /
                REWARDS_PRECISION;

            // harvest sio2 rewards amount for each borrowed asset
            user.rewards += debts[_user][asset.name] * asset.accBorrowedRewardsPerShare / 
            REWARDS_PRECISION - userBorrowedRewardDebt[_user][asset.name];

            userBorrowedRewardDebt[_user][asset.name] = debts[_user][asset.name] * asset.accBorrowedRewardsPerShare / REWARDS_PRECISION;

            // update total amount of total borrowed for current asset
            asset.totalBorrowed += debtToHarvest;

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
    }

    function _removeUser() private {
        uint256 lastId = users.length - 1;
        uint256 userId = userInfo[msg.sender].id;
        userInfo[users[lastId]].id = userId;
        delete userInfo[users[userId]];
        users[userId] = users[lastId];
        users.pop();
    }

    // @dev To get the available amount to borrow expressed in usd
    function _availableCollateralUSD(address _userAddress)
        public
        view
        returns (uint256 toBorrow, uint256 toWithdraw)
    {
        if (userInfo[_userAddress].collateralAmount == 0) return (0, 0);
        uint256 debt = _getDebtUSD(_userAddress);
        uint256 userCollateral = _toUSD(address(nastr), userInfo[_userAddress].collateralAmount);
        uint256 collateralAfterLTV = (userCollateral * collateralLTV) / RISK_PARAMS_PRECISION;
        if (collateralAfterLTV > debt) toBorrow = collateralAfterLTV - debt;
        toWithdraw = userCollateral - debt * (RISK_PARAMS_PRECISION - collateralLTV + RISK_PARAMS_PRECISION) / RISK_PARAMS_PRECISION;
    }

    // @dev Convert to USD. Change to private later
    function _toUSD(address _asset, uint256 _amount) public view returns (uint256) {
        uint256 price = priceOracle.getAssetPrice(_asset);
        return (_amount * price) / PRICE_PRECISION;
    }

    // @dev Change to private later
    function _fromUSD(address _asset, uint256 _amount) public view returns (uint256) {
        uint256 price = priceOracle.getAssetPrice(_asset);
        return _amount * PRICE_PRECISION / price;
    }

    // @dev need change visibility to private
    // @notice Calculates user debt in usd
    function _getDebtUSD(address _user) public view returns (uint256 debt) {
        string[] memory arr = userInfo[_user].borrowedAssets;
        if (arr.length == 0) return 0;

        for (uint256 i; i < arr.length; ) {
            address assetAddr = assetInfo[arr[i]].addr;
            uint256 amount = debts[_user][arr[i]];

            // convert price to correct format in case of dot borrowings
            if (assetInfo[arr[i]].addr == assetInfo["DOT"].addr) {
                amount *= DOT_PRECISION;
            }
            
            debt += _toUSD(assetAddr, amount);
            unchecked { ++i; }
        }
    }

    // @dev change to private
    function _getAssetParameters(address _assetAddr) public view returns (
        uint256 liquidationThreshold,
        uint256 liquidationPenalty
        ) {
        DataTypes.ReserveConfigurationMap memory data = pool.getConfiguration(_assetAddr);
        liquidationThreshold = data.getLiquidationThreshold();
        liquidationPenalty = data.getLiquidationBonus();
    }

    // @notice Update all pools
    function _updates(address _user) public { // <== need to be changed to private
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

    function _updateLastSTokenBalance() private {
        uint256 currentBalance = snastrToken.balanceOf(address(this));
        if (lastSTokenBalance != currentBalance) {
            lastSTokenBalance = currentBalance;
        }
    }

    function _updateLastBTokenBalance(Asset storage _asset) private {
        _asset.lastBTokenBalance = IERC20Upgradeable(_asset.bTokenAddress).balanceOf(address(this));
    }

    function _updateUserBorrowedIncomeDebts(address _user, string memory _assetName) private {
        // update rewardDebt for user's bTokens
        userBTokensIncomeDebt[_user][_assetName] = debts[_user][_assetName] * assetInfo[_assetName].accBTokensPerShare /
            REWARDS_PRECISION;

        // update rewardDebt for user's borrowed rewards
        userBorrowedRewardDebt[_user][_assetName] = debts[_user][_assetName] * assetInfo[_assetName].accBorrowedRewardsPerShare /
            REWARDS_PRECISION;
    }

    function _updateUserCollateralIncomeDebts(User storage _user) private {
        // update rewardDebt for user's collateral
        _user.sTokensIncomeDebt = _user.collateralAmount * accSTokensPerShare / REWARDS_PRECISION;

        // update rewardDebt for user's collateral rewards
        _user.collateralRewardDebt = _user.collateralAmount * accCollateralRewardsPerShare / REWARDS_PRECISION;
    }
    
    // @dev setup to get collateral info
    function setup() public onlyOwner {
        ( , , , , collateralLTV, ) = pool.getUserAccountData(address(this));
        ( , , , collateralLT, , ) = pool.getUserAccountData(address(this));
    }

    function setDebt(address _user, string memory _assetName, uint256 _amount) public {
        debts[_user][_assetName] = _amount;
    }
}