// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../src/Sio2Adapter.sol";
import "../src/Sio2AdapterAssetManager.sol";
import "./mocs/MockSio2LendingPool.sol";
import "./mocs/MockERC20.sol";
import "./mocs/MockSCollateralToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Upgradeable.sol";

contract Sio2AdapterTest is Test {
    Sio2Adapter public adapter;
    Sio2AdapterAssetManager public assetManager;

    MockSio2LendingPool public pool;
    MockERC20 public nastr;
    MockERC20 public rewardToken;
    MockSCollateralToken public snastr;
    ISio2IncentivesController public incentivesController;

    address public user1;

    function setUp() public {
        pool = new MockSio2LendingPool();

        nastr = new MockERC20();
        nastr.initialize("nASTR", "nASTR");

        snastr = new MockSCollateralToken();
        snastr.initialize("snASTR", "snASTR");

        rewardToken = new MockERC20();
        rewardToken.initialize("SIO2", "SIO2");

        assetManager = new Sio2AdapterAssetManager();
        assetManager.initialize(ISio2LendingPool(address(pool)));
        
        adapter = new Sio2Adapter();
        adapter.initialize(
            ISio2LendingPool(address(pool)),
            IERC20Upgradeable(nastr),
            IERC20Upgradeable(snastr),
            incentivesController,
            IERC20Upgradeable(rewardToken),
            assetManager
        );

        user1 = vm.addr(1); // convert private key to address
        vm.deal(user1, 5 ether); // add ether to user1
    }

    function testSupply() public {
        nastr.mint(user1, 1000);
        console.log("User balance is:", nastr.balanceOf(user1));
    }
}