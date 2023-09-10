//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./interfaces/ISio2LendingPool.sol";
import "./interfaces/IAdaptersDistributor.sol";
import "./Sio2Adapter.sol";

contract Sio2AdapterAssetManager is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap; // used to extract risk parameters of an asset

    ISio2LendingPool public pool;
    Sio2Adapter public adapter;

    string[] public assets;
    address[] public bTokens;

    mapping(string => Asset) public assetInfo;
    mapping(address => bool) public bTokenExist;
    mapping(string => bool) public assetNameExist;

    uint256 public maxNumberOfAssets;
    uint256 private rewardsPrecision; // A big number to perform mul and div operations
    address private _grantedOwner;

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

    IAdaptersDistributor public constant ADAPTERS_DISTRIBUTOR = IAdaptersDistributor(0x294Bb6b8e692543f373383A84A1f296D3C297aEf);

    event AddAsset(address owner, string indexed assetName, address indexed assetAddress);
    event RemoveAsset(address owner, string indexed assetName);
    event SetAdapter(address who, address adapterAddress);
    event UpdateBalSuccess(address user, string utilityName, uint256 amount);
    event UpdateBalError(address user, string utilityName, uint256 amount, string reason);
    event Paused(address account);
    event Unpaused(address account);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        ISio2LendingPool _pool,
        address _snastr
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        require(address(_pool) != address(0), "Lending pool address cannot be zero");
        require(_snastr != address(0), "snASTR address cannot be zero");

        bTokens.push(_snastr);

        pool = _pool;
        rewardsPrecision = 1e36;
    }

    modifier onlyAdapter() {
        require(msg.sender == address(adapter), "Allowed only for adapter");
        _;
    }

    /// @notice Allows owner to add new asset
    function addAsset(
        address _assetAddress,
        address _bToken,
        uint256 _rewardsWeight
    ) external onlyOwner {
        string memory _assetName = ERC20Upgradeable(_assetAddress).symbol();
        addAsset(_assetName, _assetAddress, _bToken, _rewardsWeight);
    }

    /// @notice Allows owner to add new asset
    function addAsset(
        string memory _assetName,
        address _assetAddress,
        address _bToken,
        uint256 _rewardsWeight
    ) public onlyOwner {
        require(assetInfo[_assetName].addr == address(0), "Asset already added");
        require(keccak256(abi.encodePacked(_assetName)) != keccak256(""), "Empty asset name");
        require(!bTokenExist[_bToken], "Such bToken address already added");
        require(!assetNameExist[_assetName], "Such asset name already added");
        require(assets.length < maxNumberOfAssets, "Assets limit reached");

        // get liquidationThreshold for asset from sio2
        DataTypes.ReserveConfigurationMap memory data = pool.getConfiguration(_assetAddress);
        uint256 lt = data.getLiquidationThreshold();

        uint256 nativeBTokenBal = IERC20Upgradeable(_bToken).balanceOf(address(this));

        Asset memory asset = Asset({
            id: assets.length,
            name: _assetName,
            addr: _assetAddress,
            bTokenAddress: _bToken,
            liquidationThreshold: lt,
            lastBTokenBalance: to18DecFormat(_assetAddress, nativeBTokenBal),
            accBTokensPerShare: 0,
            totalBorrowed: 0,
            rewardsWeight: _rewardsWeight,
            accBorrowedRewardsPerShare: 0
        });

        assets.push(asset.name);
        assetInfo[_assetName] = asset;
        bTokens.push(_bToken);

        bTokenExist[_bToken] = true;
        assetNameExist[_assetName] = true;

        emit AddAsset(msg.sender, _assetName, _assetAddress);
    }

    /// @notice Removes an asset and 
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

        // remove addr from bTokens
        address lastBAddr = bTokens[bTokens.length - 1];
        bTokens[asset.id + 1] = lastBAddr;
        bTokens.pop();

        bTokenExist[asset.bTokenAddress] = false;
        assetNameExist[asset.name] = false;

        // update id of last asset and remove deleted struct
        assetInfo[lastAsset].id = asset.id;
        delete assetInfo[_assetName];

        emit RemoveAsset(msg.sender, _assetName);
    }

    function increaseAssetsTotalBorrowed(string memory _assetName, uint256 _amount) external onlyAdapter {
        assetInfo[_assetName].totalBorrowed += _amount;
    }

    function decreaseAssetsTotalBorrowed(string memory _assetName, uint256 _amount) external onlyAdapter {
        assetInfo[_assetName].totalBorrowed -= _amount;
    }

    function increaseAccBorrowedRewardsPerShare(string memory _assetName, uint256 _assetRewards) external onlyAdapter {
        Asset storage asset = assetInfo[_assetName];
        asset.accBorrowedRewardsPerShare += _assetRewards * rewardsPrecision / asset.totalBorrowed;
    }

    function increaseAccBTokensPerShare(string memory _assetName, uint256 _income) external onlyAdapter {
        Asset storage asset = assetInfo[_assetName];
        asset.accBTokensPerShare += _income * rewardsPrecision / asset.totalBorrowed;
    }

    function updateLastBTokenBalance(string memory _assetName) external onlyAdapter {
        Asset storage asset = assetInfo[_assetName];
        uint256 nativeBal = IERC20Upgradeable(asset.bTokenAddress).balanceOf(address(adapter));
        asset.lastBTokenBalance = to18DecFormat(asset.addr, nativeBal);
    }

    function setAdapter(Sio2Adapter _adapter) external onlyOwner {
        adapter = _adapter;

        emit SetAdapter(msg.sender, address(_adapter));
    }

    function updateBalanceInAdaptersDistributor(address _user) external onlyAdapter {
        Sio2Adapter.User memory user = adapter.getUser(_user);
        uint256 nastrBalAfter = user.collateralAmount;
        try
            ADAPTERS_DISTRIBUTOR.updateBalanceInAdapter(
                "Sio2_Adapter",
                _user,
                nastrBalAfter
            )
        {
            emit UpdateBalSuccess(_user, "Sio2_Adapter", nastrBalAfter);
        } catch Error(string memory reason) {
            emit UpdateBalError(_user, "Sio2_Adapter", nastrBalAfter, reason);
        }
    }

    /// @notice Sets the maximum number of assets
    /// @param _num Number of assets. Equal to 30 by default
    function setMaxNumberOfAssets(uint256 _num) external onlyOwner {
        require(_num > 0, "Cannot equal to zero");
        maxNumberOfAssets = _num;
    }

    function updateParams() external onlyAdapter {
        rewardsPrecision = 1e36;
        uint256 len = assets.length;
        // sync accumulated values
        for (uint256 i; i < len; i = _incrementUnchecked(i)) {
            Asset memory asset = assetInfo[assets[i]];
            asset.accBorrowedRewardsPerShare *= 1e24;
            asset.accBTokensPerShare *= 1e24;
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // ADMIN LOGIC
    //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice propose a new owner
    function grantOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Owner cannot be a zero address");
        require(_newOwner != owner(), "New owner shouldn't match the current one");
        _grantedOwner = _newOwner;
    }

    /// @notice claim ownership by granted address
    function claimOwnership() external {
        require(_grantedOwner == msg.sender, "Caller is not the granted owner");
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

    /// @notice Check user collateral amount without state updates
    function calcEstimateUserCollateralUSD(
        address _userAddr
    ) public view returns (uint256 coll) {
        Sio2Adapter.User memory user = adapter.getUser(_userAddr);
        // get est collateral accRPS
        uint256 estAccSTokensPerShare = adapter.accSTokensPerShare();
        uint256 estUserCollateral = user.collateralAmount;

        IERC20Upgradeable snastr = IERC20Upgradeable(adapter.snastrToken());
        if (snastr.balanceOf(address(this)) > adapter.lastSTokenBalance()) {
            estAccSTokensPerShare +=
                ((snastr.balanceOf(address(this)) - adapter.lastSTokenBalance()) *
                    rewardsPrecision) /
                adapter.totalSupply();
        }

        estUserCollateral +=
            (estUserCollateral * estAccSTokensPerShare) /
            rewardsPrecision -
            user.sTokensIncomeDebt;

        coll = adapter.toUSD(address(adapter.nastr()), estUserCollateral);
    }

    /// @notice Check user debt amount without state updates
    function calcEstimateUserDebtUSD(
        address _userAddr
    ) public view returns (uint256 debtUSD) {
        Sio2Adapter.User memory user = adapter.getUser(_userAddr);
        uint256 assetLength = user.borrowedAssets.length;
        for (uint256 i; i < assetLength; i = _incrementUnchecked(i)) {
            Asset memory asset = assetInfo[user.borrowedAssets[i]];
            uint256 debt = estimateDebtInAsset(_userAddr, user.borrowedAssets[i]);
            debtUSD += adapter.toUSD(asset.addr, debt);
        }
    }

    function calcEstimateUserRewards(address _user) public view returns (uint256 result) {
        Sio2Adapter.User memory user = adapter.getUser(_user);
        string[] memory bAssets = user.borrowedAssets;
        uint256 bAssetsLen = bAssets.length;
        uint256 collectedRewards = user.rewards;
        result = collectedRewards;

        // iter by user's bTokens
        for (uint256 i; i < bAssetsLen; i = _incrementUnchecked(i)) {
            Asset memory asset = assetInfo[bAssets[i]];
            uint256 debt = estimateDebtInAsset(_user, bAssets[i]);
            result += debt * asset.accBorrowedRewardsPerShare / rewardsPrecision -
                adapter.userBorrowedRewardDebt(_user, bAssets[i]);
        }
        
        result += user.collateralAmount * adapter.accCollateralRewardsPerShare() /
            rewardsPrecision - user.collateralRewardDebt;
    }

    function estimateDebtInAsset(address _userAddr, string memory _assetName) public view returns (uint256) {
        Asset memory asset = assetInfo[_assetName];

        uint256 bIncomeDebt = adapter.userBTokensIncomeDebt(_userAddr, _assetName);
        uint256 estDebt = adapter.debts(_userAddr, _assetName);
        uint256 estAccBTokens = asset.accBTokensPerShare;

        uint256 income;
        uint256 curBBal = ERC20Upgradeable(asset.bTokenAddress).balanceOf(address(adapter));
        uint256 curBBal18Dec = to18DecFormat(asset.bTokenAddress, curBBal);
        if (curBBal18Dec > asset.lastBTokenBalance) {
            income = curBBal18Dec - asset.lastBTokenBalance;
        }

        if (curBBal18Dec > 0 && income > 0) {
            estAccBTokens += income * rewardsPrecision / curBBal18Dec;
            estDebt += estDebt * estAccBTokens / rewardsPrecision - bIncomeDebt;
        }

        return estDebt;
    }

    /// @notice To get the available amount to borrow expressed in usd
    function availableCollateralUSD(
        address _userAddr
    ) public view returns (uint256 toBorrow, uint256 toWithdraw) {
        Sio2Adapter.User memory user = adapter.getUser(_userAddr);
        if (user.collateralAmount == 0) return (0, 0);
        uint256 debt = calcEstimateUserDebtUSD(_userAddr);
        uint256 userCollateral = calcEstimateUserCollateralUSD(_userAddr);
        uint256 collateralAfterLTV = (userCollateral * adapter.collateralLTV()) /
            1e4; // 1e4 is RISK_PARAMS_PRECISION
        if (collateralAfterLTV > debt) toBorrow = collateralAfterLTV - debt;
        uint256 debtAfterLTV = (debt * 1e4) / adapter.collateralLTV();
        if (userCollateral > debtAfterLTV)
            toWithdraw = userCollateral - debtAfterLTV;
    }

    function getBTokens() external view returns (address[] memory) {
        return bTokens;
    }

    function getAssetsNames() external view returns (string[] memory) {
        return assets;
    }

    function getRewardsWeight(string memory assetName) external view returns (uint256) {
        return assetInfo[assetName].rewardsWeight;
    }

    /// @notice Get available tokens to borrow for user and asset
    function getAvailableTokensToBorrow(
        address _user
    ) external view returns (uint256[] memory) {
        (uint256 availableColForBorrowUSD,) = availableCollateralUSD(_user);

        uint256 assetLength = assets.length;

        string[] memory assetNames = new string[](assetLength);
        uint256[] memory amounts = new uint256[](assetLength);

        assetNames = assets;

        for (uint256 i; i < assetLength; i++) {
            address assetAddr = assetInfo[assetNames[i]].addr;
            amounts[i] = adapter.fromUSD(assetAddr, availableColForBorrowUSD);
        }        
        
        return amounts;
    }
    
    /// @notice Get arrays of asset names and its amounts for ui
    function getAvailableTokensToRepay(
        address _user
    ) external view returns (
        string[] memory, 
        uint256[] memory
    ) {
        Sio2Adapter.User memory user = adapter.getUser(_user);
        string[] memory assetNames = new string[](user.borrowedAssets.length);
        uint256[] memory debtAmounts = new uint256[](user.borrowedAssets.length);
        assetNames = user.borrowedAssets;
        uint256 assetLength = assetNames.length;

        for (uint256 i; i < assetLength; i++) {
            debtAmounts[i] = estimateDebtInAsset(_user, assetNames[i]);
        }

        return (assetNames, debtAmounts);
    }

    /// @notice Used to get assets params
    function getAssetParameters(
        address _assetAddr
    )
        external
        view
        returns (
            uint256 liquidationThreshold,
            uint256 liquidationPenalty,
            uint256 loanToValue
        )
    {
        DataTypes.ReserveConfigurationMap memory data = pool.getConfiguration(
            _assetAddr
        );
        liquidationThreshold = data.getLiquidationThreshold();
        liquidationPenalty = data.getLiquidationBonus();
        loanToValue = data.getLtv();
    }

    /// @notice If token decimals is different from 18, 
    ///         add the missing number of zeros for correct calculations
    function to18DecFormat(address _tokenAddress, uint256 _amount) public view returns (uint256) {
        if (ERC20Upgradeable(_tokenAddress).decimals() < 18) {
            return _amount * 10 ** (18 - ERC20Upgradeable(_tokenAddress).decimals());
        }
        return _amount;
    }

    function toNativeDecFormat(
        address _tokenAddress,
        uint256 _amount
    ) external view returns (uint256) {
        if (ERC20Upgradeable(_tokenAddress).decimals() < 18) {
            return
                _amount /
                10 ** (18 - ERC20Upgradeable(_tokenAddress).decimals());
        }
        return _amount;
    }

    function getAssetInfo(string memory _assetName) external view returns (Asset memory) {
        return assetInfo[_assetName];
    }

    /// @notice Get share of n tokens in pool for user
    function calc(address _user) external view returns (uint256) {
        Sio2Adapter.User memory user = adapter.getUser(_user);
        return user.collateralAmount;
    }

    function getAssetWeight(address asset) external view returns (uint256) {
        ISio2IncentivesController ic = ISio2IncentivesController(adapter.incentivesController());

        address[] memory assets = pool.getReservesList();
        uint256 sumOfCollateralWeights;
        uint256 assetLength = assets.length;

        for (uint256 i; i < assetLength; i = _incrementUnchecked(i)) {
            DataTypes.ReserveData memory data = pool.getReserveData(assets[i]);
            address sTokenAddress = data.STokenAddress;
            (uint256 initSupply, , , , ) = ic.assets(sTokenAddress);
            sumOfCollateralWeights += initSupply;
        }

        (uint256 assetWeight, , , , ) = ic.assets(asset);
        return assetWeight * 1e2 / sumOfCollateralWeights;
    }

    function _incrementUnchecked(uint256 i) internal pure returns (uint256) {
        unchecked { return ++i; }
    }
}