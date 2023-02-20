// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/Sio2AdapterAssetManager.sol";
import "../src/Sio2Adapter.sol";
import "../src/interfaces/ISio2LendingPool.sol";

contract DeployAdapter is Script {
    Sio2AdapterAssetManager managerImpl;
    TransparentUpgradeableProxy managerProxy;
    Sio2Adapter adapterImpl;
    TransparentUpgradeableProxy adapterProxy;
    Sio2AdapterAssetManager managerWrappedProxy;
    Sio2Adapter adapterWrappedProxy;

    ProxyAdmin admin;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        admin = new ProxyAdmin();

        managerImpl = new Sio2AdapterAssetManager();
        adapterImpl = new Sio2Adapter();
        
        // deploy proxy contract and point it to implementation
        managerProxy = new TransparentUpgradeableProxy(address(managerImpl), address(admin), "");
        adapterProxy = new TransparentUpgradeableProxy(address(adapterImpl), address(admin), "");
        
        managerWrappedProxy = Sio2AdapterAssetManager(address(managerProxy));
        managerWrappedProxy.initialize(
            ISio2LendingPool(0x4df48B292C026f0340B60C582f58aa41E09fF0de)
        );

        adapterWrappedProxy = Sio2Adapter(address(adapterProxy));
        adapterWrappedProxy.initialize(
            ISio2LendingPool(0x4df48B292C026f0340B60C582f58aa41E09fF0de),
            IERC20Upgradeable(0x6De33698e9e9b787e09d3Bd7771ef63557E148bb), //nASTR addr, but now its DAI for testing
            IERC20Upgradeable(0x7eC11c9aA33a2A306588a95e152C3Ec1855e2204), //snASTR, but now sDAI for testing
            ISio2IncentivesController(0xc41e6Da7F6E803514583f3b22b4Ff660CCD39B03),
            IERC20Upgradeable(0xcCA488aEEf7A1D5C633f877453784F025e7cF160), //reward token sio2
            Sio2AdapterAssetManager(0xa2D7550860E80DBB922258A1b34BA30bfe5c38A5),
            ISio2PriceOracle(0x5f7c3639A854a27DFf64B320De5C9CAF9C4Bd323)
        );

        // in assetManager setAdapter
        managerWrappedProxy.setAdapter(Sio2Adapter(address(adapterProxy)));

        // add assets in assetManager
        managerWrappedProxy.addAsset(
            "BUSD",
            0x4Bf769b05E832FCdc9053fFFBC78Ca889aCb5E1E, //Token
            0xC4Cf823f6A94699d9C6D22Aec73522D4c00867C8, //vdToken
            8 //rewardsWeight
        );

        // add some nastr to supply
        IERC20Upgradeable daiToken = IERC20Upgradeable(0x6De33698e9e9b787e09d3Bd7771ef63557E148bb);
        daiToken.approve(
            address(adapterProxy),
            1e36
        );
        adapterWrappedProxy.supply(1e15);

        // run setup() in adapter 
        adapterWrappedProxy.setup();

        console.log("adapter proxy address:", address(adapterProxy));
        console.log("assetManater proxy address:", address(managerProxy));

        vm.stopBroadcast();
    }
}

// == Logs ==
// adapter proxy address: 0xD8c9f1117d2ad6E826A8b62b3DB5dD000fd4Dace
// assetManager proxy address: 0x5b80246204c2b3214Dd4679c99099dD0e0b1Dcab