// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../src/Sio2Adapter.sol";
import "../src/Sio2AdapterAssetManager.sol";
import "../src/interfaces/ISio2LendingPool.sol";
import "../src/Liquidator.sol";
import "./mocs/MockSio2LendingPool.sol";
import "./mocs/MockERC20.sol";
import "./mocs/MockSCollateralToken.sol";
import "./mocs/MockPriceOracle.sol";
import "./mocs/MockVDToken.sol";
import "./mocs/MockProvider.sol";
import "./mocs/MockIncentivesController.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "../src/interfaces/ISio2LendingPoolAddressesProvider.sol";
import "../src/interfaces/ISio2LendingPool.sol";

contract Sio2AdapterTest is Test {
    Sio2Adapter adapter;
    Sio2AdapterAssetManager assetManager;
    Sio2AdapterData data;

    ISio2LendingPool pool;
    ERC20Upgradeable nastr;
    MockERC20 rewardToken;
    ERC20Upgradeable busd;
    ERC20Upgradeable dot;
    MockVDToken vddot;
    MockERC20 dai;
    MockVDToken vddai;
    MockERC20 usdc;
    MockVDToken vdusdc;
    MockERC20 usdt;
    MockVDToken vdusdt;
    MockSCollateralToken snastr;
    MockVDToken vdbusd;
    ISio2PriceOracle priceOracle;
    ISio2IncentivesController incentivesController;
    Liquidator liquidatorContract;

    address provider;
    address user;
    address liquidator;
    address supplier;

    uint256 dot_precision = 1e8;

    function setUp() public {
        // nastr = new MockERC20("nASTR", "nASTR"); 

        nastr = ERC20Upgradeable(0xE511ED88575C57767BAfb72BfD10775413E3F2b0);
        busd = ERC20Upgradeable(0x4Bf769b05E832FCdc9053fFFBC78Ca889aCb5E1E);
        // dot = ERC20Upgradeable(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

        snastr = new MockSCollateralToken("snASTR", "snASTR");
        // busd = new MockERC20("BUSD", "BUSD");
        vdbusd = new MockVDToken("vdBUSD", "vdBUSD");
        rewardToken = new MockERC20("SIO2", "SIO2");
        // dot = new MockERC20("DOT", "DOT");
        // dot.setDecimals(10);
        vddot = new MockVDToken("vdDOT", "vdDOT");
        vddot.setDecimals(10);
        dai = new MockERC20("DAI", "DAI");
        vddai = new MockVDToken("vdDAI", "vdDAI");
        usdc = new MockERC20("USDC", "USDC");
        vdusdc = new MockVDToken("vdUSDC", "vdUSDC");
        usdc.setDecimals(6);
        vdusdc.setDecimals(6);
        usdt = new MockERC20("USDT", "USDT");
        vdusdt = new MockVDToken("vdUSDT", "vdUSDT");
        usdt.setDecimals(6);
        vdusdt.setDecimals(6);

        // incentivesController = new MockIncentivesController(
        //     snastr,
        //     vdbusd,
        //     rewardToken
        // );

        incentivesController = ISio2IncentivesController(0xc41e6Da7F6E803514583f3b22b4Ff660CCD39B03);

        // pool = new ISio2LendingPool(
        //     snastr,
        //     nastr,
        //     busd,
        //     dot,
        //     vdbusd,
        //     vddot,
        //     dai,
        //     vddai,
        //     usdc,
        //     vdusdc,
        //     usdt,
        //     vdusdt
        // );
        pool = ISio2LendingPool(0x4df48B292C026f0340B60C582f58aa41E09fF0de);

        provider = address(new MockProvider(address(pool)));

        assetManager = new Sio2AdapterAssetManager();
        assetManager.initialize(
            ISio2LendingPool(address(pool)),
            address(snastr)
        );

        assetManager.addAsset(address(busd), address(vdbusd), 8);

        // assetManager.addAsset(address(dot), address(vddot), 12);

        // priceOracle = new MockPriceOracle(
        //     address(nastr),
        //     address(busd),
        //     address(dot),
        //     address(dai),
        //     address(usdc),
        //     address(usdt)
        // );

        priceOracle = ISio2PriceOracle(0x5f7c3639A854a27DFf64B320De5C9CAF9C4Bd323);

        adapter = new Sio2Adapter();
        adapter.initialize(
            ISio2LendingPool(address(pool)),
            IERC20Upgradeable(address(nastr)),
            IERC20Upgradeable(address(snastr)),
            ISio2IncentivesController(address(incentivesController)),
            IERC20Upgradeable(address(rewardToken)),
            assetManager,
            ISio2PriceOracle(address(priceOracle))
        );

        assetManager.setAdapter(adapter);
        data = new Sio2AdapterData();
        data.initialize(adapter, assetManager, ISio2LendingPool(address(pool)));

        user = vm.addr(1); // convert private key to address
        liquidator = vm.addr(2);
        supplier = 0xC8DB8d99121961D316d249b4D868D801deBD6e86; // the address with 100kk nASTR balance

        liquidatorContract = new Liquidator(
            ISio2LendingPool(address(pool)),
            adapter,
            assetManager,
            ISio2LendingPoolAddressesProvider(provider),
            data,
            address(nastr)
        );
        liquidatorContract.grantRole(liquidatorContract.LIQUIDATOR(), user);

        vm.deal(user, 1e10 ether); // add ether to user
        // nastr.mint(user, 1e72);        
        // busd.mint(liquidator, 1e36);
        // dot.mint(liquidator, 1e36);

        vm.startPrank(supplier);
        nastr.transfer(user, 100000 ether);
        vm.stopPrank();

        vm.prank(user);
        nastr.approve(address(adapter), 1e36);
    }

    function testSupply() public {
        uint256 bal = nastr.balanceOf(user);
        uint256 amount = 1 ether;

        vm.startPrank(user);

        vm.expectRevert("Should be greater than zero");
        adapter.supply(0);

        vm.expectRevert("Not enough nASTR tokens on the user balance");
        adapter.supply(UINT256_MAX);

        adapter.supply(amount);

        assertEq(snastr.balanceOf(address(adapter)), amount);
        assertEq(nastr.balanceOf(user), bal - amount);

        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(user);

        adapter.supply(1 ether);
        (, , uint256 colBefore, , , , ) = adapter.userInfo(user);
        assertEq(colBefore, 1 ether);

        adapter.withdraw(1 ether);
        (, , uint256 colAfter, , , , ) = adapter.userInfo(user);
        assertEq(colAfter, 0);

        vm.stopPrank();
    }

    function testBorrow() public {
        vm.startPrank(user);
        adapter.supply(10000 ether); // supply 10000 nASTR
        adapter.borrow("BUSD", 1 ether); // borrow 1 BUSD
        adapter.borrow("DOT", 1 ether);
        vm.warp(1 days);
        adapter.borrow("BUSD", 1 ether);
        adapter.borrow("DOT", 1 ether);
        uint256 debt = assetManager.calcEstimateUserDebtUSD(user);
        assertEq(busd.balanceOf(user), 2 ether);
        assertGt(dot.balanceOf(user), 0);
        assertGt(debt, 0);
        vm.stopPrank();
    }

    function testRepay() public {
        vm.startPrank(user);
        adapter.supply(1000 ether);
        adapter.borrow("BUSD", 10 ether);

        vm.expectRevert();
        adapter.repayPart("DOT", 5 ether);

        adapter.borrow("DOT", 1 ether);
        assertEq(busd.balanceOf(user), 10 ether);
        // assertEq(dot.balanceOf(user), 1 ether / dot_precision);
        busd.approve(address(adapter), 10 ether);
        dot.approve(address(adapter), 10 ether);

        //test repay part
        vm.expectRevert("Not enough wallet balance to repay");
        adapter.repayPart("BUSD", 15 ether);

        vm.expectRevert("Amount should be greater than zero");
        adapter.repayPart("BUSD", 0);

        adapter.repayPart("BUSD", 5 ether);
        assertEq(busd.balanceOf(user), 5 ether);
        uint256 debtPart = adapter.debts(user, "BUSD");
        assertEq(debtPart, 5 ether);

        //test repay full
        adapter.repayFull("BUSD");
        assertEq(busd.balanceOf(user), 0);
        uint256 debtFull = adapter.debts(user, "BUSD");
        assertEq(debtFull, 0);

        //test repay full dot
        adapter.repayFull("DOT");
        assertEq(dot.balanceOf(user), 0);

        vm.stopPrank();
    }

    function testGetHF() public {
        vm.startPrank(user);
        adapter.supply(1000 ether);
        adapter.borrow("BUSD", 10 ether);
        (uint256 hf, uint256 debtUSD) = adapter.getLiquidationParameters(user);
        uint256 estimateHF = data.estimateHF(user);
        assertEq(hf, estimateHF);
        assertGt(hf, 0);
        vm.stopPrank();
    }

    function testClaimRewards() public {
        vm.startPrank(user);

        adapter.supply(1000000 ether);
        adapter.borrow("BUSD", 10 ether);

        vm.expectRevert("User has no any rewards");
        adapter.claimRewards();

        vm.roll(10);

        adapter.claimRewards();

        assertGt(rewardToken.balanceOf(user), 0);
        assertGt(adapter.rewardPool(), 0);

        (, , , uint256 rewards, , , ) = adapter.userInfo(user);
        assertEq(rewards, 0);

        vm.stopPrank();
    }

    function testWithdrawRevenue() public {
        vm.startPrank(user);
        adapter.supply(1000 ether);
        adapter.borrow("BUSD", 10 ether);
        vm.roll(10);
        adapter.claimRewards();
        vm.stopPrank();
        uint256 amount = adapter.revenuePool();
        adapter.withdrawRevenue(amount);
        vm.expectRevert("Should be greater than zero");
        adapter.withdrawRevenue(0);
        vm.expectRevert("Not enough SIO2 revenue tokens");
        adapter.withdrawRevenue(amount);
        assertEq(rewardToken.balanceOf(address(this)), amount);
    }

    function testAddSTokens() public {
        uint256 amount = 10 ether;
        vm.startPrank(user);
        vm.expectRevert("Not enough sTokens on user balance");
        adapter.addSTokens(amount);
        nastr.approve(address(pool), amount);
        pool.deposit(address(nastr), amount, user, 0);
        assertGt(snastr.balanceOf(user), 0);
        assertEq(snastr.balanceOf(address(adapter)), 0);
        snastr.approve(address(adapter), amount);
        adapter.addSTokens(amount / 2);
        adapter.addSTokens(amount / 2);
        assertEq(snastr.balanceOf(user), 0);
        assertGt(snastr.balanceOf(address(adapter)), 0);
        vm.stopPrank();
    }

    function testLiquidationCall() public {
        vm.startPrank(user);
        adapter.supply(100 ether);

        vm.expectRevert("User has no debts");
        adapter.getLiquidationParameters(user);

        vm.expectRevert("User has no debts");
        data.estimateHF(user);

        (uint256 availableToBorrow, ) = assetManager.availableCollateralUSD(user);

        adapter.borrow("BUSD", availableToBorrow);

        vm.stopPrank();

        vm.startPrank(liquidator);
        priceOracle.setAssetPrice(address(busd), 110992110);

        uint256 debtToCover = adapter.debts(user, "BUSD");
        busd.approve(address(adapter), 1e36);

        vm.expectRevert(
            "Debt to cover need to be lower than 50% of users debt"
        );
        adapter.liquidationCall("BUSD", user, debtToCover - 1e17);

        vm.expectRevert("_debtToCover exceeds the user's debt amount");
        adapter.liquidationCall("BUSD", user, debtToCover + 1e17);

        uint256 debt = adapter.debts(user, "BUSD");

        uint256 col = adapter.getUser(user).collateralAmount;

        adapter.liquidationCall("BUSD", user, debtToCover / 2);
        vm.stopPrank();
    }

    function testAvailableCollateralUSD() public {
        vm.prank(user);
        adapter.supply(1 ether);

        (, uint256 availableColToWithdraw) = assetManager.availableCollateralUSD(
            user
        );

        (, , uint256 col, , , , ) = adapter.userInfo(user);
    }

    function testLTAndLTV() public {
        uint256 depositAmount = 10_000 ether;
        uint256 depositAmountInUsd = adapter.toUSD(address(nastr), depositAmount);
        (uint256 collateralLT, uint256 liquidationPenalty, uint256 collateralLTV) =
            assetManager.getAssetParameters(address(nastr));
        console.log("Sio2 LTV:", collateralLTV);
        console.log("Sio2 LT:", collateralLT);
        console.log("Sio2 LP:", liquidationPenalty);
        console.log("LTV:", assetManager.getLTV());
        console.log("LT:", assetManager.getLT());
        vm.startPrank(user);
        adapter.supply(depositAmount);
  
        // Available collateral to borrow and withdraw in USD
        // Mock Price of NASTR is 5340158 ($0.05340158)
        uint256 estCollateralInUsd = assetManager.calcEstimateUserCollateralUSD(user);
        console.log("estCollateralInUsd:", estCollateralInUsd, estCollateralInUsd / 1e18, "USD");
        assertEq(depositAmountInUsd, estCollateralInUsd, "Collateral values don't match");
  
        // Available collateral to borrow and withdraw in USD
        (uint256 availBorrowUSD1, uint256 availWithdrawUSD1) = assetManager.availableCollateralUSD(user);
        console.log("availBorrowUSD before borrow:", availBorrowUSD1, availBorrowUSD1 / 1e18, "USD");
        console.log("availWithdrawUSD before borrow:", availWithdrawUSD1, availWithdrawUSD1 / 1e18, "USD");
        assertEq((depositAmountInUsd * assetManager.getLTV()) / 1e4, availBorrowUSD1, "Available borrow values don't match");
  
        // Borrow all available borrow amount
        adapter.borrow("BUSD", availBorrowUSD1);
        vm.stopPrank();
  
        (uint256 availBorrowUSD2, uint256 availWithdrawUSD2) = assetManager.availableCollateralUSD(user);
        console.log("availBorrowUSD after borrow 2:", availBorrowUSD2, availBorrowUSD2 / 1e18, "USD");
        console.log("availWithdrawUSD after borrow 2:", availWithdrawUSD2, availWithdrawUSD2 / 1e18, "USD");
        assertEq(availBorrowUSD2, 0, "Available borrow amount should be 0");
        assertEq(availWithdrawUSD2, 0, "Available withdraw amount should be 0");
  
        // Get liquidation parameters with ltvFactor = 8000, ltFactor = 12000
        (uint256 hf1,) = adapter.getLiquidationParameters(user);
        console.log("Health factor with ltFactor = 12000:", hf1);
  
        // Get liquidation parameters with ltvFactor = 8000, ltFactor = 10000
        assetManager.setParamsFactors(80000, 10000);
        (uint256 hf2,) = adapter.getLiquidationParameters(user);
        console.log("Health factor with ltFactor = 10000:", hf2);
  
        assertLt(hf1, hf2, "ltFactor = 12000 results in higher health factor!");
    }
}
