//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./interfaces/ISio2LendingPool.sol";
import "./interfaces/IERC20Plus.sol";
import "./Sio2AdapterAssetManager.sol";
import "./Sio2Adapter.sol";

contract Sio2AdapterData is Initializable {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    Sio2Adapter private adapter;
    Sio2AdapterAssetManager private assetManager;
    ISio2LendingPool private lendingPool;

    uint256 private constant RISK_PARAMS_PRECISION = 1e4;

    uint256 private collateralLT;
    uint256 private collateralLTV;

    address private collateralAddr;
    address private dotAddr = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF; 
    address private wastrAddr = 0xAeaaf0e2c81Af264101B9129C00F4440cCF0F720; 
    address private baiAddr = 0x733ebcC6DF85f8266349DEFD0980f8Ced9B45f35; 
    address private ceusdcAddr = 0x6a2d262D56735DbA19Dd70682B39F6bE9a931D98; 
    address private ceusdtAddr = 0x3795C36e7D12A8c252A20C5a7B455f7c57b60283; 
    address private busdAddr = 0x4Bf769b05E832FCdc9053fFFBC78Ca889aCb5E1E; 
    address private daiAddr = 0x6De33698e9e9b787e09d3Bd7771ef63557E148bb; 
    address private wethAddr = 0x81ECac0D6Be0550A00FF064a4f9dd2400585FE9c; 
    address private wbtcAddr = 0xad543f18cFf85c77E140E3E5E3c3392f6Ba9d5CA; 
    address private bnbAddr = 0x7f27352D5F83Db87a5A3E00f4B07Cc2138D8ee52; 

    struct AssetRatesInfo {
        uint256 uOptimal;
        uint256 rSlope1;
        uint256 rSlope2;
    }

    mapping(address => AssetRatesInfo) public assets;

    function initialize(
        Sio2Adapter _adapter, 
        Sio2AdapterAssetManager _assetManager,
        ISio2LendingPool _lendingPool
    ) external initializer {
        adapter = _adapter;
        assetManager = _assetManager;
        lendingPool = _lendingPool;
        collateralLT = assetManager.getLT();
        collateralLTV = assetManager.getLTV();
        collateralAddr = address(adapter.nastr());
    }

    function estimateHF(address _user) external view returns (uint256 hf) {
        uint256 collateralUSD = assetManager.calcEstimateUserCollateralUSD(_user);

        // get est borrowed accRPS for assets
        // calc est user's debt
        uint256 debtUSD = assetManager.calcEstimateUserDebtUSD(_user);

        if (debtUSD == 0) return ~uint256(0);

        hf = (collateralUSD * assetManager.getLT() * 1e18) /
            RISK_PARAMS_PRECISION / debtUSD;
    }

    function supplyWithdrawShift(address _user, uint256 _amount, bool isSupply) external view returns (
        uint256[] memory,
        uint256[] memory
    ) {
        uint256[] memory before = new uint256[](3);
        uint256[] memory later = new uint256[](3);
        
        // 0 - borrow available
        // 1 - borrow limit used
        // 2 - health factor

        (uint256 availableToBorrowUSD, uint256 availableToWithdrawUSD) = assetManager.availableCollateralUSD(_user);
        uint256 inputDelta = adapter.toUSD(collateralAddr, _amount);
        uint256 inputDeltaLTV = inputDelta * assetManager.getLTV() / RISK_PARAMS_PRECISION;
        uint256 currentDebtUSD = assetManager.calcEstimateUserDebtUSD(_user);
        uint256 currentCollateralUSD = assetManager.calcEstimateUserCollateralUSD(_user);

        if (inputDeltaLTV == 0) inputDeltaLTV = 1;

        before[0] = availableToBorrowUSD; 

        if (availableToBorrowUSD == 0) {
            before[1] = 1e18;
        } else {
            before[1] = currentDebtUSD * 1e18 / availableToBorrowUSD;
        }

        if (currentDebtUSD == 0) {
            before[2] = type(uint256).max;
        } else {
            before[2] = currentCollateralUSD * assetManager.getLT() * 1e18 / RISK_PARAMS_PRECISION / currentDebtUSD;
        }

        if (isSupply) {
            later[0] = availableToBorrowUSD + inputDeltaLTV;
            later[1] = currentDebtUSD * 1e18 / (availableToBorrowUSD + inputDeltaLTV);
            if (currentDebtUSD == 0) {
                later[2] = type(uint256).max;
            } else {
                later[2] = (currentCollateralUSD + inputDelta) * assetManager.getLT() * 1e18 / RISK_PARAMS_PRECISION / currentDebtUSD;
            }
        } else {
            availableToBorrowUSD >= inputDeltaLTV ? 
                later[0] = availableToBorrowUSD - inputDeltaLTV :
                later[0] = 0;
            availableToBorrowUSD > currentDebtUSD + inputDeltaLTV ?
                later[1] = currentDebtUSD * 1e18 / (availableToBorrowUSD - inputDeltaLTV) :
                later[1] = 1e18;
            if (currentDebtUSD == 0) {
                later[2] = type(uint256).max;
            } else {
                currentCollateralUSD >= inputDelta + currentDebtUSD * RISK_PARAMS_PRECISION / assetManager.getLT() / 1e18 ?
                    later[2] = (currentCollateralUSD - inputDelta) * assetManager.getLT() * 1e18 / RISK_PARAMS_PRECISION / currentDebtUSD :
                    later[2] = 0;
            }
        }

        return (before, later);
    }

    function borrowRepayShift(
        address _user, 
        uint256 _amount, 
        string memory _assetName,
        bool isBorrow
    ) external view returns (
        uint256[] memory,
        uint256[] memory
    ) {
        uint256[] memory before = new uint256[](3);
        uint256[] memory later = new uint256[](3);

        // 0 - borrowed
        // 1 - borrow limit used
        // 2 - health factor

        Sio2AdapterAssetManager.Asset memory asset = assetManager.getAssetInfo(_assetName);
        (uint256 availableToBorrowUSD, uint256 availableToWithdrawUSD) = assetManager.availableCollateralUSD(_user);
        uint256 debtUSD = assetManager.calcEstimateUserDebtUSD(_user);
        uint256 amountUSD = adapter.toUSD(asset.addr, _amount);
        uint256 currentCollateralUSD = assetManager.calcEstimateUserCollateralUSD(_user);

        if (amountUSD == 0) amountUSD = 1;

        before[0] = debtUSD;
        if (availableToBorrowUSD == 0) {
            before[1] = 1e18;
        } else {
            before[1] = debtUSD * 1e18 / (debtUSD + availableToBorrowUSD);
        }
        if (currentCollateralUSD != 0 && debtUSD == 0) {
            before[2] = type(uint256).max;
        } else if (currentCollateralUSD == 0 && debtUSD == 0) {
            before[2] = 0;
        } else {
            before[2] = currentCollateralUSD * assetManager.getLT() * 1e18 / RISK_PARAMS_PRECISION / debtUSD;
        }

        if (isBorrow) {
            later[0] = debtUSD + amountUSD;
            if (availableToBorrowUSD == 0) {
                later[1] = 1e18;
            } else {
                later[1] = (debtUSD + amountUSD) * 1e18 / (debtUSD + availableToBorrowUSD);
            }
            later[2] = currentCollateralUSD * assetManager.getLT() * 1e18 / RISK_PARAMS_PRECISION / (debtUSD + amountUSD);
        } else {
            if (debtUSD > amountUSD) {
                later[0] = debtUSD - amountUSD;

                if (availableToBorrowUSD == 0) {
                    later[1] = 1e18;
                } else {
                    later[1] = (debtUSD - amountUSD) * 1e18 / (debtUSD + availableToBorrowUSD);
                }
                
                later[2] = currentCollateralUSD * assetManager.getLT() * 1e18 / RISK_PARAMS_PRECISION / (debtUSD - amountUSD);
            } else {
                later[0] = 0;
                later[1] = 0;
                later[2] = 10e18;
            }
        }

        return (before, later);
    }

    function getBorrowAssetLiquidity(string memory _assetName) external view returns (uint256) {
        Sio2AdapterAssetManager.Asset memory asset = assetManager.getAssetInfo(_assetName);
        address tokenAddr = asset.addr;

        DataTypes.ReserveData memory data = lendingPool.getReserveData(tokenAddr);
        address sTokenAddr = data.STokenAddress;
        address vdTokenAddr = data.variableDebtTokenAddress;

        uint256 sTokenSupply = ERC20Upgradeable(sTokenAddr).totalSupply();
        uint256 vdTokenSupply = ERC20Upgradeable(vdTokenAddr).totalSupply();

        return sTokenSupply - vdTokenSupply;
    }

    function getAPY(string memory _assetName) public view returns (uint256 interestRate, uint256 depositApy) {
        Sio2AdapterAssetManager.Asset memory asset = assetManager.getAssetInfo(_assetName);
        address assetAddr = asset.addr;

        DataTypes.ReserveConfigurationMap memory data = lendingPool.getConfiguration(asset.addr);
        
        (uint256 amountB, uint256 amountS) = _getSupplies(assetAddr);
        uint256 utilizationRate = amountB * 1 ether / amountS;
        AssetRatesInfo memory rates = assets[assetAddr];
        if (rates.uOptimal <= utilizationRate) {
            interestRate = (rates.rSlope1 + (utilizationRate - rates.uOptimal) * rates.rSlope2 / (1 - rates.uOptimal)) / 1 ether;
        } else {
            interestRate = utilizationRate * rates.rSlope1 / rates.uOptimal;
        }
        depositApy = utilizationRate * interestRate * (10000 - data.getReserveFactor()) / 10000 / 1e18;
    }

    function getAPR(string memory _assetName, uint256 _monthsPassed, bool _isSupplyApr) public view returns (uint256) {
        uint256 weight;
        address assetAddr;
        if (keccak256(abi.encodePacked(_assetName)) == keccak256("nASTR")) {
            assetAddr = collateralAddr;
            weight = 11;
        } else {
            Sio2AdapterAssetManager.Asset memory asset = assetManager.getAssetInfo(_assetName);
            weight = asset.rewardsWeight;
            assetAddr = asset.addr;
        }
        (uint256 borrowed, uint256 supplied) = _getSupplies(assetAddr);
        uint256 suppliedUSD = adapter.toUSD(assetAddr, supplied);
        uint256 borowedUSD = adapter.toUSD(assetAddr, borrowed);
        if (_isSupplyApr) return 1e36 * getRewardsByMonth(_monthsPassed) * weight * 12 / suppliedUSD / 10000;
        if (!_isSupplyApr) return 1e36 * getRewardsByMonth(_monthsPassed) * weight * 12 / borowedUSD / 10000;
    }

    function getRewardsByMonth(uint256 n) public pure returns (uint256) {
        uint256 init = 2e6;
        uint256 rew = init;
        uint256 rew1;
        for (uint256 i; i < n; i++) {
            rew += (init * 98 ** (i)) / (100 ** (i));
            if (i + 2 == n) rew1 = rew;
            if (i + 1 == n) return rew - rew1;
        }
    }

    function getSupplies(string memory _assetName) external view returns (uint256, uint256) {
        Sio2AdapterAssetManager.Asset memory asset = assetManager.getAssetInfo(_assetName);
        return _getSupplies(asset.addr);
    }

    function _getSupplies(address assetAddr) public view returns (uint256, uint256) {
        DataTypes.ReserveData memory data = lendingPool.getReserveData(assetAddr);
        IERC20Plus sToken = IERC20Plus(data.STokenAddress);
        IERC20Plus vdToken = IERC20Plus(data.variableDebtTokenAddress);

        return (vdToken.scaledTotalSupply(), sToken.scaledTotalSupply());
    }
}