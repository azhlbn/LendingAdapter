// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../src/Sio2Adapter.sol";
import "../src/Sio2AdapterData.sol";
import "../src/Sio2AdapterAssetManager.sol";
import "../src/Liquidator.sol";
import "../src/interfaces/ISio2LendingPoolAddressesProvider.sol";
import "../src/interfaces/ISio2LendingPool.sol";
import "../src/interfaces/ISio2PriceOracle.sol";

contract LiquidatorSingleTest is Test {
    Sio2Adapter adapter;
    Sio2AdapterAssetManager assetManager;
    Liquidator liquidator;
    ISio2LendingPool pool = ISio2LendingPool(0x4df48B292C026f0340B60C582f58aa41E09fF0de);
    Sio2AdapterData data;

    address provider;
    address user;
    address wastr = 0xAeaaf0e2c81Af264101B9129C00F4440cCF0F720; // 18
    address dai = 0x6De33698e9e9b787e09d3Bd7771ef63557E148bb; // 18
    address vdwastr = 0x36100c348c201A7D8242E4CC7BC3Df1e8560f0C1;

    ERC20 wastrT = ERC20(wastr);
    ERC20 daiT = ERC20(dai);

    // sets collateral token
    address col = dai;
    ERC20 scol;
    ERC20 colT = daiT;

    function setUp() public {
        user = 0x7ECD92b9835E0096880bF6bA778d9eA40d1338B5;
        vm.deal(user, 5e36);
        deal(col, user, 1e36 ether);

        vm.startPrank(user);

        scol = new ERC20("Collateral token sDAI", "sDAI");

        assetManager = new Sio2AdapterAssetManager();
        assetManager.initialize(pool, address(scol));
    
        adapter = new Sio2Adapter();
        adapter.initialize(
            pool,
            IERC20Upgradeable(col),
            IERC20Upgradeable(address(scol)),
            ISio2IncentivesController(0xc41e6Da7F6E803514583f3b22b4Ff660CCD39B03),
            IERC20Upgradeable(0xcCA488aEEf7A1D5C633f877453784F025e7cF160),
            assetManager,
            ISio2PriceOracle(0x5f7c3639A854a27DFf64B320De5C9CAF9C4Bd323)
        );

        assetManager.setAdapter(adapter);
        data = new Sio2AdapterData();
        data.initialize(adapter, assetManager, pool);

        liquidator = new Liquidator(
            ISio2LendingPool(0x4df48B292C026f0340B60C582f58aa41E09fF0de),
            Sio2Adapter(payable(address(adapter))),
            Sio2AdapterAssetManager(address(assetManager)),
            ISio2LendingPoolAddressesProvider(0x2660e0668dd5A18Ed092D5351FfF7B0A403f9721),
            data,
            col
        );

        assetManager.addAsset("ASTR", wastr, vdwastr, 8);

        vm.stopPrank();
    }

    modifier prank(address _user) {
        vm.startPrank(_user);
        _;
        vm.stopPrank();
    }

    function testLiquidatorSingle() public prank(user) {
        liquidationPreset();

        uint256 colUSD = collateralUSDValue();
        uint256 atb = availableToBorrowUSD();
        
        console.log("Current hf: ", currentHF(user));
        
        adapter.borrow("ASTR", astrAvailableToBorrow(user));
        console.log("> borrowed");

        console.log("Current hf: ", currentHF(user));

        assetManager.setParamsFactors(8000, 7000);
        console.log("LT sets to 7000");

        console.log("Current hf: ", currentHF(user));

        
    }

    function collateralUSDValue() public view returns (uint256) {
        return assetManager.calcEstimateUserCollateralUSD(user);
    }

    function availableToBorrowUSD() public view returns (uint256) {
        (uint256 avt, ) = assetManager.availableCollateralUSD(user);
        return avt;
    }

    function currentHF(address _user) public view returns (uint256) {
        uint256 hf = data.estimateHF(_user);
        return hf;
    }

    function liquidationPreset() public {
        colT.approve(address(adapter), ~uint256(0));
        adapter.supply(10e18);
    }

    function astrAvailableToBorrow(address _user) public view returns (uint256) {
        (string[] memory assets, uint256[] memory amounts) = assetManager.getAvailableTokensToBorrow(_user);
        return amounts[0];
    }
}