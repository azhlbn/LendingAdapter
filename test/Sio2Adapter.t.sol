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

    address public user1;

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

        pool = new MockSio2LendingPool(snastr);

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

        user1 = vm.addr(1); // convert private key to address
        vm.deal(user1, 5 ether); // add ether to user1
        nastr.mint(user1, 10e18);
        
        vm.prank(user1);
        nastr.approve(address(adapter), 1000e18);
    }

    function testSupply() public {
        vm.prank(user1);
        adapter.supply(1e18);
    }
}