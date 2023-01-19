// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../src/Sio2Adapter.sol";
import "../src/Sio2AdapterAssetManager.sol";

contract Sio2AdapterTest is Test {
    Sio2Adapter public adapter;
    Sio2AdapterAssetManager public assetManager;

    ISio2LendingPool public pool = ISio2LendingPool(0x4df48B292C026f0340B60C582f58aa41E09fF0de);
    IERC20Upgradeable public dai = IERC20Upgradeable(0x6De33698e9e9b787e09d3Bd7771ef63557E148bb);
    IERC20Upgradeable public sdai = IERC20Upgradeable(0x7eC11c9aA33a2A306588a95e152C3Ec1855e2204);
    ISio2IncentivesController public incentivesController = ISio2IncentivesController(0xc41e6Da7F6E803514583f3b22b4Ff660CCD39B03);
    IERC20Upgradeable public sio2token = IERC20Upgradeable(0xcCA488aEEf7A1D5C633f877453784F025e7cF160);
    address public user1;

    function setUp() public {
        assetManager = new Sio2AdapterAssetManager();
        assetManager.initialize(pool);
        adapter = new Sio2Adapter();
        adapter.initialize(
            pool,
            dai,
            sdai,
            incentivesController,
            sio2token,
            assetManager
        );
        user1 = vm.addr(1); // convert private key to address
        vm.deal(user1, 5 ether); // add ether to user1
    }

    function testSupply() public {

    }
}