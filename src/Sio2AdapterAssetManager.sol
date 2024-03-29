//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./interfaces/ISio2LendingPool.sol";
import "./interfaces/IAdaptersDistributor.sol";
import "./interfaces/ISio2AdapterAssetManager.sol";
import "./Sio2Adapter.sol";
import "./interfaces/ISio2IncentivesController.sol";
import "./interfaces/ISio2PriceOracle.sol";

contract Sio2AdapterAssetManager is
    ISio2AdapterAssetManager,
    Initializable, 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable 
{
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap; // used to extract risk parameters of an asset

    ISio2LendingPool public pool;
    Sio2Adapter public adapter;

    string[] public assets;
    address[] public bTokens;

    mapping(string => Asset) public assetInfo;
    mapping(address => bool) public bTokenExist; // deprecated
    mapping(string => bool) public assetNameExist; // deprecated

    uint256 public maxNumberOfAssets;
    uint256 private rewardsPrecision; // A big number to perform mul and div operations
    address private _grantedOwner;

    // safety params changing Liquidation Threshold and Loan To Value
    uint256 public ltvFactor;
    uint256 public ltFactor;

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
        bool isActive;
    }

    IAdaptersDistributor public constant ADAPTERS_DISTRIBUTOR = IAdaptersDistributor(0x294Bb6b8e692543f373383A84A1f296D3C297aEf);

    uint256 private constant PRICE_PRECISION = 1e8;

    // /// @custom:oz-upgrades-unsafe-allow constructor
    // constructor() {
    //     _disableInitializers();
    // }

    function initialize(
        ISio2LendingPool _pool,
        address _snastr
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        if (address(_pool) == address(0)) revert ZeroAddressLP();
        if (_snastr == address(0)) revert ZeroAddressSNA();

        bTokens.push(_snastr);

        pool = _pool;
        rewardsPrecision = 1e36;
        _setMaxNumberOfAssets(30);
        setParamsFactors(8000, 8000);
    }

    modifier onlyAdapter() {
        if (msg.sender != address(adapter)) revert AllowedOnlyForAdapter();
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
        if (assetInfo[_assetName].addr != address(0)) revert AlreadyAdded();
        if (keccak256(abi.encodePacked(_assetName)) == keccak256("")) revert EmptyAssetName();
        if (assets.length >= maxNumberOfAssets) revert AssetsLimitReached();

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
            accBorrowedRewardsPerShare: 0,
            isActive: true
        });

        assets.push(asset.name);
        assetInfo[_assetName] = asset;
        bTokens.push(_bToken);

        emit AddAsset(msg.sender, _assetName, _assetAddress);
    }

    /// @notice Activate or deactivate the ability to borrow an asset
    function switchAssetStatus(string memory _assetName, bool _isActive) external onlyOwner {
        Asset storage asset = assetInfo[_assetName];

        if (asset.addr == address(0)) revert NoSuchAsset();
        if (asset.isActive == _isActive) revert SameStatus();
        
        asset.isActive = _isActive;

        emit SwitchAssetStatus(msg.sender, _assetName, _isActive);
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
        ADAPTERS_DISTRIBUTOR.updateBalanceInAdapter(
            "Sio2_Adapter",
            _user,
            nastrBalAfter
        );
        emit UpdateBalSuccess(_user, "Sio2_Adapter", nastrBalAfter);
    }

    /// @notice Sets the maximum number of assets
    /// @param _num Number of assets. Equal to 30 by default
    function setMaxNumberOfAssets(uint256 _num) external onlyOwner {
        _setMaxNumberOfAssets(_num);
    }

    function _setMaxNumberOfAssets(uint256 _num) internal {
        if (_num == 0) revert ZeroNumber();
        maxNumberOfAssets = _num;
    }

    /// @notice Set params changing LT and LTV for safety reasons
    /// @dev By default _ltvFactor == 8000 (80%) and _ltFactor == 8000 (80%)
    ///      thus, ltv and lt are decreases by 20%
    function setParamsFactors(uint256 _ltvFactor, uint256 _ltFactor) public onlyOwner {
        _setParamsFactors(_ltvFactor, _ltFactor);
    }

    function _setParamsFactors(uint256 _ltvFactor, uint256 _ltFactor) internal {
        if (_ltvFactor == 0 || _ltFactor == 0) revert ZeroParams();
        ltvFactor = _ltvFactor;
        ltFactor = _ltFactor;
    }

    function updateParams() external onlyAdapter {
        rewardsPrecision = 1e36;
        _setMaxNumberOfAssets(30);
        _setParamsFactors(8000, 8000);
        uint256 len = assets.length;
        // sync accumulated values
        for (uint256 i; i < len; i = _incrementUnchecked(i)) {
            Asset storage asset = assetInfo[assets[i]];
            asset.accBorrowedRewardsPerShare *= 1e24;
            asset.accBTokensPerShare *= 1e24;
            asset.isActive = true;
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // ADMIN LOGIC
    //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice propose a new owner
    function grantOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert ZeroAddressOwner();
        if (_newOwner == owner()) revert SameOwner();
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
                adapter.lastSTokenBalance();
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
            estAccBTokens += income * rewardsPrecision / asset.lastBTokenBalance;
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
        uint256 collateralAfterLTV = (userCollateral * getLTV()) /
            1e4; // 1e4 is RISK_PARAMS_PRECISION
        if (collateralAfterLTV > debt) toBorrow = collateralAfterLTV - debt;
        uint256 debtAfterLTV = (debt * 1e4) / getLTV();
        if (userCollateral > debtAfterLTV)
            toWithdraw = userCollateral - debtAfterLTV;
    }

    function getBTokens() external view returns (address[] memory) {
        return bTokens;
    }

    function getAssetsNames() external view returns (string[] memory) {
        return assets;
    }

    function getActiveAssetsNames() public view returns (string[] memory) {
        uint256 assetsLen = assets.length;
        uint256 activeAssetsLen;

        for (uint256 i; i < assetsLen; i++) {
            Asset memory asset = assetInfo[assets[i]];
            if (asset.isActive) activeAssetsLen++;
        }

        string[] memory activeAssets = new string[](activeAssetsLen);
        uint256 aaIdx;

        for (uint256 i; i < assetsLen; i++) {
            Asset memory asset = assetInfo[assets[i]];
            if (asset.isActive) {
                activeAssets[aaIdx] = assets[i];
                aaIdx++;
            }
        }

        return activeAssets;
    }

    function getRewardsWeight(string memory assetName) external view returns (uint256) {
        return assetInfo[assetName].rewardsWeight;
    }

    /// @notice Get available tokens to borrow for user and asset
    function getAvailableTokensToBorrow(
        address _user
    ) external view returns (string[] memory, uint256[] memory) {
        (uint256 availableColForBorrowUSD, ) = availableCollateralUSD(_user);

        string[] memory activeAssetsNames = getActiveAssetsNames();

        uint256 len = activeAssetsNames.length;

        string[] memory assetNames = new string[](len);
        uint256[] memory amounts = new uint256[](len);

        for (uint256 i; i < len; i++) {
            Asset memory asset = assetInfo[activeAssetsNames[i]];
            amounts[i] = adapter.fromUSD(asset.addr, availableColForBorrowUSD);
        }        
        
        return (activeAssetsNames, amounts);
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
        uint256 dec = ERC20Upgradeable(_tokenAddress).decimals();
        if (dec < 18) return _amount * 10 ** (18 - dec);
        else if (dec > 18) return _amount / 10 ** (dec - 18);
        return _amount;
    }

    function toNativeDecFormat(
        address _tokenAddress,
        uint256 _amount
    ) external view returns (uint256) {
        uint256 dec = ERC20Upgradeable(_tokenAddress).decimals();
        if (dec < 18) return _amount / 10 ** (18 - dec);
        else if (dec > 18) return _amount * 10 ** (dec - 18);
        return _amount;
    }

    function getAssetInfo(string memory _assetName) public view returns (Asset memory) {
        return assetInfo[_assetName];
    }

    /// @notice Get share of n tokens in pool for user
    function calc(address _user) external view returns (uint256) {
        Sio2Adapter.User memory user = adapter.getUser(_user);
        return user.collateralAmount;
    }

    function getAssetWeight(address _asset, ISio2IncentivesController _ic) external view returns (uint256) {
        address[] memory assetsList = pool.getReservesList();
        uint256 sumOfCollateralWeights;
        uint256 assetLength = assetsList.length;

        for (uint256 i; i < assetLength; i = _incrementUnchecked(i)) {
            DataTypes.ReserveData memory data = pool.getReserveData(assetsList[i]);
            address sTokenAddress = data.STokenAddress;
            (uint256 initSupply, , , , ) = _ic.assets(sTokenAddress);
            sumOfCollateralWeights += initSupply;
        }

        (uint256 assetWeight, , , , ) = _ic.assets(_asset);
        return assetWeight * 1e2 / sumOfCollateralWeights;
    }

    /// @notice Calculates active Liquidation Threshold
    function getLT() public view returns (uint256) {
        return adapter.collateralLT() * ltFactor / 10_000;
    }

    /// @notice Calculates active Loan To Value
    function getLTV() public view returns (uint256) {
        return adapter.collateralLTV() * ltvFactor / 10_000;
    }

    /// @notice Convert tokens value to USD
    /// @param _asset Asset address
    /// @param _amount Amount of token with 18 decimals
    /// @return USD price with 18 decimals
    function toUSD(
        address _asset,
        uint256 _amount
    ) public view returns (uint256) {
        uint256 price = ISio2PriceOracle(adapter.priceOracle()).getAssetPrice(_asset);
        return (_amount * price) / PRICE_PRECISION;
    }

    /// @notice Convert tokens value from USD
    /// @param _asset Asset address
    /// @param _amount Price in USD with 18 decimals
    /// @return Token amount with 18 decimals
    function fromUSD(
        address _asset,
        uint256 _amount
    ) public view returns (uint256) {
        uint256 price = ISio2PriceOracle(adapter.priceOracle()).getAssetPrice(_asset);
        return (_amount * PRICE_PRECISION) / price;
    }

    function _incrementUnchecked(uint256 i) internal pure returns (uint256) {
        unchecked { return ++i; }
    }
}