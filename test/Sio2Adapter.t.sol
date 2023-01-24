// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../src/Sio2Adapter.sol";
import "../src/Sio2AdapterAssetManager.sol";
import "./mocs/MockSio2LendingPool.sol";
import "./mocs/MockERC20.sol";
import "./mocs/MockSCollateralToken.sol";
import "./mocs/MockPriceOracle.sol";
import "./mocs/MockVDToken.sol";
import "./mocs/MockIncentivesController.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

contract Sio2AdapterTest is Test {
    Sio2Adapter public adapter;
    Sio2AdapterAssetManager public assetManager;

    MockSio2LendingPool public pool;
    MockERC20 public nastr;
    MockERC20 public rewardToken;
    MockERC20 public busd;
    MockSCollateralToken public snastr;
    MockVDToken public vdbusd;
    MockPriceOracle public priceOracle;
    MockIncentivesController public incentivesController;

    address public user;

    function setUp() public {
        nastr = new MockERC20("nASTR", "nASTR");
        snastr = new MockSCollateralToken("snASTR", "snASTR");
        busd = new MockERC20("BUSD", "BUSD");
        vdbusd = new MockVDToken("vdBUSD", "vdBUSD");
        rewardToken = new MockERC20("SIO2", "SIO2");

        incentivesController = new MockIncentivesController(
            snastr,
            vdbusd,
            rewardToken
        );

        pool = new MockSio2LendingPool(snastr, nastr, busd, vdbusd);

        assetManager = new Sio2AdapterAssetManager();
        assetManager.initialize(ISio2LendingPool(address(pool)));

        assetManager.addAsset(
            "BUSD",
            address(busd),
            address(vdbusd),
            8
        );

        priceOracle = new MockPriceOracle(address(nastr), address(busd));
        
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

        user = vm.addr(1); // convert private key to address
        vm.deal(user, 5 ether); // add ether to user
        nastr.mint(user, 1000e18);
        
        vm.prank(user);
        nastr.approve(address(adapter), 1e36);

        adapter.setup();
    }

    function testSupply() public {
        uint256 bal = nastr.balanceOf(user);
        uint256 amount = 1 ether;

        vm.prank(user);
        adapter.supply(amount);

        assertEq(snastr.balanceOf(address(adapter)), amount);
        assertEq(nastr.balanceOf(user), bal - amount);
        assertEq(snastr.balanceOf(address(adapter)), amount);
    }

    function testWithdraw() public {
        vm.startPrank(user);

        adapter.supply(1 ether);
        (,,uint256 colBefore,,,) = adapter.userInfo(user);
        assertEq(colBefore, 1 ether);

        adapter.withdraw(1 ether);
        (,,uint256 colAfter,,,) = adapter.userInfo(user);
        assertEq(colAfter, 0);

        vm.stopPrank();
    }

    function testBorrow() public {
        vm.startPrank(user);
        adapter.supply(100 ether); // supply 100 nASTR
        adapter.borrow("BUSD", 1 ether); // borrow 1 BUSD
        assertEq(busd.balanceOf(user), 1 ether);
        vm.stopPrank();
    }

    function testRepay() public {
        vm.startPrank(user);
        adapter.supply(1000 ether);
        adapter.borrow("BUSD", 10 ether);
        assertEq(busd.balanceOf(user), 10 ether);
        busd.approve(address(adapter), 10 ether);

        //test repay part
        adapter.repayPart("BUSD", 5 ether);
        assertEq(busd.balanceOf(user), 5 ether);
        uint256 debtPart = adapter.debts(user, "BUSD");
        assertEq(debtPart, 5 ether);

        //test repay full
        adapter.repayFull("BUSD");
        assertEq(busd.balanceOf(user), 0);
        uint256 debtFull = adapter.debts(user, "BUSD");
        assertEq(debtFull, 0);
        vm.stopPrank();
    }

    function testGetHF() public {
        vm.startPrank(user);
        adapter.supply(1000 ether);
        adapter.borrow("BUSD", 10 ether);
        uint256 hf = adapter.getHF(user);
        uint256 estimateHF = adapter.estimateHF(user);
        assertEq(hf, estimateHF);
        assertGt(hf, 0);
        vm.stopPrank();
    }

    function testClaimRewards() public {
        vm.startPrank(user);
        adapter.supply(1000 ether);
        adapter.borrow("BUSD", 10 ether);
        vm.warp(4 minutes);
        console.log("Time:", block.timestamp);

        uint256 pendingRewards = incentivesController.getUserUnclaimedRewards(address(adapter));
        console.log("unclaimed rewards:", incentivesController.getUserUnclaimedRewards(address(adapter)));
        adapter._harvestRewards(pendingRewards);

        console.log("collRPS:", adapter.accCollateralRewardsPerShare());
        console.log("reweards on adapter:", rewardToken.balanceOf(address(adapter)));

        console.log("reward pool:", adapter.rewardPool());
        console.log("reward weight of busd:", assetManager.getInfo("BUSD"));
        // adapter._updates(msg.sender);
        // adapter.claimRewards();
        // uint256 rewards = rewardToken.balanceOf(user);
        // console.log("Rewards amount is:", rewards);
        // (,,,uint256 rews,,) = adapter.userInfo(user);
        // console.log("REWS:", rews);
        // console.log("unclaimed rewards:", incentivesController.getUserUnclaimedRewards(address(adapter)));
        // console.log("timestamp:", block.timestamp);
        // console.log("last claimed time:", snastr.lastClaimedRewardTime());

        // uint256 accBorrowedRewardsPerShare = assetManager.getAssetsRPS("BUSD");
        // console.log("accBorrowedRewardsPerShare:", accBorrowedRewardsPerShare);

        // uint256 collRPS = adapter.accCollateralRewardsPerShare();
        // console.log("coll RPS:", collRPS);

        // uint256 lastClaimedTime = snastr.lastClaimedRewardTime();
        // console.log("last claimed time:", lastClaimedTime);
    }

    function testToUSD() public {
        uint256 price = adapter._toUSD(address(nastr), 1 ether);
    }

    function testAvailableCollateralUSD() public {
        vm.prank(user);
        adapter.supply(1 ether);

        (,uint256 availableColToWithdraw) = adapter._availableCollateralUSD(user);

        (,, uint256 col,,,) = adapter.userInfo(user);
    }
}